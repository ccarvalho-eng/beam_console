defmodule BeamConsoleWeb.Console.DashboardPresenter do
  @moduledoc "Transforms one transient runtime snapshot into bounded dashboard view models."

  alias BeamConsole.ApplicationInfo
  alias BeamConsole.NodeInfo
  alias BeamConsole.ProcessInfo
  alias BeamConsole.Snapshot

  @type process_result :: %{
          items: [ProcessInfo.t()],
          matching_count: non_neg_integer(),
          omitted_count: non_neg_integer()
        }

  @doc "Returns sorted process rows plus exact matching and omission counts."
  @spec process_result(Snapshot.t(), String.t(), pos_integer()) :: process_result()
  def process_result(%Snapshot{} = snapshot, query, limit) do
    normalized_query = query |> String.trim() |> String.downcase()

    matches =
      snapshot.processes
      |> Map.values()
      |> Enum.filter(&matches?(&1, normalized_query))
      |> Enum.sort_by(&{&1.application || :zz_unattributed, &1.label, &1.pid_text})

    %{
      items: Enum.take(matches, limit),
      matching_count: length(matches),
      omitted_count: max(length(matches) - limit, 0)
    }
  end

  @doc "Returns started applications in deterministic display order."
  @spec applications(Snapshot.t()) :: [ApplicationInfo.t()]
  def applications(%Snapshot{} = snapshot) do
    snapshot.applications
    |> Map.values()
    |> Enum.sort_by(& &1.name)
  end

  @doc "Returns local and connected nodes in deterministic display order."
  @spec nodes(Snapshot.t()) :: [NodeInfo.t()]
  def nodes(%Snapshot{} = snapshot) do
    snapshot.nodes
    |> Map.values()
    |> Enum.sort_by(&{&1.kind, &1.name})
  end

  @doc "Returns a bounded selected-entity view model without retaining the snapshot."
  @spec selection(Snapshot.t(), String.t() | nil) :: map() | nil
  def selection(_snapshot, nil) do
    nil
  end

  def selection(%Snapshot{} = snapshot, selected_id) do
    case Map.get(snapshot.index, selected_id) do
      {:process, _pid} -> process_selection(snapshot.processes[selected_id])
      {:application, _name} -> application_selection(snapshot.applications[selected_id])
      {:node, _name} -> node_selection(snapshot.nodes[selected_id])
      _other -> %{id: selected_id, kind: :unknown, label: "No longer available"}
    end
  end

  @doc "Checks whether an opaque entity ID belongs to the latest snapshot."
  @spec valid_selection?(Snapshot.t() | nil, String.t()) :: boolean()
  def valid_selection?(%Snapshot{} = snapshot, entity_id) when is_binary(entity_id) do
    Map.has_key?(snapshot.index, entity_id)
  end

  def valid_selection?(_snapshot, _entity_id) do
    false
  end

  defp process_selection(nil) do
    nil
  end

  defp process_selection(process) do
    %{
      id: process.id,
      kind: :process,
      label: process.label,
      pid_text: process.pid_text,
      status: process.status
    }
  end

  defp application_selection(nil) do
    nil
  end

  defp application_selection(application) do
    %{
      id: application.id,
      kind: :application,
      label: Atom.to_string(application.name),
      description: application.description,
      version: application.version,
      node_id: application.node_id,
      root_supervisor_id: application.root_supervisor_id
    }
  end

  defp node_selection(nil) do
    nil
  end

  defp node_selection(runtime_node) do
    %{
      id: runtime_node.id,
      kind: :node,
      label: runtime_node.name,
      node_kind: runtime_node.kind,
      inspectable?: runtime_node.inspectable?
    }
  end

  defp matches?(_process, "") do
    true
  end

  defp matches?(process, query) do
    [
      process.label,
      process.pid_text,
      process.module,
      process.registered_name,
      process.application
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.any?(fn value ->
      value
      |> to_string()
      |> String.downcase()
      |> String.contains?(query)
    end)
  end
end
