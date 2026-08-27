defmodule BeamConsole.ActivityTest do
  use ExUnit.Case, async: true

  alias BeamConsole.Activity
  alias BeamConsole.ProcessInfo
  alias BeamConsole.Snapshot

  test "ranks bounded process deltas and converts reductions to rates" do
    previous = snapshot(1, 0, [process("a", 10, 1, 100), process("b", 20, 2, 200)])
    current = snapshot(2, 1_000, [process("a", 30, 4, 150), process("b", 25, 1, 180)])

    sample = Activity.sample(previous, current, 1_000)

    assert sample.aggregates.reductions_per_second == 25.0
    assert sample.aggregates.mailbox_delta == 2
    assert sample.aggregates.memory_delta == 30
    assert Enum.at(sample.top_movers, 0).value == 50
    assert Enum.all?(sample.top_movers, &is_binary(&1.entity_id))
  end

  test "treats reductions counter reset as a gap instead of a negative rate" do
    previous = snapshot(1, 0, [process("a", 100, 0, 100)])
    current = snapshot(2, 1_000, [process("a", 5, 0, 100)])

    sample = Activity.sample(previous, current, 1_000)

    refute Enum.any?(sample.top_movers, &(&1.metric == :reductions_per_second))
    assert sample.aggregates.reductions_per_second == 0.0
  end

  defp snapshot(sequence, offset_ms, processes) do
    %Snapshot{
      sequence: sequence,
      sampled_at: DateTime.add(~U[2026-01-01 00:00:00Z], offset_ms, :millisecond),
      local_node_id: "node",
      processes: Map.new(processes, &{&1.id, &1})
    }
  end

  defp process(id, reductions, mailbox, memory) do
    %ProcessInfo{
      id: id,
      node_id: "node",
      pid: self(),
      pid_text: "<0.1.0>",
      label: "Worker #{id}",
      reductions: reductions,
      message_queue_len: mailbox,
      memory: memory
    }
  end
end
