defmodule BeamConsoleDemo.ProcessLab.RelationshipWatcher do
  @moduledoc false

  use GenServer

  @processor BeamConsoleDemo.ProcessLab.PaymentProcessor

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  def monitored_pid do
    GenServer.call(__MODULE__, :monitored_pid)
  end

  @impl true
  def init(_options) do
    {:ok, attach_monitor(%{monitor_pid: nil, monitor_ref: nil})}
  end

  @impl true
  def handle_call(:monitored_pid, _from, state) do
    state = if state.monitor_ref, do: state, else: attach_monitor(state)
    {:reply, state.monitor_pid, state}
  end

  @impl true
  def handle_info({:DOWN, reference, :process, _pid, _reason}, %{monitor_ref: reference} = state) do
    Process.send_after(self(), :reattach, 25)
    {:noreply, %{state | monitor_pid: nil, monitor_ref: nil}}
  end

  def handle_info(:reattach, state) do
    state = attach_monitor(state)

    if is_nil(state.monitor_ref) do
      Process.send_after(self(), :reattach, 25)
    end

    {:noreply, state}
  end

  defp attach_monitor(state) do
    case Process.whereis(@processor) do
      nil -> state
      pid -> %{state | monitor_pid: pid, monitor_ref: Process.monitor(pid)}
    end
  end
end
