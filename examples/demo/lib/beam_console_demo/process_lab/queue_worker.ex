defmodule BeamConsoleDemo.ProcessLab.QueueWorker do
  @moduledoc false

  use GenServer

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: Keyword.fetch!(options, :name))
  end

  def enqueue(server, count) do
    Enum.each(1..count, fn number -> send(server, {:bounded_work, number}) end)
    :ok
  end

  @impl true
  def init(_options) do
    {:ok, %{checksum: 0, processed: 0}}
  end

  @impl true
  def handle_info({:bounded_work, number}, state) do
    checksum = Enum.reduce(1..2_000, state.checksum, &rem(&1 + &2 + number, 1_000_003))
    {:noreply, %{state | checksum: checksum, processed: state.processed + 1}}
  end
end
