defmodule BeamConsoleWeb.Console.SelectionState do
  @moduledoc """
  Resolves the current bounded inspector state across runtime samples.

  A selected process that disappears retains one scalar tombstone and its last
  allowlisted detail. Unknown URL identifiers never inherit unrelated state.
  """

  alias BeamConsole.Snapshot
  alias BeamConsoleWeb.Console.DashboardPresenter

  @type selection :: map() | nil
  @type detail :: BeamConsole.ProcessDetail.t() | map() | nil
  @type result :: {selection(), detail()}

  @doc "Resolves live, vanished, or unknown selection state for one snapshot."
  @spec resolve(Snapshot.t(), String.t() | nil, selection(), detail()) :: result()
  def resolve(%Snapshot{} = snapshot, selected_id, previous_selected, previous_detail) do
    snapshot
    |> DashboardPresenter.selection(selected_id)
    |> resolve_selection(snapshot, previous_selected, previous_detail)
  end

  defp resolve_selection(%{kind: :process} = selected, snapshot, _previous, _detail) do
    selected = Map.put(selected, :last_seen_sequence, snapshot.sequence)
    {selected, process_detail(snapshot, selected.id)}
  end

  defp resolve_selection(
         %{kind: :unknown} = unknown,
         snapshot,
         %{id: id, kind: kind} = previous,
         previous_detail
       )
       when kind in [:process, :vanished] and id == unknown.id do
    selected =
      previous
      |> Map.put(:kind, :vanished)
      |> Map.put_new(:vanished_at, DateTime.to_iso8601(snapshot.sampled_at))

    {selected, previous_detail}
  end

  defp resolve_selection(selected, _snapshot, _previous, _detail) do
    {selected, nil}
  end

  defp process_detail(snapshot, selected_id) do
    case BeamConsole.detail(snapshot, selected_id) do
      {:ok, detail} -> detail
      {:error, _reason} -> nil
    end
  end
end
