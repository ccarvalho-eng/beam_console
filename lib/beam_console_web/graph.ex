if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule BeamConsoleWeb.Graph do
    @moduledoc false

    alias BeamConsole.Snapshot

    @process_limit 160

    @spec default_focus_id(Snapshot.t()) :: String.t() | nil
    def default_focus_id(%Snapshot{} = snapshot) do
      case largest_supervision_application(snapshot) do
        nil -> nil
        application -> application.id
      end
    end

    @spec payload(Snapshot.t(), String.t() | nil, String.t() | nil) :: map()
    def payload(%Snapshot{} = snapshot, selected_id, focus_id \\ nil) do
      local_node = Map.fetch!(snapshot.nodes, snapshot.local_node_id)
      focus_application = focus_application(snapshot, selected_id, focus_id)
      processes = focused_processes(snapshot, focus_application, selected_id)
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

      %{
        sequence: snapshot.sequence,
        focus: focus_application && Atom.to_string(focus_application.name),
        selected: selected_if_visible(selected_id, included_ids),
        elements:
          node_elements ++
            application_elements ++ process_elements ++ hierarchy_edges ++ supervision_edges
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
      |> Enum.take(@process_limit)
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
