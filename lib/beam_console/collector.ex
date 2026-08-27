defmodule BeamConsole.Collector do
  @moduledoc """
  Owns a shared, bounded, non-overlapping runtime sampling loop.

  The collector remains idle without subscribers in the default lazy mode,
  runs scans outside its own mailbox, retains the last completed snapshot, and
  emits coalesced version invalidations to each monitored subscriber. Explicit
  always-recording mode keeps the same bounded scan loop active without viewers.
  """

  use GenServer

  alias BeamConsole.Config
  alias BeamConsole.Collector.Subscriber
  alias BeamConsole.Diff
  alias BeamConsole.EntityId
  alias BeamConsole.Lifecycle.Recorder, as: LifecycleRecorder
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
            previous_snapshot: nil,
            diff: nil,
            subscribers: %{},
            scan: nil,
            scan_timeout_ref: nil,
            tick_ref: nil,
            pending_refresh?: false,
            last_error: nil

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
          previous_snapshot: BeamConsole.Snapshot.t() | nil,
          diff: Diff.t() | nil,
          subscribers: %{pid() => Subscriber.t()},
          scan: Task.t() | nil,
          scan_timeout_ref: reference() | nil,
          tick_ref: {reference(), reference()} | nil,
          pending_refresh?: boolean(),
          last_error: term()
        }

  @type state :: t()

  @spec start_link(keyword()) :: GenServer.on_start()
  @doc "Starts a collector with optional runtime, interval, and limit overrides."
  def start_link(options) do
    name = Keyword.get(options, :name, __MODULE__)
    GenServer.start_link(__MODULE__, Keyword.put(options, :name, name), name: name)
  end

  @spec subscribe(GenServer.server()) :: {:ok, BeamConsole.Snapshot.t() | nil}
  @doc "Subscribes the caller and starts sampling when it is the first subscriber."
  def subscribe(server \\ __MODULE__) do
    GenServer.call(server, {:subscribe, self()})
  end

  @spec unsubscribe(GenServer.server()) :: :ok
  @doc "Unsubscribes the caller and stops scheduled sampling when no subscribers remain."
  def unsubscribe(server \\ __MODULE__) do
    GenServer.call(server, {:unsubscribe, self()})
  end

  @spec acknowledge(non_neg_integer(), GenServer.server()) :: :ok
  @doc "Acknowledges the caller's outstanding snapshot version and releases its newest pending version."
  def acknowledge(sequence, server \\ __MODULE__) when is_integer(sequence) and sequence >= 0 do
    GenServer.call(server, {:acknowledge, self(), sequence})
  end

  @spec refresh(GenServer.server()) :: :ok
  @doc "Requests a scan, coalescing the request when a scan is already running."
  def refresh(server \\ __MODULE__) do
    GenServer.cast(server, :refresh)
  end

  @spec latest_snapshot(GenServer.server()) :: BeamConsole.Snapshot.t() | nil
  @doc "Returns the most recent completed snapshot."
  def latest_snapshot(server \\ __MODULE__) do
    GenServer.call(server, :latest_snapshot)
  end

  @spec current_diff(GenServer.server()) :: Diff.t() | nil
  @doc "Returns the bounded diff produced by the most recent completed scan."
  def current_diff(server \\ __MODULE__) do
    GenServer.call(server, :current_diff)
  end

  @type changes_result :: {:ok, [Diff.t()]} | {:resync, BeamConsole.Snapshot.t() | nil}

  @spec changes_since(non_neg_integer(), GenServer.server()) :: changes_result()
  @doc "Returns the current bounded diff when it directly follows `sequence`, otherwise requests resync."
  def changes_since(sequence, server \\ __MODULE__) when is_integer(sequence) and sequence >= 0 do
    GenServer.call(server, {:changes_since, sequence})
  end

  @impl true
  def init(options) do
    state = %__MODULE__{
      name: Keyword.fetch!(options, :name),
      runtime: Keyword.get(options, :runtime, Local),
      runtime_options: Keyword.get(options, :runtime_options, []),
      lifecycle_recorder: Keyword.get(options, :lifecycle_recorder),
      always_record?: Keyword.get(options, :always_record?, false),
      recorder_epoch: EntityId.build(:event, {:collector_epoch, make_ref()}),
      task_supervisor: Keyword.get(options, :task_supervisor, BeamConsole.TaskSupervisor),
      interval: Config.get(options, :interval),
      scan_timeout: Config.get(options, :scan_timeout),
      diff_limit: Config.get(options, :diff_limit)
    }

    {:ok, if(state.always_record?, do: request_scan(state), else: state)}
  end

  @impl true
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

  def handle_call({:changes_since, sequence}, _from, state) do
    result = changes_since_sequence(state, sequence)
    {:reply, result, state}
  end

  @impl true
  def handle_cast(:refresh, state) do
    {:noreply, request_scan(state)}
  end

  @impl true
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

    frame = Frame.from_snapshot(snapshot, System.monotonic_time(:millisecond))

    {snapshot, observations} =
      detach_lifecycle_observations(snapshot, state.task_supervisor)

    state = deliver_lifecycle_observations(state, frame, observations)

    diff = Diff.between(state.snapshot, snapshot, state.diff_limit)

    next_state = %{
      state
      | previous_snapshot: state.snapshot,
        snapshot: snapshot,
        diff: diff,
        sequence: snapshot.sequence,
        scan: nil,
        scan_timeout_ref: nil,
        last_error: nil
    }

    next_state = notify_subscribers(next_state)
    {:noreply, schedule_after_scan(next_state)}
  end

  def handle_info({reference, {:error, reason}}, %{scan: %{ref: reference}} = state) do
    Process.demonitor(reference, [:flush])
    cancel_timer(state.scan_timeout_ref)

    {:noreply,
     schedule_after_scan(%{state | scan: nil, scan_timeout_ref: nil, last_error: reason})}
  end

  def handle_info({:DOWN, reference, :process, _pid, reason}, %{scan: %{ref: reference}} = state) do
    cancel_timer(state.scan_timeout_ref)

    {:noreply,
     schedule_after_scan(%{state | scan: nil, scan_timeout_ref: nil, last_error: reason})}
  end

  def handle_info({:scan_timeout, reference}, %{scan: %{ref: reference, pid: pid}} = state) do
    _result = Task.Supervisor.terminate_child(state.task_supervisor, pid)

    {:noreply,
     schedule_after_scan(%{
       state
       | scan: nil,
         scan_timeout_ref: nil,
         last_error: :scan_timeout
     })}
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
        state.runtime.snapshot(options)
      end)

    timeout_ref = Process.send_after(self(), {:scan_timeout, task.ref}, state.scan_timeout)
    %{state | scan: task, scan_timeout_ref: timeout_ref}
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
    if Map.has_key?(state.subscribers, subscriber) do
      state
    else
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

        state = %{state | subscribers: subscribers}

        if map_size(subscribers) == 0 and not state.always_record? do
          cancel_timer(state.tick_ref)
          deactivate_lifecycle_recorder(state.lifecycle_recorder)
          %{state | tick_ref: nil, pending_refresh?: false}
        else
          if map_size(subscribers) == 0 do
            deactivate_lifecycle_recorder(state.lifecycle_recorder)
          end

          state
        end
    end
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

  defp deliver_lifecycle_observations(%{lifecycle_recorder: nil} = state, _frame, _observations) do
    state
  end

  defp deliver_lifecycle_observations(state, frame, observations) do
    recorder = state.lifecycle_recorder

    if recorder_available?(recorder) do
      if state.always_record? or map_size(state.subscribers) > 0 do
        LifecycleRecorder.activate(recorder)
      end

      LifecycleRecorder.observe(
        frame,
        observations,
        [reset?: state.recorder_gap?, source_epoch: state.recorder_epoch],
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
