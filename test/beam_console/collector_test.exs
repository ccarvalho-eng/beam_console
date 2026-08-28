defmodule BeamConsole.CollectorTest do
  use ExUnit.Case, async: false

  alias BeamConsole.Collector
  alias BeamConsole.Coverage
  alias BeamConsole.Lifecycle.Observation
  alias BeamConsole.Lifecycle.Recorder, as: LifecycleRecorder
  alias BeamConsole.Recorder.Config, as: RecorderConfig
  alias BeamConsole.Recording.Control, as: RecordingControl
  alias BeamConsole.Snapshot

  defmodule FakeRuntime do
    @behaviour BeamConsole.Runtime.Adapter

    @impl BeamConsole.Runtime.Adapter
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

  defmodule BlockingSupervisor do
    use GenServer

    def start_link(owner) do
      GenServer.start_link(__MODULE__, owner)
    end

    @impl GenServer
    def init(owner) do
      {:ok, owner}
    end

    @impl GenServer
    def handle_call(:which_children, _from, owner) do
      send(owner, :blocking_supervisor_called)
      {:noreply, owner}
    end
  end

  defmodule ProbeRuntime do
    @behaviour BeamConsole.Runtime.Adapter

    alias BeamConsole.Coverage
    alias BeamConsole.Runtime.Supervision
    alias BeamConsole.Snapshot

    @impl BeamConsole.Runtime.Adapter
    def snapshot(options) do
      owner = Keyword.fetch!(options, :owner)
      sequence = Keyword.fetch!(options, :sequence)
      supervisor = Keyword.fetch!(options, :blocking_supervisor)
      send(owner, {:probe_scan_started, sequence})

      _result = Supervision.collect([{:fixture, supervisor}], node(), options)

      {:ok,
       %Snapshot{
         sequence: sequence,
         sampled_at: DateTime.utc_now(),
         local_node_id: "node",
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

  test "repeat subscription resets outstanding delivery state", %{collector: collector} do
    assert {:ok, nil} = Collector.subscribe(collector)
    assert_receive {:scan_started, 1, scanner}
    send(scanner, :release)
    assert_receive {:beam_console_snapshot, 1}

    assert {:ok, %Snapshot{sequence: 1}} = Collector.subscribe(collector)
    Collector.refresh(collector)
    assert_receive {:scan_started, 2, scanner}
    send(scanner, :release)
    assert_receive {:beam_console_snapshot, 2}
  end

  test "rate limits operator refresh requests", %{collector: collector} do
    assert {:ok, nil} = Collector.subscribe(collector)
    assert_receive {:scan_started, 1, scanner}

    assert :ok = Collector.request_refresh(collector)
    assert {:error, :rate_limited} = Collector.request_refresh(collector)

    send(scanner, :release)
    assert_receive {:beam_console_snapshot, 1}
    assert_receive {:scan_started, 2, next_scanner}
    send(next_scanner, :release)
  end

  test "acknowledges internal reconciliation independently of operator cooldown", %{
    collector: collector
  } do
    assert :ok = Collector.request_refresh(collector)
    assert {:error, :rate_limited} = Collector.request_refresh(collector)
    assert :ok = Collector.request_reconciliation(collector)

    assert_receive {:scan_started, 1, scanner}
    send(scanner, :release)
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

    snapshot = Collector.latest_snapshot(collector)
    assert snapshot.lifecycle_observations == []
    assert snapshot.collector_epoch == options[:source_epoch]
  end

  test "uses the injected monotonic clock for committed recorder frames" do
    assert_receive {:"$gen_cast", :deactivate}

    name = Module.concat(__MODULE__, "ClockedCollector#{System.unique_integer([:positive])}")

    collector =
      start_supervised!(
        Supervisor.child_spec(
          {Collector,
           name: name,
           runtime: FakeRuntime,
           runtime_options: [owner: self()],
           lifecycle_recorder: self(),
           monotonic_clock: fn -> 42 end,
           interval: 60_000,
           scan_timeout: 2_000,
           task_supervisor: BeamConsole.TaskSupervisor},
          id: name
        )
      )

    assert {:ok, nil} = Collector.subscribe(collector)
    assert_receive {:scan_started, 1, scanner}, 1_000
    send(scanner, :release)

    assert_receive {:"$gen_cast", {:observe, frame, [], _options}}
    assert frame.monotonic_ms == 42
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

  test "does not deactivate always-on recording when the final viewer leaves" do
    assert_receive {:"$gen_cast", :deactivate}

    name =
      Module.concat(__MODULE__, "AlwaysSubscriberCollector#{System.unique_integer([:positive])}")

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
    assert_receive {:"$gen_cast", {:observe, _frame, [], _options}}

    assert {:ok, %Snapshot{sequence: 1}} = Collector.subscribe(collector)
    assert_receive {:"$gen_cast", :activate}
    assert :ok = Collector.unsubscribe(collector)

    refute_receive {:"$gen_cast", :deactivate}
  end

  test "an always-on collector resumes sampling after restart without a viewer" do
    assert_receive {:"$gen_cast", :deactivate}

    name =
      Module.concat(__MODULE__, "RestartedAlwaysCollector#{System.unique_integer([:positive])}")

    collector_spec =
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

    _collector = start_supervised!(collector_spec)
    assert_receive {:scan_started, 1, scanner}
    send(scanner, :release)
    assert_receive {:"$gen_cast", :activate}
    assert_receive {:"$gen_cast", {:observe, _frame, [], _options}}

    assert :ok = stop_supervised(name)
    _replacement_collector = start_supervised!(collector_spec)
    assert_receive {:scan_started, 1, replacement_scanner}
    send(replacement_scanner, :release)
    assert_receive {:"$gen_cast", :activate}
    assert_receive {:"$gen_cast", {:observe, _frame, [], _options}}
  end

  test "a paused always-on collector settles one in-flight scan and stops without viewers" do
    control = start_recording_control()
    name = Module.concat(__MODULE__, "PausedAlwaysCollector#{System.unique_integer([:positive])}")

    collector =
      start_supervised!(
        Supervisor.child_spec(
          {Collector,
           name: name,
           runtime: FakeRuntime,
           runtime_options: [owner: self()],
           lifecycle_recorder: self(),
           recording_control: control,
           always_record?: true,
           interval: 20,
           scan_timeout: 2_000,
           task_supervisor: BeamConsole.TaskSupervisor},
          id: name
        )
      )

    assert_receive {:scan_started, 1, scanner}
    RecordingControl.pause(control)
    assert eventually(fn -> :sys.get_state(collector).recording_paused? end)

    send(scanner, :release)
    refute_receive {:scan_started, 2, _scanner}, 100

    assert :ok = Collector.request_reconciliation(collector)
    refute_receive {:scan_started, 2, _scanner}, 100

    assert :ok = Collector.request_refresh(collector)
    assert_receive {:scan_started, 2, manual_scanner}
    send(manual_scanner, :release)
    refute_receive {:scan_started, 3, _scanner}, 100

    RecordingControl.resume(control)
    assert_receive {:scan_started, 3, resumed_scanner}
    send(resumed_scanner, :release)
  end

  test "a connected viewer keeps live sampling while recording is paused" do
    control = start_recording_control()
    name = Module.concat(__MODULE__, "PausedViewerCollector#{System.unique_integer([:positive])}")

    collector =
      start_supervised!(
        Supervisor.child_spec(
          {Collector,
           name: name,
           runtime: FakeRuntime,
           runtime_options: [owner: self()],
           lifecycle_recorder: self(),
           recording_control: control,
           always_record?: true,
           interval: 20,
           scan_timeout: 2_000,
           task_supervisor: BeamConsole.TaskSupervisor},
          id: name
        )
      )

    assert {:ok, nil} = Collector.subscribe(collector)
    assert_receive {:scan_started, 1, scanner}
    RecordingControl.pause(control)
    assert eventually(fn -> :sys.get_state(collector).recording_paused? end)

    send(scanner, :release)
    assert_receive {:beam_console_snapshot, 1}
    assert :ok = Collector.acknowledge(1, collector)
    assert_receive {:scan_started, 2, next_scanner}
    send(next_scanner, :release)
    assert_receive {:beam_console_snapshot, 2}
    assert :ok = Collector.unsubscribe(collector)
    refute_receive {:scan_started, 3, _scanner}, 100
  end

  test "a failed in-flight scan cannot revive paused zero-viewer sampling" do
    control = start_recording_control()

    name =
      Module.concat(__MODULE__, "PausedFailureCollector#{System.unique_integer([:positive])}")

    collector =
      start_supervised!(
        Supervisor.child_spec(
          {Collector,
           name: name,
           runtime: FakeRuntime,
           runtime_options: [owner: self()],
           recording_control: control,
           always_record?: true,
           interval: 20,
           scan_timeout: 2_000,
           task_supervisor: BeamConsole.TaskSupervisor},
          id: name
        )
      )

    assert_receive {:scan_started, 1, scanner}
    RecordingControl.pause(control)
    assert eventually(fn -> :sys.get_state(collector).recording_paused? end)
    send(scanner, {:release, {:error, :fixture_failure}})

    assert eventually_after(fn -> not Collector.status(collector).scanning? end)
    refute_receive {:scan_started, 2, _scanner}, 100
  end

  test "a timed-out in-flight scan cannot revive paused zero-viewer sampling" do
    control = start_recording_control()

    name =
      Module.concat(__MODULE__, "PausedTimeoutCollector#{System.unique_integer([:positive])}")

    collector =
      start_supervised!(
        Supervisor.child_spec(
          {Collector,
           name: name,
           runtime: FakeRuntime,
           runtime_options: [owner: self()],
           recording_control: control,
           always_record?: true,
           interval: 20,
           scan_timeout: 20,
           task_supervisor: BeamConsole.TaskSupervisor},
          id: name
        )
      )

    assert_receive {:scan_started, 1, _scanner}
    RecordingControl.pause(control)
    assert eventually(fn -> :sys.get_state(collector).recording_paused? end)

    assert eventually_after(fn -> not Collector.status(collector).scanning? end)
    refute_receive {:scan_started, 2, _scanner}, 100
  end

  test "a paused control prevents restarted always-on collectors from sampling" do
    control = start_recording_control()
    RecordingControl.pause(control)

    name =
      Module.concat(__MODULE__, "RestartPausedCollector#{System.unique_integer([:positive])}")

    collector_spec =
      Supervisor.child_spec(
        {Collector,
         name: name,
         runtime: FakeRuntime,
         runtime_options: [owner: self()],
         lifecycle_recorder: self(),
         recording_control: control,
         always_record?: true,
         interval: 20,
         scan_timeout: 2_000,
         task_supervisor: BeamConsole.TaskSupervisor},
        id: name
      )

    _collector = start_supervised!(collector_spec)
    refute_receive {:scan_started, 1, _scanner}, 100

    assert :ok = stop_supervised(name)
    _replacement = start_supervised!(collector_spec)
    refute_receive {:scan_started, 1, _scanner}, 100
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

    assert_receive {:beam_console_snapshot, 1}

    assert %Collector.Status{
             sequence: 1,
             stale?: true,
             scanning?: false,
             last_error: %BeamConsole.ReasonSummary{text: "atom"}
           } = Collector.status(collector)

    assert Collector.latest_snapshot(collector).stale?
    assert :ok = Collector.acknowledge(1, collector)

    Collector.refresh(collector)
    assert_receive {:scan_started, 2, recovery_scanner}

    state = :sys.get_state(collector)
    assert state.snapshot.sequence == 1
    assert %BeamConsole.ReasonSummary{text: "atom"} = state.last_error
    send(recovery_scanner, :release)
    assert_receive {:beam_console_snapshot, 2}
    assert eventually(fn -> :sys.get_state(collector).last_error == nil end)
    refute Collector.latest_snapshot(collector).stale?
  end

  test "recovers after a runtime task crashes", %{collector: collector} do
    assert {:ok, nil} = Collector.subscribe(collector)
    assert_receive {:scan_started, 1, crashing_scanner}
    crashing_monitor = Process.monitor(crashing_scanner)
    send(crashing_scanner, {:release, :crash})

    assert_receive {:DOWN, ^crashing_monitor, :process, ^crashing_scanner, :runtime_crash}
    assert_receive {:beam_console_snapshot, 0}
    assert :ok = Collector.acknowledge(0, collector)
    Collector.refresh(collector)
    assert_receive {:scan_started, 1, recovery_scanner}

    assert %BeamConsole.ReasonSummary{text: "atom"} =
             :sys.get_state(collector).last_error

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
    assert_receive {:beam_console_snapshot, 0}
    assert :ok = Collector.acknowledge(0, collector)

    Collector.refresh(collector)
    assert_receive {:scan_started, 1, recovery_scanner}

    assert %BeamConsole.ReasonSummary{text: "atom"} =
             :sys.get_state(collector).last_error

    send(recovery_scanner, :release)
    assert_receive {:beam_console_snapshot, 1}
  end

  test "scan timeouts terminate nested supervision probes" do
    blocking_supervisor = start_supervised!({BlockingSupervisor, self()})
    baseline = length(Task.Supervisor.children(BeamConsole.TaskSupervisor))
    name = Module.concat(__MODULE__, "ProbeTimeoutCollector#{System.unique_integer([:positive])}")

    collector =
      start_supervised!(
        Supervisor.child_spec(
          {Collector,
           name: name,
           runtime: ProbeRuntime,
           runtime_options: [owner: self(), blocking_supervisor: blocking_supervisor],
           interval: 60_000,
           scan_timeout: 20,
           supervisor_timeout: 60_000,
           task_supervisor: BeamConsole.TaskSupervisor},
          id: name
        )
      )

    assert {:ok, nil} = Collector.subscribe(collector)

    Enum.each(1..3, fn attempt ->
      if attempt > 1 do
        Collector.refresh(collector)
      end

      assert_receive {:probe_scan_started, 1}, 1_000

      if attempt == 1 do
        assert_receive :blocking_supervisor_called
      end

      assert_receive {:beam_console_snapshot, 0}
      assert :ok = Collector.acknowledge(0, collector)

      assert eventually(fn ->
               length(Task.Supervisor.children(BeamConsole.TaskSupervisor)) == baseline
             end)
    end)
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

  defp start_recording_control do
    name = Module.concat(__MODULE__, "RecordingControl#{System.unique_integer([:positive])}")

    start_supervised!(Supervisor.child_spec({RecordingControl, name: name}, id: name))
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

  defp eventually_after(fun, attempts \\ 100)

  defp eventually_after(fun, attempts) when attempts > 0 do
    if fun.() do
      true
    else
      Process.sleep(1)
      eventually_after(fun, attempts - 1)
    end
  end

  defp eventually_after(_fun, 0) do
    false
  end
end
