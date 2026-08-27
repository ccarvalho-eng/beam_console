defmodule BeamConsoleTest do
  use ExUnit.Case

  doctest BeamConsole.EntityId
  doctest BeamConsole.Recorder.History
  doctest BeamConsole.ReasonSummary

  alias BeamConsole.Diff
  alias BeamConsole.EntityId
  alias BeamConsole.ProcessInfo
  alias BeamConsole.Snapshot

  test "entity IDs are deterministic, kind-separated, and URL safe" do
    process_id = EntityId.build(:process, {node(), self()})

    assert process_id == EntityId.build(:process, {node(), self()})
    refute process_id == EntityId.build(:node, {node(), self()})
    assert process_id =~ ~r/^proc_[A-Za-z0-9_-]+$/
  end

  test "entity labels preserve valid UTF-8 at byte boundaries" do
    label = EntityId.label("éé", 1)

    assert label == "…"
    assert String.valid?(label)

    invalid_label = EntityId.label(<<255>>, 8)
    assert invalid_label == "binary(1…"
    assert String.valid?(invalid_label)
  end

  test "diffs classify observed process changes" do
    first = snapshot(1, %{"proc_old" => process("proc_old", 1)})

    second =
      snapshot(2, %{
        "proc_old" => process("proc_old", 2),
        "proc_new" => process("proc_new", 1)
      })

    diff = Diff.between(first, second)

    assert diff.observed_started == ["proc_new"]
    assert diff.changed == ["proc_old"]
    assert diff.observed_stopped == []
  end

  test "diffs preserve omission counts by change category" do
    first =
      snapshot(1, %{
        "proc-old-a" => process("proc-old-a", 1),
        "proc-old-b" => process("proc-old-b", 1)
      })

    second =
      snapshot(2, %{
        "proc-new-a" => process("proc-new-a", 1),
        "proc-new-b" => process("proc-new-b", 1)
      })

    diff = Diff.between(first, second, 1)

    assert diff.omitted == 3
    assert diff.omitted_by == %{observed_started: 1, observed_stopped: 2}
  end

  test "search is bounded and matches process metadata" do
    snapshot = snapshot(1, %{"proc" => process("proc", 1)})

    assert [%ProcessInfo{id: "proc"}] = BeamConsole.search(snapshot, "sample", 1)
    assert [] = BeamConsole.search(snapshot, "missing", 1)
  end

  defp snapshot(sequence, processes) do
    %Snapshot{
      sequence: sequence,
      sampled_at: ~U[2026-01-01 00:00:00Z],
      local_node_id: "node",
      processes: processes
    }
  end

  defp process(id, reductions) do
    %ProcessInfo{
      id: id,
      node_id: "node",
      pid: self(),
      pid_text: "<0.1.0>",
      label: "SampleWorker",
      module: "SampleWorker",
      reductions: reductions
    }
  end
end
