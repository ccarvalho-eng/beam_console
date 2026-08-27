defmodule BeamConsole.Lifecycle.DiffEventsTest do
  use ExUnit.Case, async: true

  alias BeamConsole.Diff
  alias BeamConsole.Coverage
  alias BeamConsole.Lifecycle.DiffEvents
  alias BeamConsole.ProcessInfo
  alias BeamConsole.Recorder.Frame
  alias BeamConsole.Snapshot

  test "turns post-baseline process changes into safe sampled events" do
    previous = snapshot(1, [process("old", "Old worker")])
    current = snapshot(2, [process("new", "New worker")])
    diff = Diff.between(previous, current)

    events = DiffEvents.from_diff(diff, previous, current, frame(2))

    assert Enum.map(events, &{&1.kind, &1.entity_id, &1.label}) == [
             {:observed_start, "new", "New worker"},
             {:observed_stop, "old", "Old worker"}
           ]

    assert Enum.all?(events, &(&1.evidence == :snapshot_diff and &1.certainty == :sampled))
  end

  test "treats the first snapshot as a baseline" do
    current = snapshot(1, [process("existing", "Existing")])
    diff = Diff.between(nil, current)

    assert DiffEvents.from_diff(diff, nil, current, frame(1)) == []
  end

  test "marks capped process samples as partial instead of inventing lifecycle changes" do
    previous = snapshot(1, [process("sample-a", "Sample A")], process_limit_reached?: true)
    current = snapshot(2, [process("sample-b", "Sample B")], process_limit_reached?: true)
    diff = Diff.between(previous, current)

    assert [event] = DiffEvents.from_diff(diff, previous, current, frame(2))
    assert event.kind == :gap
    assert event.certainty == :partial
    assert event.details == %{reason: :partial_process_coverage, omitted: 2}
  end

  test "does not repeat partial coverage gaps when the sampled set is unchanged" do
    previous = snapshot(1, [process("sample-a", "Sample A")], process_limit_reached?: true)
    current = snapshot(2, [process("sample-a", "Sample A")], process_limit_reached?: true)
    diff = Diff.between(previous, current)

    assert DiffEvents.from_diff(diff, previous, current, frame(2)) == []
  end

  test "makes bounded diff omissions visible in the lifecycle" do
    snapshot = snapshot(2, [])

    diff = %Diff{
      from_sequence: 1,
      to_sequence: 2,
      omitted: 7,
      omitted_by: %{observed_started: 3, observed_stopped: 1, changed: 3}
    }

    assert [event] = DiffEvents.from_diff(diff, snapshot, snapshot, frame(2))
    assert event.kind == :gap
    assert event.details == %{reason: :diff_limit, omitted: 4}
  end

  test "does not report non-lifecycle diff omissions as lifecycle loss" do
    snapshot = snapshot(2, [])

    diff = %Diff{
      from_sequence: 1,
      to_sequence: 2,
      omitted: 4,
      omitted_by: %{changed: 2, edge_added: 2}
    }

    assert DiffEvents.from_diff(diff, snapshot, snapshot, frame(2)) == []
  end

  test "scopes sampled event IDs to the collector epoch" do
    previous = snapshot(1, [process("old", "Old")])
    current = snapshot(2, [process("new", "New")])
    diff = Diff.between(previous, current)

    first = %{current | collector_epoch: "epoch-a"}
    second = %{current | collector_epoch: "epoch-b"}

    first_ids = DiffEvents.from_diff(diff, previous, first, frame(2)) |> Enum.map(& &1.id)
    second_ids = DiffEvents.from_diff(diff, previous, second, frame(2)) |> Enum.map(& &1.id)

    assert MapSet.disjoint?(MapSet.new(first_ids), MapSet.new(second_ids))
  end

  defp snapshot(sequence, processes, coverage_options \\ []) do
    %Snapshot{
      sequence: sequence,
      sampled_at: DateTime.utc_now(),
      local_node_id: "node",
      processes: Map.new(processes, &{&1.id, &1}),
      coverage: struct!(Coverage, coverage_options)
    }
  end

  defp process(id, label) do
    %ProcessInfo{
      id: id,
      node_id: "node",
      pid: self(),
      pid_text: inspect(self()),
      label: label,
      application: :fixture
    }
  end

  defp frame(sequence) do
    %Frame{
      sequence: sequence,
      sampled_at_ms: sequence * 1_000,
      monotonic_ms: sequence * 100
    }
  end
end
