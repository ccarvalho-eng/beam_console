defmodule BeamConsoleDemo.ProcessLab.EphemeralWorker do
  @moduledoc false

  use GenServer

  @doc "Starts an unnamed temporary demo worker."
  @spec start_link(term()) :: GenServer.on_start()
  def start_link(child_id) do
    GenServer.start_link(__MODULE__, child_id)
  end

  @impl GenServer
  def init(child_id) do
    {:ok, %{child_id: child_id}}
  end
end
