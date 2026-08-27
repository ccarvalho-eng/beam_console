defmodule BeamConsole.Runtime.Supervision do
  @moduledoc """
  Traverses local OTP supervision trees under explicit depth, child, and time limits.

  The traversal is a pure state transition around one isolated runtime call:
  `Supervisor.which_children/1`. Unresponsive branches become partial results
  without blocking the shared collector.
  """

  alias BeamConsole.Config
  alias BeamConsole.EntityId
  alias BeamConsole.Lifecycle.Observation
  alias BeamConsole.Runtime.Supervision.State
  alias BeamConsole.SupervisionEdge

  @module_limit 4

  @type root :: {application :: atom(), supervisor :: pid()}
  @type queue_item :: {application :: atom(), supervisor :: pid(), depth :: non_neg_integer()}
  @type context :: %{
          local_node: node(),
          options: keyword(),
          sequence: non_neg_integer(),
          supervisor_limit: non_neg_integer(),
          children_limit: non_neg_integer(),
          depth_limit: non_neg_integer()
        }
  @type result :: {
          edges :: %{String.t() => SupervisionEdge.t()},
          attribution :: %{String.t() => atom()},
          observations :: [Observation.t()],
          partial_supervisors :: non_neg_integer(),
          traversal_limit_reached? :: boolean()
        }

  @spec collect([root()], node(), keyword()) :: result()
  @doc """
  Collects normalized supervision edges and process-to-application attribution.

  Branches that time out or exit increment the partial count. Reaching a depth,
  supervisor, or child limit sets the final boolean without discarding the
  bounded data collected so far.
  """
  def collect(roots, local_node, options) do
    queue = Enum.map(roots, fn {application, pid} -> {application, pid, 0} end)

    context = %{
      local_node: local_node,
      options: options,
      sequence: Keyword.get(options, :sequence, 0),
      supervisor_limit: Config.get(options, :supervisor_limit),
      children_limit: Config.get(options, :children_limit),
      depth_limit: Config.get(options, :topology_depth)
    }

    state = walk(queue, %State{}, context)

    {
      state.edges,
      state.attribution,
      Enum.reverse(state.observations),
      state.partial,
      state.reached_limit?
    }
  end

  defp walk([], state, _context) do
    state
  end

  defp walk([item | rest], state, context) do
    {application, supervisor, depth} = item

    cond do
      state.children >= context.children_limit ->
        %{state | reached_limit?: true}

      depth > context.depth_limit or
          map_size(state.visited) >= context.supervisor_limit ->
        walk(rest, %{state | reached_limit?: true}, context)

      Map.has_key?(state.visited, supervisor) ->
        walk(rest, state, context)

      true ->
        visit(rest, application, supervisor, depth, state, context)
    end
  end

  defp visit(rest, application, supervisor, depth, state, context) do
    state = %{state | visited: Map.put(state.visited, supervisor, true)}

    case which_children(supervisor, context.options) do
      {:ok, children} ->
        remaining = max(context.children_limit - state.children, 0)
        {included, omitted} = Enum.split(children, remaining)

        batch =
          normalize_children(
            included,
            application,
            supervisor,
            context.local_node,
            depth,
            context.sequence,
            if(omitted == [], do: :complete, else: :truncated)
          )

        next_state = merge_batch(state, batch, omitted != [])
        walk(rest ++ batch.additions, next_state, context)

      {:error, _reason} ->
        walk(rest, %{state | partial: state.partial + 1}, context)
    end
  end

  defp normalize_children(
         children,
         application,
         parent,
         local_node,
         depth,
         sequence,
         coverage
       ) do
    parent_id = EntityId.build(:process, {local_node, parent})

    Enum.reduce(
      children,
      %{edges: %{}, attribution: %{}, observations: [], additions: [], count: 0},
      fn {child_key, child, type, modules}, batch ->
        edge_id = EntityId.build(:edge, {local_node, parent, edge_identity(child_key, child)})
        child_id = if is_pid(child), do: EntityId.build(:process, {local_node, child})

        observation =
          lifecycle_observation(
            child_key,
            child,
            type,
            modules,
            parent,
            local_node,
            sequence,
            coverage
          )

        edge = %SupervisionEdge{
          id: edge_id,
          parent_id: parent_id,
          child_id: child_id,
          label: child_label(child_key, modules),
          state: child_state(child),
          child_type: type
        }

        attribution =
          if child_id do
            Map.put(batch.attribution, child_id, application)
          else
            batch.attribution
          end

        additions =
          if type == :supervisor and is_pid(child) do
            [{application, child, depth + 1} | batch.additions]
          else
            batch.additions
          end

        %{
          edges: Map.put(batch.edges, edge_id, edge),
          attribution: attribution,
          observations: [observation | batch.observations],
          additions: additions,
          count: batch.count + 1
        }
      end
    )
  end

  defp merge_batch(state, batch, truncated?) do
    children = state.children + batch.count

    %{
      state
      | edges: Map.merge(state.edges, batch.edges),
        attribution: Map.merge(state.attribution, batch.attribution),
        observations: batch.observations ++ state.observations,
        children: children,
        reached_limit?: state.reached_limit? or truncated?
    }
  end

  defp which_children(supervisor, options) do
    timeout = Config.get(options, :supervisor_timeout)

    task =
      Task.Supervisor.async_nolink(BeamConsole.TaskSupervisor, fn ->
        Supervisor.which_children(supervisor)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, children} when is_list(children) -> {:ok, children}
      {:exit, reason} -> {:error, reason}
      nil -> {:error, :timeout}
      _other -> {:error, :invalid_children}
    end
  end

  defp child_state(child) when is_pid(child) do
    :running
  end

  defp child_state(:restarting) do
    :restarting
  end

  defp child_state(:undefined) do
    :undefined
  end

  defp child_state(_child) do
    :missing
  end

  defp edge_identity(:undefined, child) when is_pid(child) do
    {:dynamic, child}
  end

  defp edge_identity(child_key, _child) do
    child_key
  end

  defp lifecycle_observation(
         child_key,
         child,
         type,
         modules,
         parent,
         local_node,
         sequence,
         coverage
       ) do
    %Observation{
      slot_id: EntityId.build(:slot, {local_node, parent, slot_identity(child_key, child)}),
      slot_kind: slot_kind(child_key),
      supervisor_pid: parent,
      child_pid: if(is_pid(child), do: child),
      child_state: child_state(child),
      child_type: normalize_child_type(type),
      modules: normalize_modules(modules),
      sequence: sequence,
      coverage: coverage
    }
  end

  defp slot_identity(:undefined, child) when is_pid(child) do
    {:dynamic, child}
  end

  defp slot_identity(child_key, _child) do
    {:stable, child_key}
  end

  defp slot_kind(:undefined) do
    :dynamic
  end

  defp slot_kind(_child_key) do
    :stable
  end

  defp normalize_child_type(type) when type in [:supervisor, :worker] do
    type
  end

  defp normalize_child_type(_type) do
    nil
  end

  defp normalize_modules(modules) when is_list(modules) do
    modules
    |> Enum.filter(&is_atom/1)
    |> Enum.take(@module_limit)
  end

  defp normalize_modules(_modules) do
    []
  end

  defp child_label(:undefined, [module | _modules]) when is_atom(module) do
    EntityId.label(module)
  end

  defp child_label(child_key, _modules) do
    EntityId.label(child_key)
  end
end
