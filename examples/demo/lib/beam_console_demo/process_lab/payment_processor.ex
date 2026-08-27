defmodule BeamConsoleDemo.ProcessLab.PaymentProcessor do
  @moduledoc false

  use GenServer

  @doc "Starts the named demo payment processor."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: Keyword.fetch!(options, :name))
  end

  @impl GenServer
  def init(_options) do
    {:ok, %{processed: 0}}
  end
end
