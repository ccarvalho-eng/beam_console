defmodule BeamConsole.Runtime.LocalTest do
  use ExUnit.Case, async: false

  alias BeamConsole.Runtime.Local

  test "collects a bounded local snapshot with node-aware processes" do
    assert {:ok, snapshot} = Local.snapshot(sequence: 7, process_limit: 10_000)

    assert snapshot.sequence == 7
    assert snapshot.nodes[snapshot.local_node_id].inspectable?
    assert snapshot.coverage.total_pids >= snapshot.coverage.inspected_pids
    assert snapshot.runtime_sample.process_count == snapshot.coverage.total_pids
    assert snapshot.runtime_sample.inspected_process_count == map_size(snapshot.processes)
    assert snapshot.runtime_sample.application_count == map_size(snapshot.applications)
    assert snapshot.runtime_sample.ets_count >= 0
    assert snapshot.runtime_sample.atom_count == :erlang.system_info(:atom_count)
    assert snapshot.runtime_sample.atom_limit == :erlang.system_info(:atom_limit)
    assert snapshot.runtime_sample.atom_count <= snapshot.runtime_sample.atom_limit
    assert snapshot.runtime_sample.memory_total > 0
    assert snapshot.runtime_sample.scheduler_count > 0
    refute Enum.any?(snapshot.processes, fn {_id, process} -> process.pid == self() end)
    refute Enum.any?(snapshot.processes, fn {_id, process} -> process.label == "nil" end)
  end

  test "separates the exact VM process total from the bounded inspected count" do
    assert {:ok, snapshot} = Local.snapshot(sequence: 1, process_limit: 1)

    assert snapshot.runtime_sample.process_count == snapshot.coverage.total_pids
    assert snapshot.runtime_sample.inspected_process_count == snapshot.coverage.inspected_pids
    assert snapshot.runtime_sample.process_count > snapshot.runtime_sample.inspected_process_count
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

  test "returns only bounded relationships from a relation-heavy process" do
    owner = self()

    target =
      spawn(fn ->
        children = Enum.map(1..100, fn _index -> waiting_process() end)
        Enum.each(children, &Process.link/1)
        send(owner, {:relations_ready, self()})

        receive do
          :stop -> Enum.each(children, &send(&1, :stop))
        end
      end)

    assert_receive {:relations_ready, ^target}
    on_exit(fn -> send(target, :stop) end)

    assert {:ok, snapshot} = Local.snapshot(sequence: 1, process_limit: 10_000)
    assert {:ok, detail} = Local.detail(target, snapshot, relationship_limit: 5)
    assert length(detail.links) == 5
    assert detail.relationship_counts.links == 100
    assert detail.relationship_omitted.links == 95
  end

  test "does not leave a late detail result in the caller mailbox after a timeout" do
    target = waiting_process()
    on_exit(fn -> send(target, :stop) end)

    assert {:ok, snapshot} = Local.snapshot(sequence: 1, process_limit: 10_000)
    assert {:error, :unavailable} = Local.detail(target, snapshot, detail_timeout: 0)

    Process.sleep(20)
    {:messages, messages} = Process.info(self(), :messages)

    refute Enum.any?(messages, fn
             {_reference, {:ok, %BeamConsole.ProcessDetail{}}} -> true
             _message -> false
           end)
  end

  test "makes only relationships captured by the snapshot selectable" do
    target = relation_process()
    visible_peer = waiting_process()
    on_exit(fn -> send(target, :stop) end)
    on_exit(fn -> send(visible_peer, :stop) end)

    link_process(target, visible_peer)
    assert {:ok, snapshot} = Local.snapshot(sequence: 1, process_limit: 10_000)
    assert {:ok, visible_detail} = Local.detail(target, snapshot)

    assert Enum.any?(visible_detail.links, fn relation ->
             relation.id == BeamConsole.EntityId.build(:process, {node(), visible_peer})
           end)

    omitted_peer = waiting_process()
    on_exit(fn -> send(omitted_peer, :stop) end)
    link_process(target, omitted_peer)

    assert {:ok, omitted_detail} = Local.detail(target, snapshot)

    assert Enum.any?(omitted_detail.links, fn relation ->
             relation.label == BeamConsole.EntityId.label(omitted_peer) and is_nil(relation.id)
           end)
  end

  test "returns bounded scheduling and memory diagnostics" do
    owner = self()

    target =
      spawn(fn ->
        Process.flag(:trap_exit, true)
        Process.flag(:priority, :high)
        send(owner, {:diagnostics_ready, self()})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:diagnostics_ready, ^target}
    on_exit(fn -> send(target, :stop) end)

    assert {:ok, snapshot} = Local.snapshot(sequence: 1, process_limit: 10_000)
    assert {:ok, detail} = Local.detail(target, snapshot)

    diagnostics = detail.diagnostics

    assert is_binary(diagnostics.initial_call)
    assert diagnostics.trap_exit
    assert diagnostics.priority == :high
    assert diagnostics.group_leader.label == BeamConsole.EntityId.label(Process.group_leader())
    assert is_integer(diagnostics.heap_size)
    assert is_integer(diagnostics.total_heap_size)
    assert diagnostics.total_heap_size >= diagnostics.heap_size
    assert is_integer(diagnostics.stack_size)
    assert is_integer(diagnostics.minor_gcs)
    assert is_integer(diagnostics.fullsweep_after)

    refute Map.has_key?(diagnostics, :dictionary)
    refute Map.has_key?(diagnostics, :messages)
    refute Map.has_key?(diagnostics, :stacktrace)
  end

  defp relation_process do
    spawn(fn -> relation_loop() end)
  end

  defp relation_loop do
    receive do
      {:link, pid, caller} ->
        Process.link(pid)
        send(caller, {:linked, self(), pid})
        relation_loop()

      :stop ->
        :ok
    end
  end

  defp link_process(target, peer) do
    send(target, {:link, peer, self()})
    assert_receive {:linked, ^target, ^peer}
  end

  defp waiting_process do
    spawn(fn ->
      receive do
        :stop -> :ok
      end
    end)
  end
end
