defmodule BeamConsole.Runtime.LocalTest do
  use ExUnit.Case, async: false

  alias BeamConsole.Runtime.Local

  test "collects a bounded local snapshot with node-aware processes" do
    assert {:ok, snapshot} = Local.snapshot(sequence: 7, process_limit: 10_000)

    assert snapshot.sequence == 7
    assert snapshot.nodes[snapshot.local_node_id].inspectable?
    assert snapshot.coverage.total_pids >= snapshot.coverage.inspected_pids
    refute Enum.any?(snapshot.processes, fn {_id, process} -> process.pid == self() end)
    refute Enum.any?(snapshot.processes, fn {_id, process} -> process.label == "nil" end)
  end

  test "rejects details for a process absent from the snapshot" do
    assert {:ok, snapshot} = Local.snapshot(sequence: 1, process_limit: 10_000)
    pid = spawn(fn -> :ok end)
    reference = Process.monitor(pid)
    assert_receive {:DOWN, ^reference, :process, ^pid, :normal}

    assert {:error, :unavailable} = Local.detail(pid, snapshot)
  end
end
