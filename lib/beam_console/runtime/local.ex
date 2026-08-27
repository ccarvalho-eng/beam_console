defmodule BeamConsole.Runtime.Local do
  @moduledoc """
  Collects bounded topology and process details from the local BEAM node.

  The adapter uses standard OTP/runtime APIs and normalizes their results into
  safe BeamConsole structs. Connected nodes are listed but are not queried.
  """

  @behaviour BeamConsole.Runtime.Adapter

  alias BeamConsole.ApplicationInfo
  alias BeamConsole.Config
  alias BeamConsole.Coverage
  alias BeamConsole.EntityId
  alias BeamConsole.NodeInfo
  alias BeamConsole.ProcessDetail
  alias BeamConsole.ProcessInfo
  alias BeamConsole.Runtime.Supervision
  alias BeamConsole.Snapshot

  @process_fields [
    :registered_name,
    :initial_call,
    :memory,
    :reductions,
    :message_queue_len,
    :status
  ]

  @detail_fields @process_fields ++ [:current_function, :links, :monitors, :monitored_by]

  @impl true
  def snapshot(options) do
    started_at = System.monotonic_time(:millisecond)
    sequence = Keyword.get(options, :sequence, 1)
    local_node = node()
    local_node_id = EntityId.build(:node, local_node)
    process_limit = Config.get(options, :process_limit)
    all_pids = Process.list() |> Enum.sort()

    selected_pids =
      all_pids
      |> Enum.reject(&(&1 == self()))
      |> Enum.take(process_limit)

    {processes, vanished} = collect_processes(selected_pids, local_node, local_node_id)
    {applications, roots} = collect_applications(local_node, local_node_id)

    {edges, supervision_attribution, partial_supervisors, traversal_limit_reached?} =
      Supervision.collect(roots, local_node, options)

    processes = apply_supervision_attribution(processes, supervision_attribution)
    completed_at = System.monotonic_time(:millisecond)

    coverage = %Coverage{
      total_pids: length(all_pids),
      inspected_pids: map_size(processes),
      vanished_pids: vanished,
      process_limit_reached?: length(all_pids) > process_limit,
      traversal_limit_reached?: traversal_limit_reached?,
      partial_supervisors: partial_supervisors,
      duration_ms: max(completed_at - started_at, 0),
      warnings: warnings(length(all_pids) > process_limit, partial_supervisors)
    }

    nodes = collect_nodes(local_node)

    snapshot = %Snapshot{
      sequence: sequence,
      sampled_at: DateTime.utc_now(),
      local_node_id: local_node_id,
      nodes: nodes,
      applications: applications,
      processes: processes,
      edges: edges,
      coverage: coverage,
      index: build_index(processes, applications, nodes)
    }

    {:ok, snapshot}
  rescue
    exception -> {:error, {:snapshot_failed, exception}}
  end

  @spec detail(pid(), Snapshot.t(), keyword()) ::
          {:ok, ProcessDetail.t()} | {:error, :unavailable}
  @doc """
  Returns allowlisted details for a local process present in the snapshot.

  The call returns `{:error, :unavailable}` when the PID is remote, has exited,
  or no longer matches a process in the supplied snapshot.
  """
  def detail(pid, snapshot, options \\ []) when is_pid(pid) do
    with true <- node(pid) == node(),
         values when is_list(values) <- Process.info(pid, @detail_fields),
         process_id <- EntityId.build(:process, {node(), pid}),
         %ProcessInfo{} = summary <- Map.get(snapshot.processes, process_id) do
      relationship_limit = Config.get(options, :relationship_limit)

      {:ok,
       %ProcessDetail{
         id: process_id,
         pid_text: summary.pid_text,
         label: summary.label,
         registered_name: normalize_registered_name(values[:registered_name]),
         module: module_label(values[:initial_call]),
         current_function: function_label(values[:current_function]),
         application: summary.application,
         memory: values[:memory],
         reductions: values[:reductions],
         message_queue_len: values[:message_queue_len],
         status: values[:status],
         last_seen_at: snapshot.sampled_at,
         links: normalize_relations(values[:links], relationship_limit),
         monitors: normalize_relations(values[:monitors], relationship_limit),
         monitored_by: normalize_relations(values[:monitored_by], relationship_limit)
       }}
    else
      _other -> {:error, :unavailable}
    end
  end

  defp collect_nodes(local_node) do
    [local_node | Node.list()]
    |> Enum.uniq()
    |> Map.new(fn current_node ->
      id = EntityId.build(:node, current_node)

      info = %NodeInfo{
        id: id,
        name: Atom.to_string(current_node),
        kind: if(current_node == local_node, do: :local, else: :connected),
        inspectable?: current_node == local_node
      }

      {id, info}
    end)
  end

  defp collect_processes(pids, local_node, local_node_id) do
    Enum.reduce(pids, {%{}, 0}, fn pid, {processes, vanished} ->
      case Process.info(pid, @process_fields) do
        nil ->
          {processes, vanished + 1}

        values ->
          process = process_info(pid, values, local_node, local_node_id)
          {Map.put(processes, process.id, process), vanished}
      end
    end)
  end

  defp process_info(pid, values, local_node, local_node_id) do
    id = EntityId.build(:process, {local_node, pid})
    registered_name = normalize_registered_name(values[:registered_name])
    module = module_label(values[:initial_call])
    application = application_for(pid)

    %ProcessInfo{
      id: id,
      node_id: local_node_id,
      pid: pid,
      pid_text: EntityId.label(pid),
      label: process_label(registered_name, module, pid),
      registered_name: registered_name,
      module: module,
      application: application,
      supervision_application: nil,
      attribution: if(application, do: :otp_only, else: :unknown),
      memory: values[:memory],
      reductions: values[:reductions],
      message_queue_len: values[:message_queue_len],
      status: values[:status]
    }
  end

  defp collect_applications(local_node, local_node_id) do
    Application.started_applications()
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce({%{}, []}, fn {name, description, version}, {applications, roots} ->
      id = EntityId.build(:application, {local_node, name})
      root = application_supervisor(name)

      info = %ApplicationInfo{
        id: id,
        name: name,
        node_id: local_node_id,
        description: safe_string(description),
        version: safe_string(version),
        root_supervisor_id: root && EntityId.build(:process, {local_node, root})
      }

      roots = if root, do: [{name, root} | roots], else: roots
      {Map.put(applications, id, info), roots}
    end)
  end

  defp apply_supervision_attribution(processes, attribution) do
    Map.new(processes, fn {id, process} ->
      supervision_application = Map.get(attribution, id)

      attribution_state =
        case {process.application, supervision_application} do
          {nil, nil} -> :unknown
          {nil, _application} -> :supervision_only
          {_application, nil} -> :otp_only
          {application, application} -> :otp_and_supervision
          {_otp_application, _supervision_application} -> :conflict
        end

      {id,
       %{
         process
         | supervision_application: supervision_application,
           attribution: attribution_state
       }}
    end)
  end

  defp build_index(processes, applications, nodes) do
    process_index = Map.new(processes, fn {id, process} -> {id, {:process, process.pid}} end)

    application_index =
      Map.new(applications, fn {id, info} -> {id, {:application, info.name}} end)

    node_index = Map.new(nodes, fn {id, info} -> {id, {:node, info.name}} end)

    process_index
    |> Map.merge(application_index)
    |> Map.merge(node_index)
  end

  defp application_for(pid) do
    case :application.get_application(pid) do
      {:ok, application} -> application
      :undefined -> nil
    end
  end

  defp application_supervisor(application) do
    case :application.get_supervisor(application) do
      {:ok, supervisor} -> supervisor
      :undefined -> nil
    end
  end

  defp normalize_registered_name([]) do
    nil
  end

  defp normalize_registered_name(name) when is_atom(name) do
    name
  end

  defp normalize_registered_name(_name) do
    nil
  end

  defp module_label({module, _function, _arity}) when is_atom(module) do
    Atom.to_string(module)
  end

  defp module_label(_initial_call) do
    nil
  end

  defp function_label({module, function, arity})
       when is_atom(module) and is_atom(function) and is_integer(arity) do
    "#{module}.#{function}/#{arity}"
  end

  defp function_label(_current_function) do
    nil
  end

  defp process_label(name, _module, _pid) when is_atom(name) and not is_nil(name) do
    Atom.to_string(name)
  end

  defp process_label(nil, module, _pid) when is_binary(module) do
    module
  end

  defp process_label(nil, nil, pid) do
    EntityId.label(pid)
  end

  defp safe_string(value) when is_binary(value) do
    EntityId.label(value, 160)
  end

  defp safe_string(value) when is_list(value) do
    value
    |> List.to_string()
    |> EntityId.label(160)
  rescue
    _exception -> nil
  end

  defp safe_string(_value) do
    nil
  end

  defp normalize_relations(relations, limit) when is_list(relations) do
    relations
    |> Enum.take(limit)
    |> Enum.map(&relation_label/1)
  end

  defp normalize_relations(_relations, _limit) do
    []
  end

  defp relation_label(pid) when is_pid(pid) do
    EntityId.label(pid)
  end

  defp relation_label(port) when is_port(port) do
    port |> :erlang.port_to_list() |> List.to_string()
  end

  defp relation_label({kind, pid}) when kind in [:process, :port] do
    relation_label(pid)
  end

  defp relation_label(_relation) do
    "opaque relation"
  end

  defp warnings(true, partial_supervisors) do
    ["Process limit reached" | warnings(false, partial_supervisors)]
  end

  defp warnings(false, partial_supervisors) when partial_supervisors > 0 do
    ["#{partial_supervisors} supervision branches were partial"]
  end

  defp warnings(false, _partial_supervisors) do
    []
  end
end
