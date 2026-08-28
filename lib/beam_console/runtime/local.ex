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
  alias BeamConsole.ProcessRelation
  alias BeamConsole.Runtime.Sample, as: RuntimeSample
  alias BeamConsole.Runtime.ProcessSelector
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

  @impl BeamConsole.Runtime.Adapter
  def snapshot(options) do
    started_at = System.monotonic_time(:millisecond)
    sequence = Keyword.get(options, :sequence, 1)
    local_node = node()
    local_node_id = EntityId.build(:node, local_node)
    process_limit = Config.get(options, :process_limit)
    all_pids = Process.list()

    selected_pids =
      all_pids
      |> Enum.reject(&(&1 == self()))
      |> ProcessSelector.select(process_limit)

    {processes, vanished} = collect_processes(selected_pids, local_node, local_node_id)

    {applications, roots} = collect_applications(local_node, local_node_id)

    {
      edges,
      supervision_attribution,
      lifecycle_observations,
      partial_supervisors,
      traversal_limit_reached?
    } =
      Supervision.collect(roots, local_node, options)

    processes = apply_supervision_attribution(processes, supervision_attribution)
    completed_at = System.monotonic_time(:millisecond)

    coverage =
      %Coverage{
        total_pids: length(all_pids),
        inspected_pids: map_size(processes),
        vanished_pids: vanished,
        process_limit_reached?: length(all_pids) > process_limit,
        traversal_limit_reached?: traversal_limit_reached?,
        partial_supervisors: partial_supervisors,
        duration_ms: max(completed_at - started_at, 0)
      }
      |> then(&%{&1 | warnings: Coverage.warnings(&1)})

    nodes = collect_nodes(local_node)

    sampled_at = DateTime.utc_now()

    runtime_sample =
      runtime_sample(
        sequence,
        sampled_at,
        completed_at,
        applications,
        nodes,
        edges,
        coverage
      )

    snapshot = %Snapshot{
      sequence: sequence,
      sampled_at: sampled_at,
      monotonic_ms: completed_at,
      local_node_id: local_node_id,
      nodes: nodes,
      applications: applications,
      processes: processes,
      edges: edges,
      lifecycle_observations: lifecycle_observations,
      runtime_sample: runtime_sample,
      coverage: coverage,
      index: build_index(processes, applications, nodes)
    }

    {:ok, snapshot}
  rescue
    exception -> {:error, {:snapshot_failed, exception}}
  end

  @doc """
  Returns allowlisted details for a local process present in the snapshot.

  The call returns `{:error, :unavailable}` when the PID is remote, has exited,
  or no longer matches a process in the supplied snapshot.
  """
  @spec detail(pid(), Snapshot.t(), keyword()) ::
          {:ok, ProcessDetail.t()} | {:error, :unavailable}
  def detail(pid, snapshot, options \\ []) when is_pid(pid) do
    with true <- node(pid) == node(),
         process_id <- EntityId.build(:process, {node(), pid}),
         %ProcessInfo{} = summary <- Map.get(snapshot.processes, process_id),
         {:ok, detail} <- timed_detail(pid, summary, snapshot, options) do
      {:ok, detail}
    else
      _other -> {:error, :unavailable}
    end
  end

  defp timed_detail(pid, summary, snapshot, options) do
    timeout = Config.get(options, :detail_timeout)
    context = detail_context(snapshot, options)
    parent = self()
    request_ref = make_ref()

    {worker, monitor_ref} =
      spawn_monitor(fn ->
        result = process_detail(pid, summary, context)
        send(parent, {request_ref, result})
      end)

    receive do
      {^request_ref, result} ->
        Process.demonitor(monitor_ref, [:flush])
        result

      {:DOWN, ^monitor_ref, :process, ^worker, _reason} ->
        {:error, :unavailable}
    after
      timeout ->
        terminate_detail_worker(worker, monitor_ref, request_ref)
        {:error, :unavailable}
    end
  end

  defp process_detail(pid, summary, context) do
    case Process.info(pid, @detail_fields) do
      values when is_list(values) ->
        {links, link_count, links_omitted} =
          normalize_relations(values[:links], context.relationship_limit, context.process_ids)

        {monitors, monitor_count, monitors_omitted} =
          normalize_relations(values[:monitors], context.relationship_limit, context.process_ids)

        {monitored_by, monitored_by_count, monitored_by_omitted} =
          normalize_relations(
            values[:monitored_by],
            context.relationship_limit,
            context.process_ids
          )

        {:ok,
         %ProcessDetail{
           id: summary.id,
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
           last_seen_at: context.sampled_at,
           links: links,
           monitors: monitors,
           monitored_by: monitored_by,
           relationship_counts: %{
             links: link_count,
             monitors: monitor_count,
             monitored_by: monitored_by_count
           },
           relationship_omitted: %{
             links: links_omitted,
             monitors: monitors_omitted,
             monitored_by: monitored_by_omitted
           }
         }}

      _other ->
        {:error, :unavailable}
    end
  end

  defp detail_context(snapshot, options) do
    %{
      sampled_at: snapshot.sampled_at,
      relationship_limit: Config.get(options, :relationship_limit),
      process_ids: snapshot.processes |> Map.keys() |> MapSet.new()
    }
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
        root_supervisor_id: root && EntityId.build(:process, {local_node, root}),
        required_applications: required_applications(name),
        origin: application_origin(name)
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

  defp required_applications(application) do
    case Application.spec(application, :applications) do
      applications when is_list(applications) -> Enum.filter(applications, &is_atom/1)
      _other -> []
    end
  end

  defp application_origin(application) do
    with root when is_list(root) <- :code.root_dir(),
         directory when is_list(directory) <- :code.lib_dir(application) do
      otp_library = root |> List.to_string() |> Path.join("lib") |> Path.expand()
      application_directory = directory |> List.to_string() |> Path.expand()

      if application_directory == otp_library or
           String.starts_with?(application_directory, otp_library <> "/") do
        :otp
      else
        :external
      end
    else
      _other -> :unknown
    end
  end

  defp normalize_registered_name([]) do
    nil
  end

  defp normalize_registered_name(name) when is_atom(name) do
    name |> Atom.to_string() |> EntityId.label(160)
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

  defp process_label(name, _module, _pid) when is_binary(name) do
    name
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

  defp normalize_relations(relations, limit, process_ids) when is_list(relations) do
    count = length(relations)
    normalized = relations |> Enum.take(limit) |> Enum.map(&process_relation(&1, process_ids))
    {normalized, count, max(count - length(normalized), 0)}
  end

  defp normalize_relations(_relations, _limit, _process_ids) do
    {[], 0, 0}
  end

  defp terminate_detail_worker(worker, monitor_ref, request_ref) do
    Process.exit(worker, :kill)

    receive do
      {:DOWN, ^monitor_ref, :process, ^worker, _reason} -> :ok
    after
      50 -> Process.demonitor(monitor_ref, [:flush])
    end

    receive do
      {^request_ref, _late_result} -> :ok
    after
      0 -> :ok
    end
  end

  defp runtime_sample(
         sequence,
         sampled_at,
         monotonic_ms,
         applications,
         nodes,
         edges,
         coverage
       ) do
    memory = :erlang.memory()

    %RuntimeSample{
      sequence: sequence,
      sampled_at_ms: DateTime.to_unix(sampled_at, :millisecond),
      monotonic_ms: monotonic_ms,
      process_count: coverage.total_pids,
      inspected_process_count: coverage.inspected_pids,
      supervisor_count: supervisor_count(applications, edges),
      application_count: map_size(applications),
      ets_count: length(:ets.all()),
      node_count: map_size(nodes),
      atom_count: :erlang.system_info(:atom_count),
      atom_limit: :erlang.system_info(:atom_limit),
      memory_total: memory[:total],
      memory_processes: memory[:processes],
      memory_system: memory[:system],
      memory_atom: memory[:atom],
      memory_binary: memory[:binary],
      memory_code: memory[:code],
      memory_ets: memory[:ets],
      scheduler_count: :erlang.system_info(:schedulers_online),
      run_queue: :erlang.statistics(:run_queue),
      collector_scan_ms: coverage.duration_ms,
      collector_partial?: Coverage.state(coverage) != :complete
    }
  end

  defp supervisor_count(applications, edges) do
    child_supervisors =
      edges
      |> Map.values()
      |> Enum.filter(&(&1.child_type == :supervisor and is_binary(&1.child_id)))
      |> Enum.map(& &1.child_id)

    root_supervisors =
      applications
      |> Map.values()
      |> Enum.map(& &1.root_supervisor_id)
      |> Enum.reject(&is_nil/1)

    child_supervisors
    |> Kernel.++(root_supervisors)
    |> MapSet.new()
    |> MapSet.size()
  end

  defp process_relation(pid, process_ids) when is_pid(pid) do
    id = EntityId.build(:process, {node(pid), pid})

    %ProcessRelation{
      id: if(MapSet.member?(process_ids, id), do: id),
      label: EntityId.label(pid),
      kind: :process
    }
  end

  defp process_relation(port, _process_ids) when is_port(port) do
    %ProcessRelation{
      label: port |> :erlang.port_to_list() |> List.to_string(),
      kind: :port
    }
  end

  defp process_relation({kind, relation}, process_ids) when kind in [:process, :port] do
    process_relation(relation, process_ids)
  end

  defp process_relation(_relation, _process_ids) do
    %ProcessRelation{label: "opaque relation", kind: :opaque}
  end
end
