defmodule BeamConsole.Lifecycle.DiffEvents do
  @moduledoc """
  Converts bounded snapshot differences into safe sampled lifecycle events.

  The first snapshot establishes a baseline and emits no process starts. Later
  differences retain only opaque entity IDs and normalized snapshot labels.
  """

  alias BeamConsole.Diff
  alias BeamConsole.EntityId
  alias BeamConsole.Lifecycle.Event
  alias BeamConsole.ProcessInfo
  alias BeamConsole.Recorder.Frame
  alias BeamConsole.Snapshot

  @doc "Returns sampled process start and stop events from a bounded snapshot difference."
  @spec from_diff(Diff.t(), Snapshot.t() | nil, Snapshot.t(), Frame.t()) :: [Event.t()]
  def from_diff(%Diff{from_sequence: 0}, _previous, _current, _frame) do
    []
  end

  def from_diff(%Diff{} = diff, %Snapshot{} = previous, %Snapshot{} = current, frame) do
    if complete_process_coverage?(previous) and complete_process_coverage?(current) do
      process_events(diff, previous, current, frame) ++ omission_events(diff, current, frame)
    else
      partial_coverage_events(diff, current, frame)
    end
  end

  defp process_events(diff, previous, current, frame) do
    starts =
      Enum.flat_map(diff.observed_started, fn entity_id ->
        event_for(:observed_start, current.processes[entity_id], current.collector_epoch, frame)
      end)

    stops =
      Enum.flat_map(diff.observed_stopped, fn entity_id ->
        event_for(:observed_stop, previous.processes[entity_id], current.collector_epoch, frame)
      end)

    starts ++ stops
  end

  defp omission_events(%Diff{} = diff, current, frame) do
    case lifecycle_omitted(diff) do
      0 ->
        []

      omitted ->
        [
          gap_event(
            frame,
            "#{omitted} observed lifecycle changes omitted",
            :diff_limit,
            omitted,
            current.collector_epoch
          )
        ]
    end
  end

  defp partial_coverage_events(diff, current, frame) do
    if diff.observed_started == [] and diff.observed_stopped == [] and
         lifecycle_omitted(diff) == 0 do
      []
    else
      [
        gap_event(
          frame,
          "Process lifecycle sampling is partial",
          :partial_process_coverage,
          partial_coverage_omitted(diff),
          current.collector_epoch
        )
      ]
    end
  end

  defp gap_event(frame, label, reason, omitted, collector_epoch) do
    %Event{
      id: EntityId.build(:event, {:lifecycle_gap, collector_epoch, reason, frame.sequence}),
      kind: :gap,
      sequence: frame.sequence,
      segment: frame.segment,
      observed_at_ms: frame.sampled_at_ms,
      monotonic_ms: frame.monotonic_ms,
      label: label,
      evidence: :snapshot_diff,
      certainty: :partial,
      details: %{reason: reason, omitted: omitted}
    }
  end

  defp complete_process_coverage?(snapshot) do
    coverage = snapshot.coverage
    not coverage.process_limit_reached? and coverage.vanished_pids == 0
  end

  defp lifecycle_omitted(diff) do
    Map.get(diff.omitted_by, :observed_started, 0) +
      Map.get(diff.omitted_by, :observed_stopped, 0)
  end

  defp partial_coverage_omitted(diff) do
    length(diff.observed_started) +
      length(diff.observed_stopped) +
      lifecycle_omitted(diff)
  end

  defp event_for(_kind, nil, _collector_epoch, _frame) do
    []
  end

  defp event_for(kind, %ProcessInfo{} = process, collector_epoch, %Frame{} = frame) do
    [
      %Event{
        id: EntityId.build(:event, {collector_epoch, kind, process.id, frame.sequence}),
        kind: kind,
        sequence: frame.sequence,
        segment: frame.segment,
        observed_at_ms: frame.sampled_at_ms,
        monotonic_ms: frame.monotonic_ms,
        entity_id: process.id,
        label: process.label,
        node_id: process.node_id,
        application: application_label(process.application),
        evidence: :snapshot_diff,
        certainty: :sampled
      }
    ]
  end

  defp application_label(application) when is_atom(application) do
    Atom.to_string(application)
  end

  defp application_label(_application) do
    nil
  end
end
