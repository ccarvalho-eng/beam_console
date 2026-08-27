defmodule BeamConsole.Runtime.LocalTest do
  use ExUnit.Case, async: false

  alias BeamConsole.Runtime.Local

  test "collects a bounded local snapshot with node-aware processes" do
    assert {:ok, snapshot} = Local.snapshot(sequence: 7, process_limit: 10_000)

    assert snapshot.sequence == 7
    assert snapshot.nodes[snapshot.local_node_id].inspectable?
    assert snapshot.coverage.total_pids >= snapshot.coverage.inspected_pids
    assert snapshot.runtime_sample.process_count == map_size(snapshot.processes)
    assert snapshot.runtime_sample.application_count == map_size(snapshot.applications)
    assert snapshot.runtime_sample.ets_count >= 0
    assert snapshot.runtime_sample.memory_total > 0
    assert snapshot.runtime_sample.scheduler_count > 0
    refute Enum.any?(snapshot.processes, fn {_id, process} -> process.pid == self() end)
    refute Enum.any?(snapshot.processes, fn {_id, process} -> process.label == "nil" end)
  end

  test "rejects details for a process absent from the snapshot" do
    assert {:ok, snapshot} = Local.snapshot(sequence: 1, process_limit: 10_000)

    pid =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    reference = Process.monitor(pid)
    send(pid, :stop)
    assert_receive {:DOWN, ^reference, :process, ^pid, :normal}

    assert {:error, :unavailable} = Local.detail(pid, snapshot)
  end
end
