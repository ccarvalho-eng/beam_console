defmodule BeamConsole.Collector do
  @moduledoc """
  Owns a shared, bounded, non-overlapping runtime sampling loop.

  The collector remains idle without subscribers in the default lazy mode,
  runs scans outside its own mailbox, retains the last completed snapshot, and
  emits coalesced version invalidations to each monitored subscriber. Explicit
  always-recording mode keeps the same bounded scan loop active without viewers.
  """

  use GenServer

  alias BeamConsole.Activity
  alias BeamConsole.Collector.Status
  alias BeamConsole.Collector.Subscriber
  alias BeamConsole.Config
  alias BeamConsole.Diff
  alias BeamConsole.EntityId
  alias BeamConsole.Lifecycle.Recorder, as: LifecycleRecorder
  alias BeamConsole.Lifecycle.DiffEvents
  alias BeamConsole.ReasonSummary
  alias BeamConsole.Recorder.Frame
  alias BeamConsole.Runtime.InternalProcesses
  alias BeamConsole.Runtime.Local
  alias BeamConsole.Snapshot

  defstruct name: nil,
            runtime: Local,
            runtime_options: [],
            lifecycle_recorder: nil,
            always_record?: false,
            recorder_gap?: false,
            recorder_epoch: nil,
            task_supervisor: BeamConsole.TaskSupervisor,
            interval: 2_000,
            scan_timeout: 1_500,
            diff_limit: 500,
            sequence: 0,
            snapshot: nil,
            diff: nil,
            subscribers: %{},
            scan: nil,
            scan_timeout_ref: nil,
            tick_ref: nil,
            pending_refresh?: false,
            last_error: nil,
            last_failure_at: nil,
            refresh_cooldown: 250,
            last_operator_refresh_ms: nil,
            monotonic_clock: nil

  @type t :: %__MODULE__{
          name: GenServer.name() | nil,
          runtime: module(),
          runtime_options: keyword(),
          lifecycle_recorder: GenServer.server() | nil,
          always_record?: boolean(),
          recorder_gap?: boolean(),
          recorder_epoch: String.t(),
          task_supervisor: Supervisor.supervisor(),
          interval: non_neg_integer(),
          scan_timeout: non_neg_integer(),
          diff_limit: non_neg_integer(),
          sequence: non_neg_integer(),
          snapshot: BeamConsole.Snapshot.t() | nil,
          diff: Diff.t() | nil,
          subscribers: %{pid() => Subscriber.t()},
          scan: Task.t() | nil,
          scan_timeout_ref: reference() | nil,
          tick_ref: {reference(), reference()} | nil,
          pending_refresh?: boolean(),
          last_error: ReasonSummary.t() | nil,
          last_failure_at: DateTime.t() | nil,
          refresh_cooldown: non_neg_integer(),
          last_operator_refresh_ms: integer() | nil,
          monotonic_clock: (-> integer())
        }

  @type state :: t()

  @doc "Starts a collector with optional runtime, interval, and limit overrides."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options) do
    name = Keyword.get(options, :name, __MODULE__)
    GenServer.start_link(__MODULE__, Keyword.put(options, :name, name), name: name)
  end

  @doc "Subscribes the caller and starts sampling when it is the first subscriber."
  @spec subscribe(GenServer.server(), timeout()) :: {:ok, BeamConsole.Snapshot.t() | nil}
  def subscribe(server \\ __MODULE__, timeout \\ 5_000) do
    GenServer.call(server, {:subscribe, self()}, timeout)
  end

  @doc "Unsubscribes the caller and stops scheduled sampling when no subscribers remain."
  @spec unsubscribe(GenServer.server()) :: :ok
  def unsubscribe(server \\ __MODULE__) do
    GenServer.call(server, {:unsubscribe, self()})
  end

  @doc "Acknowledges the caller's outstanding snapshot version and releases its newest pending version."
  @spec acknowledge(non_neg_integer(), GenServer.server(), timeout()) :: :ok
  def acknowledge(sequence, server \\ __MODULE__, timeout \\ 5_000)
      when is_integer(sequence) and sequence >= 0 do
    GenServer.call(server, {:acknowledge, self(), sequence}, timeout)
  end

  @doc "Requests a scan, coalescing the request when a scan is already running."
  @spec refresh(GenServer.server()) :: :ok
  def refresh(server \\ __MODULE__) do
    GenServer.cast(server, :refresh)
  end

  @doc "Requests an operator scan while enforcing the configured refresh cooldown."
  @spec request_refresh(GenServer.server(), timeout()) :: :ok | {:error, :rate_limited}
  def request_refresh(server \\ __MODULE__, timeout \\ 5_000) do
    GenServer.call(server, :request_refresh, timeout)
  end

  @doc "Requests an acknowledged internal reconciliation scan without operator rate limiting."
  @spec request_reconciliation(GenServer.server(), timeout()) :: :ok
  def request_reconciliation(server \\ __MODULE__, timeout \\ 5_000) do
    GenServer.call(server, :request_reconciliation, timeout)
  end

  @doc "Returns the most recent completed snapshot."
  @spec latest_snapshot(GenServer.server(), timeout()) :: BeamConsole.Snapshot.t() | nil
  def latest_snapshot(server \\ __MODULE__, timeout \\ 5_000) do
    GenServer.call(server, :latest_snapshot, timeout)
  end

  @doc "Returns the bounded diff produced by the most recent completed scan."
  @spec current_diff(GenServer.server()) :: Diff.t() | nil
  def current_diff(server \\ __MODULE__) do
    GenServer.call(server, :current_diff)
  end

  @doc "Returns bounded collector health and freshness information."
  @spec status(GenServer.server(), timeout()) :: Status.t()
  def status(server \\ __MODULE__, timeout \\ 5_000) do
    GenServer.call(server, :status, timeout)
  end

  @type changes_result :: {:ok, [Diff.t()]} | {:resync, BeamConsole.Snapshot.t() | nil}

  @doc "Returns the current bounded diff when it directly follows `sequence`, otherwise requests resync."
  @spec changes_since(non_neg_integer(), GenServer.server()) :: changes_result()
  def changes_since(sequence, server \\ __MODULE__) when is_integer(sequence) and sequence >= 0 do
    GenServer.call(server, {:changes_since, sequence})
  end

  @impl GenServer
  def init(options) do
    configured =
      options
      |> Keyword.take(Config.collector_keys())
      |> Config.collector()

    runtime_options =
      configured
      |> Keyword.take(Config.runtime_keys())
      |> Keyword.merge(Keyword.get(options, :runtime_options, []))

    state = %__MODULE__{
      name: Keyword.fetch!(options, :name),
      runtime: Keyword.get(options, :runtime, Local),
      runtime_options: runtime_options,
      lifecycle_recorder: Keyword.get(options, :lifecycle_recorder),
      always_record?: Keyword.get(options, :always_record?, false),
      recorder_epoch: EntityId.build(:event, {:collector_epoch, make_ref()}),
      task_supervisor: Keyword.get(options, :task_supervisor, BeamConsole.TaskSupervisor),
      interval: Keyword.fetch!(configured, :interval),
      scan_timeout: Keyword.fetch!(configured, :scan_timeout),
      diff_limit: Keyword.fetch!(configured, :diff_limit),
      refresh_cooldown: Keyword.fetch!(configured, :refresh_cooldown),
      monotonic_clock:
        Keyword.get(options, :monotonic_clock, fn ->
          System.monotonic_time(:millisecond)
        end)
    }

    if not state.always_record? do
      deactivate_lifecycle_recorder(state.lifecycle_recorder)
    end

    {:ok, if(state.always_record?, do: request_scan(state), else: state)}
  end

  @impl GenServer
  def handle_call({:subscribe, subscriber}, _from, state) do
    first_subscriber? =
      map_size(state.subscribers) == 0 and not Map.has_key?(state.subscribers, subscriber)

    state = add_subscriber(state, subscriber)
    state = if first_subscriber?, do: request_scan(state), else: state
    {:reply, {:ok, state.snapshot}, state}
  end

  def handle_call({:unsubscribe, subscriber}, _from, state) do
    {:reply, :ok, remove_subscriber(state, subscriber)}
  end

  def handle_call({:acknowledge, subscriber, sequence}, _from, state) do
    {:reply, :ok, acknowledge_subscriber(state, subscriber, sequence)}
  end

  def handle_call(:latest_snapshot, _from, state) do
    {:reply, state.snapshot, state}
  end

  def handle_call(:current_diff, _from, state) do
    {:reply, state.diff, state}
  end

  def handle_call(:status, _from, state) do
    {:reply, status_from_state(state), state}
  end

  def handle_call(:request_refresh, _from, state) do
    now_ms = state.monotonic_clock.()

    if refresh_allowed?(state, now_ms) do
      next_state = state |> request_scan() |> Map.put(:last_operator_refresh_ms, now_ms)
      {:reply, :ok, next_state}
    else
      {:reply, {:error, :rate_limited}, state}
    end
  end

  def handle_call(:request_reconciliation, _from, state) do
    {:reply, :ok, request_scan(state)}
  end

  def handle_call({:changes_since, sequence}, _from, state) do
    result = changes_since_sequence(state, sequence)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_cast(:refresh, state) do
    {:noreply, request_scan(state)}
  end

  @impl GenServer
  def handle_info({:scan, token}, %{scan: nil, tick_ref: {_timer, token}} = state) do
    {:noreply, start_scan(%{state | tick_ref: nil, pending_refresh?: false})}
  end

  def handle_info({:scan, token}, %{tick_ref: {_timer, token}} = state) do
    {:noreply, %{state | tick_ref: nil, pending_refresh?: true}}
  end

  def handle_info({:scan, _stale_token}, state) do
    {:noreply, state}
  end

  def handle_info({reference, {:ok, snapshot}}, %{scan: %{ref: reference}} = state) do
    Process.demonitor(reference, [:flush])
    cancel_timer(state.scan_timeout_ref)

    snapshot = %{snapshot | stale?: false, collector_epoch: state.recorder_epoch}
    monotonic_ms = state.monotonic_clock.()
    activity = Activity.sample(state.snapshot, snapshot, monotonic_ms)
    frame = Frame.from_snapshot(snapshot, monotonic_ms, activity)

    {snapshot, observations} =
      detach_lifecycle_observations(snapshot, state.task_supervisor)

    diff = Diff.between(state.snapshot, snapshot, state.diff_limit)
    lifecycle_events = DiffEvents.from_diff(diff, state.snapshot, snapshot, frame)

    state =
      deliver_lifecycle_observations(state, frame, observations, events: lifecycle_events)

    next_state =
      state
      |> Map.merge(%{
        snapshot: snapshot,
        diff: diff,
        sequence: snapshot.sequence,
        scan: nil,
        scan_timeout_ref: nil,
        last_error: nil,
        last_failure_at: nil
      })
      |> notify_subscribers()
      |> schedule_after_scan()

    {:noreply, next_state}
  end

  def handle_info({reference, {:error, reason}}, %{scan: %{ref: reference}} = state) do
    Process.demonitor(reference, [:flush])
    cancel_timer(state.scan_timeout_ref)

    {:noreply, fail_scan(state, reason)}
  end

  def handle_info({:DOWN, reference, :process, _pid, reason}, %{scan: %{ref: reference}} = state) do
    cancel_timer(state.scan_timeout_ref)

    {:noreply, fail_scan(state, reason)}
  end

  def handle_info({:scan_timeout, reference}, %{scan: %{ref: reference, pid: pid}} = state) do
    _result = Task.Supervisor.terminate_child(state.task_supervisor, pid)

    {:noreply, fail_scan(state, :scan_timeout)}
  end

  def handle_info({:DOWN, reference, :process, subscriber, _reason}, state) do
    case Map.get(state.subscribers, subscriber) do
      %Subscriber{monitor_ref: ^reference} -> {:noreply, remove_subscriber(state, subscriber)}
      _other -> {:noreply, state}
    end
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp start_scan(state) do
    sequence = state.sequence + 1
    options = Keyword.put(state.runtime_options, :sequence, sequence)

    task =
      Task.Supervisor.async_nolink(state.task_supervisor, fn ->
        run_scan(state.runtime, options)
      end)

    timeout_ref = Process.send_after(self(), {:scan_timeout, task.ref}, state.scan_timeout)
    %{state | scan: task, scan_timeout_ref: timeout_ref}
  end

  defp run_scan(runtime, options) do
    {:ok, probe_supervisor} = Task.Supervisor.start_link()
    options = Keyword.put(options, :probe_task_supervisor, probe_supervisor)

    try do
      runtime.snapshot(options)
    after
      stop_probe_supervisor(probe_supervisor)
    end
  end

  defp stop_probe_supervisor(probe_supervisor) do
    if Process.alive?(probe_supervisor) do
      Supervisor.stop(probe_supervisor, :normal)
    end
  catch
    :exit, _reason -> :ok
  end

  defp request_scan(%{scan: nil, tick_ref: nil} = state) do
    schedule_scan(state, 0)
  end

  defp request_scan(%{scan: nil} = state) do
    cancel_timer(state.tick_ref)
    schedule_scan(%{state | tick_ref: nil}, 0)
  end

  defp request_scan(state) do
    %{state | pending_refresh?: true}
  end

  defp refresh_allowed?(%{last_operator_refresh_ms: nil}, _now_ms) do
    true
  end

  defp refresh_allowed?(state, now_ms) do
    now_ms - state.last_operator_refresh_ms >= state.refresh_cooldown
  end

  defp fail_scan(state, reason) do
    snapshot =
      case state.snapshot do
        %Snapshot{} = snapshot -> %{snapshot | stale?: true}
        nil -> nil
      end

    state
    |> Map.merge(%{
      snapshot: snapshot,
      scan: nil,
      scan_timeout_ref: nil,
      last_error: ReasonSummary.sanitize(reason),
      last_failure_at: DateTime.utc_now(),
      recorder_gap?: true
    })
    |> notify_subscribers()
    |> schedule_after_scan()
  end

  defp status_from_state(state) do
    %Status{
      sequence: state.sequence,
      sampled_at: state.snapshot && state.snapshot.sampled_at,
      stale?: not is_nil(state.last_error),
      scanning?: not is_nil(state.scan),
      subscriber_count: map_size(state.subscribers),
      last_error: state.last_error,
      failed_at: state.last_failure_at
    }
  end

  defp schedule_after_scan(%{pending_refresh?: true} = state) do
    request_scan(%{state | pending_refresh?: false})
  end

  defp schedule_after_scan(state)
       when map_size(state.subscribers) > 0 or state.always_record? do
    cancel_timer(state.tick_ref)
    schedule_scan(%{state | tick_ref: nil}, state.interval)
  end

  defp schedule_after_scan(state) do
    state
  end

  defp add_subscriber(state, subscriber) do
    case Map.get(state.subscribers, subscriber) do
      %Subscriber{} = delivery ->
        delivery = %{
          delivery
          | outstanding_sequence: nil,
            pending_sequence: nil,
            last_acked_sequence: state.sequence
        }

        %{state | subscribers: Map.put(state.subscribers, subscriber, delivery)}

      nil ->
        reference = Process.monitor(subscriber)

        delivery = %Subscriber{
          monitor_ref: reference,
          last_acked_sequence: state.sequence
        }

        if map_size(state.subscribers) == 0 do
          activate_lifecycle_recorder(state.lifecycle_recorder)
        end

        %{state | subscribers: Map.put(state.subscribers, subscriber, delivery)}
    end
  end

  defp remove_subscriber(state, subscriber) do
    case Map.pop(state.subscribers, subscriber) do
      {nil, subscribers} ->
        %{state | subscribers: subscribers}

      {%Subscriber{} = delivery, subscribers} ->
        Process.demonitor(delivery.monitor_ref, [:flush])

        state
        |> Map.put(:subscribers, subscribers)
        |> after_subscriber_removed()
    end
  end

  defp after_subscriber_removed(%{subscribers: subscribers} = state)
       when map_size(subscribers) > 0 do
    state
  end

  defp after_subscriber_removed(%{always_record?: false} = state) do
    cancel_timer(state.tick_ref)
    deactivate_lifecycle_recorder(state.lifecycle_recorder)
    %{state | tick_ref: nil, pending_refresh?: false}
  end

  defp after_subscriber_removed(%{always_record?: true} = state) do
    state
  end

  defp notify_subscribers(state) do
    subscribers =
      Map.new(state.subscribers, fn {subscriber, delivery} ->
        {subscriber, notify_subscriber(subscriber, delivery, state.sequence)}
      end)

    %{state | subscribers: subscribers}
  end

  defp notify_subscriber(subscriber, %Subscriber{outstanding_sequence: nil} = delivery, sequence) do
    send(subscriber, {:beam_console_snapshot, sequence})
    %{delivery | outstanding_sequence: sequence}
  end

  defp notify_subscriber(_subscriber, delivery, sequence) do
    %{delivery | pending_sequence: sequence}
  end

  defp acknowledge_subscriber(state, subscriber, sequence) do
    case Map.get(state.subscribers, subscriber) do
      %Subscriber{outstanding_sequence: ^sequence} = delivery ->
        delivery = release_pending(subscriber, delivery, sequence)
        %{state | subscribers: Map.put(state.subscribers, subscriber, delivery)}

      _other ->
        state
    end
  end

  defp release_pending(_subscriber, %Subscriber{pending_sequence: nil} = delivery, sequence) do
    %{
      delivery
      | outstanding_sequence: nil,
        last_acked_sequence: max(delivery.last_acked_sequence, sequence)
    }
  end

  defp release_pending(subscriber, %Subscriber{pending_sequence: pending} = delivery, sequence) do
    send(subscriber, {:beam_console_snapshot, pending})

    %{
      delivery
      | outstanding_sequence: pending,
        pending_sequence: nil,
        last_acked_sequence: max(delivery.last_acked_sequence, sequence)
    }
  end

  defp changes_since_sequence(%{snapshot: nil}, _sequence) do
    {:resync, nil}
  end

  defp changes_since_sequence(%{snapshot: snapshot}, sequence)
       when snapshot.sequence == sequence do
    {:ok, []}
  end

  defp changes_since_sequence(%{diff: %Diff{} = diff}, sequence)
       when diff.from_sequence == sequence do
    {:ok, [diff]}
  end

  defp changes_since_sequence(state, _sequence) do
    {:resync, state.snapshot}
  end

  defp detach_lifecycle_observations(%Snapshot{} = snapshot, task_supervisor) do
    observations =
      InternalProcesses.reject_probe_observations(
        snapshot.lifecycle_observations,
        task_supervisor
      )

    {%{snapshot | lifecycle_observations: []}, observations}
  end

  defp deliver_lifecycle_observations(
         %{lifecycle_recorder: nil} = state,
         _frame,
         _observations,
         _options
       ) do
    state
  end

  defp deliver_lifecycle_observations(state, frame, observations, options) do
    recorder = state.lifecycle_recorder

    if recorder_available?(recorder) do
      if state.always_record? or map_size(state.subscribers) > 0 do
        LifecycleRecorder.activate(recorder)
      end

      LifecycleRecorder.observe(
        frame,
        observations,
        Keyword.merge(options,
          reset?: state.recorder_gap?,
          source_epoch: state.recorder_epoch
        ),
        recorder
      )

      %{state | recorder_gap?: false}
    else
      %{state | recorder_gap?: true}
    end
  end

  defp activate_lifecycle_recorder(nil) do
    :ok
  end

  defp activate_lifecycle_recorder(recorder) do
    LifecycleRecorder.activate(recorder)
  end

  defp deactivate_lifecycle_recorder(nil) do
    :ok
  end

  defp deactivate_lifecycle_recorder(recorder) do
    LifecycleRecorder.deactivate(recorder)
  end

  defp recorder_available?(recorder) do
    not is_nil(GenServer.whereis(recorder))
  catch
    :exit, _reason -> false
  end

  defp schedule_scan(state, delay) do
    token = make_ref()
    timer = Process.send_after(self(), {:scan, token}, delay)
    %{state | tick_ref: {timer, token}}
  end

  defp cancel_timer(nil) do
    :ok
  end

  defp cancel_timer(reference) do
    timer = if is_tuple(reference), do: elem(reference, 0), else: reference
    _result = Process.cancel_timer(timer)
    :ok
  end
end
