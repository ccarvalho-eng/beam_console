defmodule BeamConsole.Collector do
  @moduledoc false

  use GenServer

  alias BeamConsole.Config
  alias BeamConsole.Diff
  alias BeamConsole.Runtime.Local

  defstruct name: nil,
            runtime: Local,
            runtime_options: [],
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

  @type state :: %__MODULE__{}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options) do
    name = Keyword.get(options, :name, __MODULE__)
    GenServer.start_link(__MODULE__, Keyword.put(options, :name, name), name: name)
  end

  @spec subscribe(GenServer.server()) :: {:ok, BeamConsole.Snapshot.t() | nil}
  def subscribe(server \\ __MODULE__) do
    GenServer.call(server, {:subscribe, self()})
  end

  @spec unsubscribe(GenServer.server()) :: :ok
  def unsubscribe(server \\ __MODULE__) do
    GenServer.call(server, {:unsubscribe, self()})
  end

  @spec refresh(GenServer.server()) :: :ok
  def refresh(server \\ __MODULE__) do
    GenServer.cast(server, :refresh)
  end

  @spec latest_snapshot(GenServer.server()) :: BeamConsole.Snapshot.t() | nil
  def latest_snapshot(server \\ __MODULE__) do
    GenServer.call(server, :latest_snapshot)
  end

  @spec current_diff(GenServer.server()) :: Diff.t() | nil
  def current_diff(server \\ __MODULE__) do
    GenServer.call(server, :current_diff)
  end

  @impl true
  def init(options) do
    state = %__MODULE__{
      name: Keyword.fetch!(options, :name),
      runtime: Keyword.get(options, :runtime, Local),
      runtime_options: Keyword.get(options, :runtime_options, []),
      task_supervisor: Keyword.get(options, :task_supervisor, BeamConsole.TaskSupervisor),
      interval: Config.get(options, :interval),
      scan_timeout: Config.get(options, :scan_timeout),
      diff_limit: Config.get(options, :diff_limit)
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:subscribe, subscriber}, _from, state) do
    state = add_subscriber(state, subscriber)
    state = if map_size(state.subscribers) == 1, do: request_scan(state), else: state
    {:reply, {:ok, state.snapshot}, state}
  end

  def handle_call({:unsubscribe, subscriber}, _from, state) do
    {:reply, :ok, remove_subscriber(state, subscriber)}
  end

  def handle_call(:latest_snapshot, _from, state) do
    {:reply, state.snapshot, state}
  end

  def handle_call(:current_diff, _from, state) do
    {:reply, state.diff, state}
  end

  @impl true
  def handle_cast(:refresh, state) do
    {:noreply, request_scan(state)}
  end

  @impl true
  def handle_info(:scan, %{scan: nil} = state) do
    {:noreply, start_scan(%{state | tick_ref: nil, pending_refresh?: false})}
  end

  def handle_info(:scan, state) do
    {:noreply, %{state | tick_ref: nil, pending_refresh?: true}}
  end

  def handle_info({reference, {:ok, snapshot}}, %{scan: %{ref: reference}} = state) do
    Process.demonitor(reference, [:flush])
    cancel_timer(state.scan_timeout_ref)

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

    notify_subscribers(next_state, diff)
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
      ^reference -> {:noreply, remove_subscriber(state, subscriber)}
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
    %{state | tick_ref: Process.send_after(self(), :scan, 0)}
  end

  defp request_scan(%{scan: nil} = state) do
    state
  end

  defp request_scan(state) do
    %{state | pending_refresh?: true}
  end

  defp schedule_after_scan(%{pending_refresh?: true} = state) do
    request_scan(%{state | pending_refresh?: false})
  end

  defp schedule_after_scan(state) when map_size(state.subscribers) > 0 do
    cancel_timer(state.tick_ref)
    %{state | tick_ref: Process.send_after(self(), :scan, state.interval)}
  end

  defp schedule_after_scan(state) do
    state
  end

  defp add_subscriber(state, subscriber) do
    if Map.has_key?(state.subscribers, subscriber) do
      state
    else
      reference = Process.monitor(subscriber)
      %{state | subscribers: Map.put(state.subscribers, subscriber, reference)}
    end
  end

  defp remove_subscriber(state, subscriber) do
    case Map.pop(state.subscribers, subscriber) do
      {nil, subscribers} ->
        %{state | subscribers: subscribers}

      {reference, subscribers} ->
        Process.demonitor(reference, [:flush])

        state = %{state | subscribers: subscribers}

        if map_size(subscribers) == 0 do
          cancel_timer(state.tick_ref)
          %{state | tick_ref: nil, pending_refresh?: false}
        else
          state
        end
    end
  end

  defp notify_subscribers(state, diff) do
    Enum.each(state.subscribers, fn {subscriber, _reference} ->
      send(subscriber, {:beam_console_snapshot, state.snapshot.sequence, diff})
    end)
  end

  defp cancel_timer(nil) do
    :ok
  end

  defp cancel_timer(reference) do
    _result = Process.cancel_timer(reference)
    :ok
  end
end
