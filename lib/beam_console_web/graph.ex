if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule BeamConsoleWeb.Graph do
    @moduledoc """
    Converts normalized runtime snapshots into bounded Cytoscape graph data.

    The payload keeps browser-facing values scalar and limits the visible
    process count so large runtimes remain navigable.
    """

    alias BeamConsole.EntityId
    alias BeamConsole.Snapshot

    @process_limit 160
    @relationship_target_limit 40

    @type payload_options :: [
            selected_id: String.t() | nil,
            focus_id: String.t() | nil,
            edge_preset: String.t(),
            selected_detail: map() | nil
          ]

    @doc "Returns the application ID with the largest observed supervision tree."
    @spec default_focus_id(Snapshot.t()) :: String.t() | nil
    def default_focus_id(%Snapshot{} = snapshot) do
      case largest_supervision_application(snapshot) do
        nil -> nil
        application -> application.id
      end
    end

    @doc "Builds a bounded graph payload around the selected or focused application."
    @spec payload(Snapshot.t(), payload_options()) :: map()
    def payload(%Snapshot{} = snapshot, options \\ []) when is_list(options) do
      selected_id = Keyword.get(options, :selected_id)
      focus_id = Keyword.get(options, :focus_id)
      edge_preset = Keyword.get(options, :edge_preset, "supervision")
      selected_detail = live_process_detail(snapshot, Keyword.get(options, :selected_detail))
      local_node = Map.fetch!(snapshot.nodes, snapshot.local_node_id)
      focus_application = focus_application(snapshot, selected_id, focus_id)
      focused_processes = focused_processes(snapshot, focus_application, selected_id)

      relationship_processes =
        relationship_processes(snapshot, selected_detail, edge_preset, selected_id)

      relationship_ids = MapSet.new(relationship_processes, & &1.id)
      focused_processes = Enum.reject(focused_processes, &MapSet.member?(relationship_ids, &1.id))
      focus_limit = max(@process_limit - length(relationship_processes), 0)
      processes = Enum.take(focused_processes, focus_limit) ++ relationship_processes
      supervisor_ids = supervisor_ids(snapshot)

      node_elements = [node_element(local_node.id, local_node.name, "node")]
      application_elements = application_elements(snapshot, focus_application)

      process_elements =
        Enum.map(processes, fn process ->
          kind = if MapSet.member?(supervisor_ids, process.id), do: "supervisor", else: "process"
          node_element(process.id, process.label, kind)
        end)

      included_ids =
        (node_elements ++ application_elements ++ process_elements)
        |> Enum.map(& &1.data.id)
        |> MapSet.new()

      hierarchy_edges = hierarchy_edges(snapshot, focus_application, included_ids)
      supervision_edges = supervision_edges(snapshot, included_ids)
      relationship_edges = relationship_edges(selected_detail, included_ids, edge_preset)
      omitted_focus_nodes = max(length(focused_processes) - focus_limit, 0)

      omitted_relationship_nodes =
        omitted_relationship_nodes(snapshot, selected_detail, edge_preset)

      %{
        epoch: snapshot.collector_epoch,
        sequence: snapshot.sequence,
        focus: focus_application && Atom.to_string(focus_application.name),
        selected: selected_if_visible(selected_id, included_ids),
        omitted_nodes: omitted_focus_nodes,
        omitted_relationships: omitted_relationship_nodes,
        elements:
          node_elements ++
            application_elements ++
            process_elements ++ hierarchy_edges ++ supervision_edges ++ relationship_edges
      }
    end

    defp focus_application(snapshot, selected_id, focus_id) do
      selected_application(snapshot, selected_id) ||
        selected_application(snapshot, focus_id) ||
        largest_supervision_application(snapshot)
    end

    defp selected_application(_snapshot, nil) do
      nil
    end

    defp selected_application(snapshot, selected_id) do
      case Map.get(snapshot.index, selected_id) do
        {:application, application} ->
          application_info(snapshot, application)

        {:process, _pid} ->
          process = Map.get(snapshot.processes, selected_id)

          application_info(
            snapshot,
            process && (process.supervision_application || process.application)
          )

        _other ->
          nil
      end
    end

    defp largest_supervision_application(snapshot) do
      counts =
        snapshot.processes
        |> Map.values()
        |> Enum.reject(&is_nil(&1.supervision_application))
        |> Enum.frequencies_by(& &1.supervision_application)

      case Enum.max_by(counts, fn {application, count} -> {count, application} end, fn -> nil end) do
        {application, _count} -> application_info(snapshot, application)
        nil -> snapshot.applications |> Map.values() |> Enum.sort_by(& &1.name) |> List.first()
      end
    end

    defp application_info(_snapshot, nil) do
      nil
    end

    defp application_info(snapshot, application) do
      snapshot.applications
      |> Map.values()
      |> Enum.find(&(&1.name == application))
    end

    defp focused_processes(snapshot, nil, selected_id) do
      case Map.get(snapshot.processes, selected_id) do
        nil -> []
        process -> [process]
      end
    end

    defp focused_processes(snapshot, application, selected_id) do
      snapshot.processes
      |> Map.values()
      |> Enum.filter(fn process ->
        process.id == selected_id || process.supervision_application == application.name ||
          process.id == application.root_supervisor_id
      end)
      |> Enum.sort_by(&{&1.label, &1.id})
    end

    defp relationship_edges(_detail, _included_ids, "supervision") do
      []
    end

    defp relationship_edges(%{id: source_id} = detail, included_ids, "relationships") do
      if MapSet.member?(included_ids, source_id) do
        (link_edges(source_id, detail.links, included_ids) ++
           monitor_edges(source_id, detail.monitors, included_ids) ++
           monitored_by_edges(source_id, Map.get(detail, :monitored_by, []), included_ids))
        |> Enum.uniq_by(& &1.data.id)
        |> Enum.sort_by(& &1.data.id)
      else
        []
      end
    end

    defp relationship_edges(_processes, _included_ids, _preset) do
      []
    end

    defp link_edges(source_id, relations, included_ids) do
      relations
      |> relation_ids()
      |> Enum.filter(&valid_relation?(source_id, &1, included_ids))
      |> Enum.map(fn target_id ->
        [source, target] = Enum.sort([source_id, target_id])
        edge_element(EntityId.build(:edge, {:link, source, target}), source, target, "links")
      end)
    end

    defp monitor_edges(source_id, relations, included_ids) do
      relations
      |> relation_ids()
      |> Enum.filter(&valid_relation?(source_id, &1, included_ids))
      |> Enum.map(fn target_id ->
        edge_element(
          EntityId.build(:edge, {:monitor, source_id, target_id}),
          source_id,
          target_id,
          "monitors"
        )
      end)
    end

    defp monitored_by_edges(target_id, relations, included_ids) do
      relations
      |> relation_ids()
      |> Enum.filter(&valid_relation?(target_id, &1, included_ids))
      |> Enum.map(fn source_id ->
        edge_element(
          EntityId.build(:edge, {:monitor, source_id, target_id}),
          source_id,
          target_id,
          "monitors"
        )
      end)
    end

    defp relationship_processes(snapshot, detail, "relationships", selected_id) do
      detail
      |> all_relation_ids()
      |> Enum.reject(&(&1 == selected_id))
      |> Enum.flat_map(fn relation_id ->
        case Map.get(snapshot.processes, relation_id) do
          nil -> []
          process -> [process]
        end
      end)
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(&{&1.label, &1.id})
      |> Enum.take(@relationship_target_limit)
    end

    defp relationship_processes(_snapshot, _detail, _preset, _selected_id) do
      []
    end

    defp live_process_detail(_snapshot, nil) do
      nil
    end

    defp live_process_detail(snapshot, %{id: id} = detail) do
      if Map.has_key?(snapshot.processes, id), do: detail
    end

    defp live_process_detail(_snapshot, _detail) do
      nil
    end

    defp omitted_relationship_nodes(_snapshot, nil, "relationships") do
      0
    end

    defp omitted_relationship_nodes(snapshot, detail, "relationships") do
      available_ids =
        detail
        |> all_relation_ids()
        |> Enum.reject(&(&1 == detail.id))
        |> Enum.uniq()

      available = Enum.count(available_ids, &Map.has_key?(snapshot.processes, &1))

      unavailable =
        detail
        |> all_relations()
        |> Enum.count(&(not graphable_relation?(&1, snapshot, detail.id)))

      raw_omitted = relationship_omitted(detail)

      raw_omitted + unavailable + max(available - @relationship_target_limit, 0)
    end

    defp omitted_relationship_nodes(_snapshot, _detail, _preset) do
      0
    end

    defp all_relation_ids(nil) do
      []
    end

    defp all_relation_ids(detail) do
      detail |> all_relations() |> relation_ids()
    end

    defp all_relations(nil) do
      []
    end

    defp all_relations(detail) do
      detail.links ++ detail.monitors ++ Map.get(detail, :monitored_by, [])
    end

    defp relationship_omitted(detail) do
      detail
      |> Map.get(:relationship_omitted, %{})
      |> Map.take([:links, :monitors, :monitored_by])
      |> Map.values()
      |> Enum.filter(&is_integer/1)
      |> Enum.sum()
    end

    defp relation_ids(relations) do
      Enum.flat_map(relations, fn
        %{id: id, kind: :process} when is_binary(id) -> [id]
        _relation -> []
      end)
    end

    defp graphable_relation?(%{id: id, kind: :process}, snapshot, selected_id)
         when is_binary(id) do
      id != selected_id and Map.has_key?(snapshot.processes, id)
    end

    defp graphable_relation?(_relation, _snapshot, _selected_id) do
      false
    end

    defp valid_relation?(source_id, target_id, included_ids) do
      source_id != target_id and MapSet.member?(included_ids, target_id)
    end

    defp application_elements(_snapshot, nil) do
      []
    end

    defp application_elements(_snapshot, application) do
      [node_element(application.id, Atom.to_string(application.name), "application")]
    end

    defp hierarchy_edges(_snapshot, nil, _included_ids) do
      []
    end

    defp hierarchy_edges(snapshot, application, included_ids) do
      node_to_application =
        edge_element(
          "hierarchy-node-#{application.id}",
          snapshot.local_node_id,
          application.id,
          "contains"
        )

      application_to_root =
        if application.root_supervisor_id &&
             MapSet.member?(included_ids, application.root_supervisor_id) do
          [
            edge_element(
              "hierarchy-root-#{application.id}",
              application.id,
              application.root_supervisor_id,
              "owns"
            )
          ]
        else
          []
        end

      [node_to_application | application_to_root]
    end

    defp supervision_edges(snapshot, included_ids) do
      snapshot.edges
      |> Map.values()
      |> Enum.filter(fn edge ->
        edge.child_id && MapSet.member?(included_ids, edge.parent_id) &&
          MapSet.member?(included_ids, edge.child_id)
      end)
      |> Enum.sort_by(& &1.id)
      |> Enum.map(&edge_element(&1.id, &1.parent_id, &1.child_id, "supervises"))
    end

    defp supervisor_ids(snapshot) do
      Enum.reduce(snapshot.edges, MapSet.new(), fn {_id, edge}, ids ->
        ids = MapSet.put(ids, edge.parent_id)

        if edge.child_type == :supervisor && edge.child_id do
          MapSet.put(ids, edge.child_id)
        else
          ids
        end
      end)
    end

    defp node_element(id, label, kind) do
      %{data: %{id: id, label: label, kind: kind}}
    end

    defp edge_element(id, source, target, kind) do
      %{data: %{id: id, source: source, target: target, kind: kind}}
    end

    defp selected_if_visible(nil, _included_ids) do
      nil
    end

    defp selected_if_visible(selected_id, included_ids) do
      if MapSet.member?(included_ids, selected_id), do: selected_id
    end
  end
end
