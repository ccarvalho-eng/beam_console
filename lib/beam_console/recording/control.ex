defmodule BeamConsole.Recording.Control do
  @moduledoc """
  Owns restart-safe operator recording intent for the BeamConsole application.

  The process stores only a boolean pause state and a monotonic revision. The
  collector and lifecycle recorder register as monitored consumers, receive the
  current state during initialization, and receive later transitions as bounded
  scalar messages. A child restart therefore converges without coupling the two
  runtime services to each other.
  """

  use GenServer

  alias BeamConsole.Recording.Status

  @roles [:collector, :recorder]

  defstruct status: %Status{paused?: false, revision: 0}, consumers: %{}, subscribers: %{}

  @type role :: :collector | :recorder
  @type consumer :: %{pid: pid(), monitor_ref: reference()}
  @type t :: %__MODULE__{
          status: Status.t(),
          consumers: %{optional(role()) => consumer()},
          subscribers: %{optional(pid()) => reference()}
        }

  @doc "Starts the recording control authority."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options \\ []) do
    name = Keyword.get(options, :name, __MODULE__)
    GenServer.start_link(__MODULE__, options, name: name)
  end

  @doc "Registers the calling runtime service and returns the current control state."
  @spec register(role(), GenServer.server()) :: Status.t()
  def register(role, server \\ __MODULE__) when role in @roles do
    GenServer.call(server, {:register, role, self()})
  end

  @doc "Subscribes the calling process to authoritative recording-state transitions."
  @spec subscribe(GenServer.server(), timeout()) :: Status.t()
  def subscribe(server \\ __MODULE__, timeout \\ 5_000) do
    GenServer.call(server, {:subscribe, self()}, timeout)
  end

  @doc "Pauses lifecycle recording and opt-in zero-viewer background sampling."
  @spec pause(GenServer.server(), timeout()) :: Status.t()
  def pause(server \\ __MODULE__, timeout \\ 5_000) do
    GenServer.call(server, {:set_paused, true}, timeout)
  end

  @doc "Resumes lifecycle recording according to the configured demand mode."
  @spec resume(GenServer.server(), timeout()) :: Status.t()
  def resume(server \\ __MODULE__, timeout \\ 5_000) do
    GenServer.call(server, {:set_paused, false}, timeout)
  end

  @doc "Returns the authoritative operator recording control state."
  @spec status(GenServer.server(), timeout()) :: Status.t()
  def status(server \\ __MODULE__, timeout \\ 5_000) do
    GenServer.call(server, :status, timeout)
  end

  @impl GenServer
  def init(_options) do
    {:ok, %__MODULE__{}}
  end

  @impl GenServer
  def handle_call({:register, role, consumer}, _from, state)
      when role in @roles and is_pid(consumer) do
    consumers = register_consumer(state.consumers, role, consumer)
    {:reply, state.status, %{state | consumers: consumers}}
  end

  def handle_call({:subscribe, subscriber}, _from, state) when is_pid(subscriber) do
    subscribers = register_subscriber(state.subscribers, subscriber)
    {:reply, state.status, %{state | subscribers: subscribers}}
  end

  def handle_call({:set_paused, paused?}, _from, state) when is_boolean(paused?) do
    if state.status.paused? == paused? do
      {:reply, state.status, state}
    else
      status = %Status{paused?: paused?, revision: state.status.revision + 1}
      broadcast(state.consumers, state.subscribers, status)
      {:reply, status, %{state | status: status}}
    end
  end

  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end

  @impl GenServer
  def handle_info({:DOWN, monitor_ref, :process, pid, _reason}, state) do
    consumers = remove_consumer(state.consumers, pid, monitor_ref)
    subscribers = remove_subscriber(state.subscribers, pid, monitor_ref)
    {:noreply, %{state | consumers: consumers, subscribers: subscribers}}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp register_consumer(consumers, role, consumer) do
    case Map.get(consumers, role) do
      %{pid: ^consumer} ->
        consumers

      previous ->
        demonitor_consumer(previous)
        monitor_ref = Process.monitor(consumer)
        Map.put(consumers, role, %{pid: consumer, monitor_ref: monitor_ref})
    end
  end

  defp demonitor_consumer(%{monitor_ref: monitor_ref}) do
    Process.demonitor(monitor_ref, [:flush])
    :ok
  end

  defp demonitor_consumer(nil) do
    :ok
  end

  defp register_subscriber(subscribers, subscriber) do
    case Map.fetch(subscribers, subscriber) do
      {:ok, _monitor_ref} -> subscribers
      :error -> Map.put(subscribers, subscriber, Process.monitor(subscriber))
    end
  end

  defp broadcast(consumers, subscribers, status) do
    Enum.each(consumers, fn {_role, %{pid: consumer}} ->
      send(consumer, {__MODULE__, status})
    end)

    Enum.each(subscribers, fn {subscriber, _monitor_ref} ->
      send(subscriber, {__MODULE__, status})
    end)
  end

  defp remove_consumer(consumers, pid, monitor_ref) do
    Map.reject(consumers, fn {_role, consumer} ->
      consumer.pid == pid and consumer.monitor_ref == monitor_ref
    end)
  end

  defp remove_subscriber(subscribers, pid, monitor_ref) do
    case Map.get(subscribers, pid) do
      ^monitor_ref -> Map.delete(subscribers, pid)
      _other -> subscribers
    end
  end
end
