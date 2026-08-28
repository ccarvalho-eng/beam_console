defmodule BeamConsoleWeb.Console.SelectionStateTest do
  use ExUnit.Case, async: true

  alias BeamConsole.Snapshot
  alias BeamConsoleWeb.Console.SelectionState

  test "retains one bounded process tombstone when a selected process vanishes" do
    sampled_at = DateTime.from_unix!(1_700_000_000_000, :millisecond)

    snapshot = %Snapshot{
      sequence: 8,
      sampled_at: sampled_at,
      local_node_id: "node",
      index: %{}
    }

    previous = %{
      id: "process-id",
      kind: :process,
      label: "PaymentWorker",
      pid_text: "<0.42.0>",
      status: :waiting,
      last_seen_sequence: 3
    }

    previous_detail = %{label: "PaymentWorker", memory: 1_024}

    assert {%{kind: :vanished} = selected, ^previous_detail} =
             SelectionState.resolve(snapshot, "process-id", previous, previous_detail)

    assert selected.id == "process-id"
    assert selected.label == "PaymentWorker"
    assert selected.last_seen_sequence == 3
    assert selected.vanished_at == DateTime.to_iso8601(sampled_at)
  end

  test "records the exact sequence while a selected process is live" do
    process = %BeamConsole.ProcessInfo{
      id: "process-id",
      node_id: "node",
      pid: self(),
      pid_text: inspect(self()),
      label: "SelectionStateTest"
    }

    snapshot = %Snapshot{
      sequence: 12,
      sampled_at: DateTime.utc_now(),
      local_node_id: "node",
      processes: %{process.id => process},
      index: %{process.id => {:process, self()}}
    }

    assert {%{kind: :process, last_seen_sequence: 12}, _detail} =
             SelectionState.resolve(snapshot, process.id, nil, nil)
  end

  test "does not manufacture a tombstone for an unknown URL selection" do
    snapshot = %Snapshot{
      sequence: 1,
      sampled_at: DateTime.utc_now(),
      local_node_id: "node",
      index: %{}
    }

    assert {%{kind: :unknown}, nil} =
             SelectionState.resolve(snapshot, "unknown", nil, nil)
  end
end
