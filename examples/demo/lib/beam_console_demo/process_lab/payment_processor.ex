defmodule BeamConsoleDemo.ProcessLab.PaymentProcessor do
  @moduledoc false

  use GenServer

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: Keyword.fetch!(options, :name))
  end

  @impl true
  def init(_options) do
    {:ok, %{processed: 0}}
  end
end
