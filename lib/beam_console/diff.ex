defmodule BeamConsole.Diff do
  @moduledoc false

  alias BeamConsole.Snapshot

  @enforce_keys [:from_sequence, :to_sequence]
  defstruct from_sequence: 0,
            to_sequence: 0,
            observed_started: [],
            observed_stopped: [],
            changed: [],
            edge_added: [],
            edge_removed: [],
            omitted: 0

  @type t :: %__MODULE__{}

  @spec between(Snapshot.t() | nil, Snapshot.t(), non_neg_integer()) :: t()
  def between(previous, current, limit \\ 500)

  def between(nil, %Snapshot{} = current, limit) do
    started = current.processes |> Map.keys() |> Enum.sort()
    {kept, omitted} = cap(started, limit)

    %__MODULE__{
      from_sequence: 0,
      to_sequence: current.sequence,
      observed_started: kept,
      omitted: omitted
    }
  end

  def between(%Snapshot{} = previous, %Snapshot{} = current, limit) do
    previous_ids = previous.processes |> Map.keys() |> MapSet.new()
    current_ids = current.processes |> Map.keys() |> MapSet.new()

    started = current_ids |> MapSet.difference(previous_ids) |> MapSet.to_list()
    stopped = previous_ids |> MapSet.difference(current_ids) |> MapSet.to_list()

    changed =
      previous_ids
      |> MapSet.intersection(current_ids)
      |> Enum.filter(&(Map.fetch!(previous.processes, &1) != Map.fetch!(current.processes, &1)))

    previous_edges = previous.edges |> Map.keys() |> MapSet.new()
    current_edges = current.edges |> Map.keys() |> MapSet.new()

    records = [
      {:observed_started, Enum.sort(started)},
      {:observed_stopped, Enum.sort(stopped)},
      {:changed, Enum.sort(changed)},
      {:edge_added, current_edges |> MapSet.difference(previous_edges) |> Enum.sort()},
      {:edge_removed, previous_edges |> MapSet.difference(current_edges) |> Enum.sort()}
    ]

    {fields, omitted} = cap_records(records, limit)

    struct!(
      __MODULE__,
      [from_sequence: previous.sequence, to_sequence: current.sequence, omitted: omitted] ++
        fields
    )
  end

  defp cap(values, limit) do
    kept = Enum.take(values, limit)
    {kept, max(length(values) - length(kept), 0)}
  end

  defp cap_records(records, limit) do
    records
    |> Enum.map_reduce({limit, 0}, fn {key, values}, {remaining, omitted} ->
      {kept, newly_omitted} = cap(values, remaining)
      {{key, kept}, {max(remaining - length(kept), 0), omitted + newly_omitted}}
    end)
    |> then(fn {fields, {_remaining, omitted}} -> {fields, omitted} end)
  end
end
