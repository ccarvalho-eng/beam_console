defmodule BeamConsole.CollectorTest do
  use ExUnit.Case, async: false

  alias BeamConsole.Collector
  alias BeamConsole.Coverage
  alias BeamConsole.Lifecycle.Observation
  alias BeamConsole.Lifecycle.Recorder, as: LifecycleRecorder
  alias BeamConsole.Recorder.Config, as: RecorderConfig
  alias BeamConsole.Snapshot

  defmodule FakeRuntime do
    @behaviour BeamConsole.Runtime.Adapter

    @impl true
    def snapshot(options) do
      owner = Keyword.fetch!(options, :owner)
      send(owner, {:scan_started, Keyword.fetch!(options, :sequence), self()})

      receive do
        :release ->
          successful_snapshot(options)

        {:release, {:ok, observations}} ->
          successful_snapshot(options, observations)

        {:release, {:error, reason}} ->
          {:error, reason}

        {:release, :crash} ->
          exit(:runtime_crash)
      end
    end

    defp successful_snapshot(options, observations \\ []) do
      sequence = Keyword.fetch!(options, :sequence)

      {:ok,
       %Snapshot{
         sequence: sequence,
         sampled_at: DateTime.utc_now(),
         local_node_id: "node",
         lifecycle_observations: observations,
         coverage: %Coverage{}
       }}
    end
  end

  setup do
    name = Module.concat(__MODULE__, "Collector#{System.unique_integer([:positive])}")

    collector =
      start_supervised!(
        {Collector,
         name: name,
         runtime: FakeRuntime,
         runtime_options: [owner: self()],
         lifecycle_recorder: self(),
         interval: 60_000,
         scan_timeout: 2_000,
         task_supervisor: BeamConsole.TaskSupervisor}
      )

    %{collector: collector}
  end

  test "coalesces refreshes into one follow-up scan", %{collector: collector} do
    assert {:ok, nil} = Collector.subscribe(collector)
    assert_receive {:scan_started, 1, scanner}

    Collector.refresh(collector)
    Collector.refresh(collector)
    refute_receive {:scan_started, 2, _pid}

    send(scanner, :release)
    assert_receive {:beam_console_snapshot, 1}
    assert_receive {:scan_started, 2, next_scanner}
    send(next_scanner, :release)
    refute_receive {:beam_console_snapshot, 2}

    assert :ok = Collector.acknowledge(1, collector)
    assert_receive {:beam_console_snapshot, 2}
  end

  test "remains idle until a subscriber arrives", %{collector: collector} do
    refute_receive {:scan_started, _sequence, _pid}
    assert {:ok, nil} = Collector.subscribe(collector)
    assert_receive {:scan_started, 1, scanner}
    send(scanner, :release)
  end

  test "deactivates after the last viewer while allowing the in-flight scan to finish", %{
    collector: collector
  } do
    assert {:ok, nil} = Collector.subscribe(collector)
    assert_receive {:"$gen_cast", :activate}
    assert_receive {:scan_started, 1, scanner}

    assert :ok = Collector.unsubscribe(collector)
    assert_receive {:"$gen_cast", :deactivate}
    send(scanner, :release)

    assert_receive {:"$gen_cast", {:observe, frame, [], _options}}
    assert frame.sequence == 1
    refute_receive {:beam_console_snapshot, _sequence}
    refute_receive {:scan_started, 2, _scanner}
  end

  test "hands private observations to the recorder and strips the public snapshot", %{
    collector: collector
  } do
    observation = %Observation{
      slot_id: "slot_fixture",
      slot_kind: :stable,
      supervisor_pid: self(),
      child_pid: self(),
      child_state: :running,
      child_type: :worker,
      modules: [__MODULE__],
      sequence: 1,
      coverage: :complete
    }

    assert {:ok, nil} = Collector.subscribe(collector)
    assert_receive {:"$gen_cast", :activate}
    assert_receive {:scan_started, 1, scanner}
    send(scanner, {:release, {:ok, [observation]}})

    assert_receive {:beam_console_snapshot, 1}
    assert_receive {:"$gen_cast", :activate}

    assert_receive {:"$gen_cast", {:observe, frame, [^observation], options}}
    assert frame.sequence == 1
    assert frame.coverage == :complete
    assert options[:reset?] == false
    assert is_binary(options[:source_epoch])

    assert Collector.latest_snapshot(collector).lifecycle_observations == []
  end

  test "does not send sampling task observations to the lifecycle recorder", %{
    collector: collector
  } do
    observation = %Observation{
      slot_id: "slot_probe",
      slot_kind: :dynamic,
      supervisor_pid: Process.whereis(BeamConsole.TaskSupervisor),
      child_pid: self(),
      child_state: :running,
      child_type: :worker,
      modules: [Task.Supervised],
      sequence: 1,
      coverage: :complete
    }

    assert {:ok, nil} = Collector.subscribe(collector)
    assert_receive {:scan_started, 1, scanner}
    send(scanner, {:release, {:ok, [observation]}})

    assert_receive {:beam_console_snapshot, 1}
    assert_receive {:"$gen_cast", {:observe, frame, [], _options}}
    assert frame.sequence == 1
  end

  test "samples for always recording before any viewer subscribes" do
    name = Module.concat(__MODULE__, "AlwaysCollector#{System.unique_integer([:positive])}")

    collector =
      start_supervised!(
        Supervisor.child_spec(
          {Collector,
           name: name,
           runtime: FakeRuntime,
           runtime_options: [owner: self()],
           lifecycle_recorder: self(),
           always_record?: true,
           interval: 60_000,
           scan_timeout: 2_000,
           task_supervisor: BeamConsole.TaskSupervisor},
          id: name
        )
      )

    assert_receive {:scan_started, 1, scanner}
    send(scanner, :release)

    assert_receive {:"$gen_cast", :activate}
    assert_receive {:"$gen_cast", {:observe, frame, [], options}}
    assert frame.sequence == 1
    assert options[:reset?] == false
    assert is_binary(options[:source_epoch])
    assert Collector.latest_snapshot(collector).sequence == 1
  end

  test "reactivates a restarted recorder while a viewer remains subscribed" do
    suffix = System.unique_integer([:positive])
    recorder_name = Module.concat(__MODULE__, "RestartingRecorder#{suffix}")
    collector_name = Module.concat(__MODULE__, "RecoveryCollector#{suffix}")

    recorder_spec =
      Supervisor.child_spec(
        {LifecycleRecorder, name: recorder_name, config: RecorderConfig.new!(), collector: nil},
        id: recorder_name
      )

    _recorder = start_supervised!(recorder_spec)

    collector =
      start_supervised!(
        Supervisor.child_spec(
          {Collector,
           name: collector_name,
           runtime: FakeRuntime,
           runtime_options: [owner: self()],
           lifecycle_recorder: recorder_name,
           interval: 60_000,
           scan_timeout: 2_000,
           task_supervisor: BeamConsole.TaskSupervisor},
          id: collector_name
        )
      )

    assert {:ok, nil} = Collector.subscribe(collector)
    assert_receive {:scan_started, 1, scanner}
    send(scanner, :release)
    assert_receive {:beam_console_snapshot, 1}
    assert eventually(fn -> LifecycleRecorder.status(recorder_name).history.frame_count == 1 end)

    assert :ok = stop_supervised(recorder_name)
    assert Process.whereis(recorder_name) == nil
    _replacement_recorder = start_supervised!(recorder_spec)

    assert :ok = Collector.acknowledge(1, collector)
    Collector.refresh(collector)
    assert_receive {:scan_started, 2, scanner}
    send(scanner, :release)
    assert_receive {:beam_console_snapshot, 2}

    assert eventually(fn ->
             status = LifecycleRecorder.status(recorder_name)
             status.active? and status.history.last_sequence == 2
           end)
  end

  test "coalesces one hundred commits for a stalled subscriber", %{collector: collector} do
    assert {:ok, nil} = Collector.subscribe(collector)
    assert_receive {:scan_started, 1, scanner}
    owner = self()

    fast_subscriber =
      spawn_link(fn ->
        assert {:ok, nil} = Collector.subscribe(collector)
        send(owner, :fast_subscribed)
        fast_subscriber_loop(collector, owner)
      end)

    assert_receive :fast_subscribed
    send(scanner, :release)
    assert_receive {:beam_console_snapshot, 1}
    assert_receive {:fast_snapshot, 1}

    Enum.each(2..100, fn sequence ->
      Collector.refresh(collector)
      assert_receive {:scan_started, ^sequence, scanner}
      send(scanner, :release)
      assert_receive {:fast_snapshot, ^sequence}
    end)

    refute_receive {:beam_console_snapshot, _sequence}

    state = :sys.get_state(collector)
    delivery = Map.fetch!(state.subscribers, self())
    assert delivery.outstanding_sequence == 1
    assert delivery.pending_sequence == 100

    assert :ok = Collector.acknowledge(1, collector)
    assert_receive {:beam_console_snapshot, 100}

    delivery = :sys.get_state(collector).subscribers |> Map.fetch!(self())
    assert delivery.outstanding_sequence == 100
    assert delivery.pending_sequence == nil

    send(fast_subscriber, :stop)
  end

  test "ignores invalid acknowledgements and provides bounded catch-up", %{collector: collector} do
    assert {:ok, nil} = Collector.subscribe(collector)
    assert_receive {:scan_started, 1, scanner}
    send(scanner, :release)
    assert_receive {:beam_console_snapshot, 1}

    assert :ok = Collector.acknowledge(0, collector)
    assert :ok = Collector.acknowledge(2, collector)
    refute_receive {:beam_console_snapshot, _sequence}

    assert {:ok, [%BeamConsole.Diff{from_sequence: 0, to_sequence: 1}]} =
             Collector.changes_since(0, collector)

    assert {:ok, []} = Collector.changes_since(1, collector)
    assert {:resync, %Snapshot{sequence: 1}} = Collector.changes_since(99, collector)

    assert :ok = Collector.acknowledge(1, collector)
    assert :ok = Collector.acknowledge(1, collector)
  end

  test "scopes acknowledgements to the calling subscriber", %{collector: collector} do
    assert {:ok, nil} = Collector.subscribe(collector)
    assert_receive {:scan_started, 1, scanner}
    owner = self()

    stalled_subscriber =
      spawn_link(fn ->
        assert {:ok, nil} = Collector.subscribe(collector)
        send(owner, :stalled_subscriber_ready)
        controlled_subscriber_loop(collector, owner)
      end)

    assert_receive :stalled_subscriber_ready
    send(scanner, :release)
    assert_receive {:beam_console_snapshot, 1}
    assert_receive {:controlled_snapshot, 1}

    assert :ok = Collector.acknowledge(1, collector)
    Collector.refresh(collector)
    assert_receive {:scan_started, 2, scanner}
    send(scanner, :release)
    assert_receive {:beam_console_snapshot, 2}
    refute_receive {:controlled_snapshot, 2}

    send(stalled_subscriber, {:acknowledge, 1})
    assert_receive {:controlled_snapshot, 2}
    send(stalled_subscriber, :stop)
  end

  test "removes a dead subscriber without affecting the collector", %{collector: collector} do
    owner = self()

    subscriber =
      spawn(fn ->
        assert {:ok, nil} = Collector.subscribe(collector)
        send(owner, :subscriber_ready)

        receive do
          :stop -> :ok
        end
      end)

    monitor = Process.monitor(subscriber)
    assert_receive :subscriber_ready
    assert_receive {:scan_started, 1, scanner}

    send(subscriber, :stop)
    assert_receive {:DOWN, ^monitor, :process, ^subscriber, :normal}

    assert eventually(fn ->
             not Map.has_key?(:sys.get_state(collector).subscribers, subscriber)
           end)

    send(scanner, :release)

    assert eventually(fn ->
             match?(%Snapshot{sequence: 1}, :sys.get_state(collector).snapshot)
           end)

    refute_receive {:beam_console_snapshot, _sequence}
  end

  test "preserves the last good snapshot and recovers from runtime errors", %{
    collector: collector
  } do
    assert {:ok, nil} = Collector.subscribe(collector)
    assert_receive {:scan_started, 1, first_scanner}
    send(first_scanner, :release)
    assert_receive {:beam_console_snapshot, 1}
    assert :ok = Collector.acknowledge(1, collector)

    Collector.refresh(collector)
    assert_receive {:scan_started, 2, failing_scanner}
    failing_monitor = Process.monitor(failing_scanner)
    send(failing_scanner, {:release, {:error, :runtime_unavailable}})
    assert_receive {:DOWN, ^failing_monitor, :process, ^failing_scanner, :normal}

    Collector.refresh(collector)
    assert_receive {:scan_started, 2, recovery_scanner}

    state = :sys.get_state(collector)
    assert state.snapshot.sequence == 1
    assert state.last_error == :runtime_unavailable
    refute_receive {:beam_console_snapshot, _sequence}

    send(recovery_scanner, :release)
    assert_receive {:beam_console_snapshot, 2}
    assert eventually(fn -> :sys.get_state(collector).last_error == nil end)
  end

  test "recovers after a runtime task crashes", %{collector: collector} do
    assert {:ok, nil} = Collector.subscribe(collector)
    assert_receive {:scan_started, 1, crashing_scanner}
    crashing_monitor = Process.monitor(crashing_scanner)
    send(crashing_scanner, {:release, :crash})

    assert_receive {:DOWN, ^crashing_monitor, :process, ^crashing_scanner, :runtime_crash}
    Collector.refresh(collector)
    assert_receive {:scan_started, 1, recovery_scanner}
    assert :sys.get_state(collector).last_error == :runtime_crash

    send(recovery_scanner, :release)
    assert_receive {:beam_console_snapshot, 1}
  end

  test "recovers after a scan timeout" do
    name = Module.concat(__MODULE__, "TimeoutCollector#{System.unique_integer([:positive])}")

    collector =
      start_supervised!(
        Supervisor.child_spec(
          {Collector,
           name: name,
           runtime: FakeRuntime,
           runtime_options: [owner: self()],
           interval: 60_000,
           scan_timeout: 20,
           task_supervisor: BeamConsole.TaskSupervisor},
          id: name
        )
      )

    assert {:ok, nil} = Collector.subscribe(collector)
    assert_receive {:scan_started, 1, timed_out_scanner}
    timeout_monitor = Process.monitor(timed_out_scanner)
    assert_receive {:DOWN, ^timeout_monitor, :process, ^timed_out_scanner, _reason}

    Collector.refresh(collector)
    assert_receive {:scan_started, 1, recovery_scanner}
    assert :sys.get_state(collector).last_error == :scan_timeout

    send(recovery_scanner, :release)
    assert_receive {:beam_console_snapshot, 1}
  end

  test "does not recursively resample when internal probe tasks exit" do
    suffix = System.unique_integer([:positive])
    recorder_name = Module.concat(__MODULE__, "LoopRecorder#{suffix}")
    collector_name = Module.concat(__MODULE__, "LoopCollector#{suffix}")

    recorder =
      start_supervised!(
        Supervisor.child_spec(
          {LifecycleRecorder,
           name: recorder_name, config: RecorderConfig.new!(), collector: collector_name},
          id: recorder_name
        )
      )

    collector =
      start_supervised!(
        Supervisor.child_spec(
          {Collector,
           name: collector_name,
           lifecycle_recorder: recorder,
           interval: 60_000,
           scan_timeout: 2_000,
           task_supervisor: BeamConsole.TaskSupervisor},
          id: collector_name
        )
      )

    assert {:ok, nil} = Collector.subscribe(collector)
    assert_receive {:beam_console_snapshot, 1}, 2_000
    assert :ok = Collector.acknowledge(1, collector)

    refute_receive {:beam_console_snapshot, 2}, 250
    assert :sys.get_state(collector).sequence == 1
  end

  defp fast_subscriber_loop(collector, owner) do
    receive do
      {:beam_console_snapshot, sequence} ->
        :ok = Collector.acknowledge(sequence, collector)
        send(owner, {:fast_snapshot, sequence})
        fast_subscriber_loop(collector, owner)

      :stop ->
        Collector.unsubscribe(collector)
    end
  end

  defp controlled_subscriber_loop(collector, owner) do
    receive do
      {:beam_console_snapshot, sequence} ->
        send(owner, {:controlled_snapshot, sequence})
        controlled_subscriber_loop(collector, owner)

      {:acknowledge, sequence} ->
        :ok = Collector.acknowledge(sequence, collector)
        controlled_subscriber_loop(collector, owner)

      :stop ->
        Collector.unsubscribe(collector)
    end
  end

  defp eventually(fun, attempts \\ 1_000)

  defp eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      true
    else
      :erlang.yield()
      eventually(fun, attempts - 1)
    end
  end

  defp eventually(_fun, 0) do
    false
  end
end
