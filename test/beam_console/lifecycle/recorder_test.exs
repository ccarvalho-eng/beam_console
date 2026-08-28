defmodule BeamConsole.Lifecycle.RecorderTest do
  use ExUnit.Case, async: false

  alias BeamConsole.Lifecycle.Observation
  alias BeamConsole.Lifecycle.Recorder
  alias BeamConsole.Recorder.Config
  alias BeamConsole.Recorder.Frame

  test "records sanitized direct exits only after lazy activation" do
    recorder = start_recorder()
    worker = waiting_process()

    Recorder.observe(frame(1, 1_000), [observation(worker, 1)], [], recorder)
    assert Recorder.status(recorder).active? == false
    assert Recorder.status(recorder).watched == 0

    Recorder.activate(recorder)
    Recorder.observe(frame(1, 1_000), [observation(worker, 1)], [], recorder)

    status = Recorder.status(recorder)
    assert status.active?
    assert status.watched == 1
    assert status.eligible == 1

    monitor = Process.monitor(worker)
    Process.exit(worker, {:fixture_failure, "private-value"})
    assert_receive {:DOWN, ^monitor, :process, ^worker, {:fixture_failure, "private-value"}}

    assert eventually(fn -> Recorder.status(recorder).watched == 0 end)
    result = Recorder.events([now_ms: 1_000], recorder)
    event = Enum.find(result.items, &(&1.kind == :terminated))

    assert event.evidence == :monitor
    assert event.certainty == :direct
    assert event.reason.category == :error
    assert event.reason.text == "{atom, binary(13 bytes)}"
    refute event.reason.text =~ "private-value"
    refute is_pid(event.entity_id)
    assert Recorder.status(recorder).pending_correlations == 1
  end

  test "deactivation removes watches and ignores an in-flight observation" do
    recorder = start_recorder()
    first = waiting_process()
    second = waiting_process()

    Recorder.activate(recorder)
    Recorder.observe(frame(1, 1_000), [observation(first, 1)], [], recorder)
    assert Recorder.status(recorder).watched == 1

    Recorder.deactivate(recorder)
    Recorder.observe(frame(2, 2_000), [observation(second, 2)], [], recorder)

    status = Recorder.status(recorder)
    assert status.active? == false
    assert status.watched == 0
    assert status.recording_started_at_ms == nil

    Process.exit(first, :kill)
    Process.exit(second, :kill)

    assert Recorder.events([now_ms: 2_000], recorder).items
           |> Enum.all?(&(&1.kind != :terminated))
  end

  test "always mode remains active when subscriber deactivation arrives" do
    recorder = start_recorder(mode: :always)
    worker = waiting_process()

    assert Recorder.status(recorder).active?
    Recorder.deactivate(recorder)
    Recorder.observe(frame(1, 1_000), [observation(worker, 1)], [], recorder)
    assert Recorder.status(recorder).watched == 1

    Recorder.deactivate(recorder)
    assert Recorder.status(recorder).active?
    Process.exit(worker, :kill)
  end

  test "operator pause survives automatic activation until explicitly resumed" do
    recorder = start_recorder()
    first = waiting_process()
    second = waiting_process()

    Recorder.activate(recorder)
    Recorder.observe(frame(1, 1_000), [observation(first, 1)], [], recorder)
    assert Recorder.status(recorder).watched == 1

    assert %BeamConsole.Recorder.Status{activity: :paused, demanded?: true} =
             Recorder.pause(recorder)

    Recorder.activate(recorder)
    Recorder.observe(frame(2, 2_000), [observation(second, 2)], [], recorder)

    paused = Recorder.status(recorder)
    assert paused.activity == :paused
    refute paused.active?
    assert paused.watched == 0

    assert %BeamConsole.Recorder.Status{activity: :recording, active?: true} =
             Recorder.resume(recorder)

    Recorder.observe(frame(2, 2_000), [observation(second, 2)], [], recorder)
    assert Recorder.status(recorder).watched == 1

    Process.exit(first, :kill)
    Process.exit(second, :kill)
  end

  test "operator pause overrides always mode" do
    recorder = start_recorder(mode: :always)

    assert Recorder.pause(recorder).activity == :paused
    Recorder.deactivate(recorder)
    assert Recorder.status(recorder).activity == :paused
    assert Recorder.resume(recorder).activity == :recording
  end

  test "resume requests a deferred reconciliation when recording demand remains" do
    owner = self()
    requester = fn -> send(owner, :refresh_requested) end
    recorder = start_recorder([mode: :always], refresh_requester: requester)

    assert Recorder.pause(recorder).activity == :paused
    assert Recorder.resume(recorder).activity == :recording
    assert_receive :refresh_requested
  end

  test "a monitored exit requests reconciliation without blocking the recorder" do
    owner = self()

    requester = fn ->
      send(owner, {:refresh_request_started, self()})

      receive do
        :release_refresh -> :ok
      end
    end

    recorder =
      start_recorder(
        [],
        refresh_requester: requester,
        refresh_timeout: 1_000
      )

    worker = waiting_process()
    Recorder.activate(recorder)
    Recorder.observe(frame(1, 1_000), [observation(worker, 1)], [], recorder)
    assert Recorder.status(recorder).watched == 1

    Process.exit(worker, :kill)
    assert_receive {:refresh_request_started, requester_pid}
    assert Recorder.status(recorder).active?

    send(requester_pid, :release_refresh)
    assert eventually(fn -> Recorder.status(recorder).missed_reconciliations == 0 end)
  end

  test "requester failures are sanitized and counted without stopping recording" do
    requester = fn -> raise "private requester failure" end
    recorder = start_recorder([], refresh_requester: requester)
    worker = waiting_process()

    Recorder.activate(recorder)
    Recorder.observe(frame(1, 1_000), [observation(worker, 1)], [], recorder)
    Process.exit(worker, :kill)

    assert eventually(fn ->
             status = Recorder.status(recorder)
             status.active? and status.missed_reconciliations == 1
           end)
  end

  test "coalesces a burst of reconciliation requests behind one bounded follow-up" do
    owner = self()

    requester = fn ->
      send(owner, {:refresh_request_started, self()})

      receive do
        :release_refresh -> :ok
      end
    end

    recorder =
      start_recorder(
        [mode: :always],
        refresh_requester: requester,
        refresh_timeout: 1_000
      )

    Enum.each(1..100, fn _index ->
      send(recorder, :reconcile_after_down)
    end)

    assert_receive {:refresh_request_started, first_requester}
    send(first_requester, :release_refresh)
    assert_receive {:refresh_request_started, second_requester}
    send(second_requester, :release_refresh)
    refute_receive {:refresh_request_started, _requester}
    assert Recorder.status(recorder).missed_reconciliations == 0
  end

  test "times out a wedged reconciliation requester and remains responsive" do
    owner = self()

    requester = fn ->
      send(owner, :wedged_refresh_started)
      Process.sleep(:infinity)
    end

    recorder =
      start_recorder(
        [mode: :always],
        refresh_requester: requester,
        refresh_timeout: 20
      )

    send(recorder, :reconcile_after_down)
    assert_receive :wedged_refresh_started

    assert eventually(fn ->
             status = Recorder.status(recorder)
             status.active? and status.missed_reconciliations == 1
           end)
  end

  test "waits for a timed-out request to terminate before starting its coalesced successor" do
    owner = self()

    requester = fn ->
      send(owner, {:refresh_callback_started, self()})
      Process.sleep(:infinity)
    end

    recorder =
      start_recorder(
        [mode: :always],
        refresh_requester: requester,
        refresh_timeout: 20
      )

    send(recorder, :reconcile_after_down)
    send(recorder, :reconcile_after_down)
    assert_receive {:refresh_callback_started, _first_callback}

    first_guardian = :sys.get_state(recorder).refresh_request.pid
    guardian_ref = Process.monitor(first_guardian)

    assert_receive {:DOWN, ^guardian_ref, :process, ^first_guardian, _reason}
    assert_receive {:refresh_callback_started, _second_callback}
  end

  test "terminates an in-flight requester when its recorder stops" do
    owner = self()
    name = Module.concat(__MODULE__, "OwnedRequest#{System.unique_integer([:positive])}")

    requester = fn ->
      send(owner, {:owned_refresh_started, self()})
      Process.sleep(:infinity)
    end

    child_spec =
      Supervisor.child_spec(
        {Recorder,
         name: name,
         config: Config.new!(mode: :always),
         refresh_requester: requester,
         refresh_timeout: 1_000},
        id: name
      )

    recorder = start_supervised!(child_spec)
    send(recorder, :reconcile_after_down)
    assert_receive {:owned_refresh_started, callback}
    callback_ref = Process.monitor(callback)

    assert :ok = stop_supervised(name)
    assert_receive {:DOWN, ^callback_ref, :process, ^callback, _reason}
  end

  test "preserves the compatible collector option's asynchronous refresh protocol" do
    name = Module.concat(__MODULE__, "LegacyCollector#{System.unique_integer([:positive])}")

    recorder =
      start_supervised!(
        Supervisor.child_spec(
          {Recorder,
           name: name, config: Config.new!(mode: :always), collector: self(), refresh_timeout: 20},
          id: name
        )
      )

    send(recorder, :reconcile_after_down)
    assert_receive {:"$gen_cast", :refresh}
    assert eventually(fn -> Recorder.status(recorder).missed_reconciliations == 0 end)
  end

  test "counts an unavailable acknowledged collector requester" do
    missing_collector =
      Module.concat(__MODULE__, "UnavailableCollector#{System.unique_integer([:positive])}")

    requester = fn ->
      BeamConsole.Collector.request_reconciliation(missing_collector, 20)
    end

    recorder =
      start_recorder(
        [mode: :always],
        refresh_requester: requester,
        refresh_timeout: 50
      )

    send(recorder, :reconcile_after_down)

    assert eventually(fn ->
             Recorder.status(recorder).missed_reconciliations == 1
           end)
  end

  test "always mode resumes after recorder restart without subscriber demand" do
    name =
      Module.concat(__MODULE__, "RestartedAlwaysRecorder#{System.unique_integer([:positive])}")

    config = Config.new!(mode: :always)

    recorder_spec =
      Supervisor.child_spec(
        {Recorder, name: name, config: config, refresh_requester: nil},
        id: name
      )

    _recorder = start_supervised!(recorder_spec)
    assert %BeamConsole.Recorder.Status{active?: true, demanded?: true} = Recorder.status(name)

    assert :ok = stop_supervised(name)
    _replacement_recorder = start_supervised!(recorder_spec)
    assert %BeamConsole.Recorder.Status{active?: true, demanded?: true} = Recorder.status(name)
  end

  test "caps watch changes per frame and reports omitted and deferred coverage" do
    recorder = start_recorder(watch_limit: 2, reconciliation_limit: 1)
    workers = Enum.map(1..3, fn _index -> waiting_process() end)
    observations = Enum.map(workers, &observation(&1, 1))

    Recorder.activate(recorder)
    Recorder.observe(frame(1, 1_000), observations, [], recorder)

    first_status = Recorder.status(recorder)
    assert first_status.watched == 1
    assert first_status.eligible == 3
    assert first_status.omitted == 1
    assert first_status.deferred == 1

    Recorder.observe(frame(2, 2_000), Enum.map(workers, &observation(&1, 2)), [], recorder)

    second_status = Recorder.status(recorder)
    assert second_status.watched == 2
    assert second_status.eligible == 3
    assert second_status.omitted == 1
    assert second_status.deferred == 0

    Recorder.deactivate(recorder)
    assert Recorder.status(recorder).watched == 0
    Enum.each(workers, &Process.exit(&1, :kill))
  end

  test "requires two complete omissions and keeps watches across partial frames" do
    recorder = start_recorder()
    worker = waiting_process()

    Recorder.activate(recorder)
    Recorder.observe(frame(1, 1_000), [observation(worker, 1)], [], recorder)
    assert Recorder.status(recorder).watched == 1

    Recorder.observe(frame(2, 2_000, :partial), [], [], recorder)
    Recorder.observe(frame(3, 3_000, :truncated), [], [], recorder)
    assert Recorder.status(recorder).watched == 1

    Recorder.observe(frame(4, 4_000), [], [], recorder)
    assert Recorder.status(recorder).watched == 1

    Recorder.observe(frame(5, 5_000), [], [], recorder)
    assert Recorder.status(recorder).watched == 0
    assert Process.alive?(worker)
    Process.exit(worker, :kill)
  end

  test "does not create stable replacement candidates for dynamic children" do
    recorder = start_recorder()
    worker = waiting_process()

    Recorder.activate(recorder)

    dynamic =
      worker
      |> observation(1)
      |> Map.put(:slot_kind, :dynamic)

    Recorder.observe(frame(1, 1_000), [dynamic], [], recorder)
    assert Recorder.status(recorder).watched == 1

    Process.exit(worker, :kill)
    assert eventually(fn -> Recorder.status(recorder).watched == 0 end)
    assert Recorder.status(recorder).pending_correlations == 0
  end

  test "expires pending stable-slot exits at the configured boundary" do
    recorder = start_recorder(pending_slot_ms: 30_000)
    worker = waiting_process()

    Recorder.activate(recorder)
    Recorder.observe(frame(1, 1_000), [observation(worker, 1)], [], recorder)
    Process.exit(worker, :kill)

    assert eventually(fn -> Recorder.status(recorder).pending_correlations == 1 end)

    Recorder.observe(frame(2, 31_000), [], [], recorder)
    assert Recorder.status(recorder).pending_correlations == 1

    Recorder.observe(frame(3, 31_001), [], [], recorder)
    assert Recorder.status(recorder).pending_correlations == 0
  end

  test "emits a replacement event when the same stable slot receives a new PID" do
    recorder = start_recorder()
    original = waiting_process()
    replacement = waiting_process()

    Recorder.activate(recorder)

    Recorder.observe(
      frame(1, 1_000),
      [observation(original, 1, slot_id: "stable-worker")],
      [],
      recorder
    )

    Process.exit(original, :kill)
    assert eventually(fn -> Recorder.status(recorder).pending_correlations == 1 end)

    Recorder.observe(
      frame(2, 2_000),
      [observation(replacement, 2, slot_id: "stable-worker")],
      [],
      recorder
    )

    result = Recorder.events([now_ms: 2_000], recorder)
    event = Enum.find(result.items, &(&1.kind == :replacement_observed))

    assert event.certainty == :strong
    assert event.label == "Replacement observed"
    assert Recorder.status(recorder).pending_correlations == 0

    Recorder.deactivate(recorder)
    Process.exit(replacement, :kill)
  end

  test "starts a new segment when lazy recording resumes with a reset sequence" do
    recorder = start_recorder()

    Recorder.activate(recorder)
    Recorder.observe(frame(5, 5_000), [], [], recorder)
    Recorder.deactivate(recorder)
    Recorder.activate(recorder)
    Recorder.observe(frame(1, 6_000), [], [], recorder)

    result = Recorder.events([now_ms: 6_000], recorder)
    kinds = Enum.map(result.items, & &1.kind)

    assert Enum.count(kinds, &(&1 == :recording_started)) == 2
    assert :reset in kinds

    status = Recorder.status(recorder)
    assert status.history.last_sequence == 1
    assert status.history.segment == 1
  end

  test "resets the segment when a restarted collector repeats a sequence" do
    recorder = start_recorder(mode: :always)

    Recorder.observe(frame(1, 1_000), [], [source_epoch: "collector-a"], recorder)
    Recorder.observe(frame(1, 2_000), [], [source_epoch: "collector-b"], recorder)

    status = Recorder.status(recorder)
    assert status.history.last_sequence == 1
    assert status.history.segment == 1

    result = Recorder.events([now_ms: 2_000], recorder)
    assert Enum.any?(result.items, &(&1.kind == :reset))
  end

  defp start_recorder(overrides \\ [], runtime_options \\ []) do
    name = Module.concat(__MODULE__, "Recorder#{System.unique_integer([:positive])}")

    config =
      [
        retention_ms: 60_000,
        event_limit: 100,
        frame_limit: 100,
        watch_limit: 100,
        reconciliation_limit: 100,
        pending_slot_ms: 30_000,
        timeline_limit: 100
      ]
      |> Keyword.merge(overrides)
      |> Config.new!()

    start_supervised!(
      Supervisor.child_spec(
        {Recorder,
         Keyword.merge(
           [
             name: name,
             config: config,
             refresh_requester: nil,
             monotonic_clock: fn -> 1_000 end,
             system_clock: fn -> 1_700_000_000_000 end
           ],
           runtime_options
         )},
        id: name
      )
    )
  end

  defp waiting_process do
    pid =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :kill)
      end
    end)

    pid
  end

  defp frame(sequence, monotonic_ms, coverage \\ :complete) do
    %Frame{
      sequence: sequence,
      sampled_at_ms: 1_700_000_000_000 + monotonic_ms,
      monotonic_ms: monotonic_ms,
      coverage: coverage
    }
  end

  defp observation(pid, sequence, overrides \\ []) do
    defaults = [
      slot_id: "slot-#{inspect(pid)}",
      slot_kind: :stable,
      supervisor_pid: self(),
      child_pid: pid,
      child_state: :running,
      child_type: :worker,
      modules: [__MODULE__],
      sequence: sequence,
      coverage: :complete
    ]

    defaults
    |> Keyword.merge(overrides)
    |> then(&struct!(Observation, &1))
  end

  defp eventually(fun, attempts \\ 500)

  defp eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      true
    else
      Process.sleep(1)
      eventually(fun, attempts - 1)
    end
  end

  defp eventually(_fun, 0) do
    false
  end
end
