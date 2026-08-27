defmodule BeamConsole.Diff do
  @moduledoc """
  Describes bounded differences between two sampled runtime snapshots.

  Lifecycle fields use `observed_` terminology because short-lived changes can
  occur between samples and are not guaranteed to be lossless.
  """

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

  @type entity_id :: String.t()
  @type t :: %__MODULE__{
          from_sequence: non_neg_integer(),
          to_sequence: non_neg_integer(),
          observed_started: [entity_id()],
          observed_stopped: [entity_id()],
          changed: [entity_id()],
          edge_added: [entity_id()],
          edge_removed: [entity_id()],
          omitted: non_neg_integer()
        }

  @spec between(Snapshot.t() | nil, Snapshot.t(), non_neg_integer()) :: t()
  @doc """
  Computes a bounded difference from one snapshot to the next.

  Passing `nil` as the previous snapshot reports current processes as observed
  starts. Once the event limit is reached, remaining records are counted in
  `omitted`.
  """
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
