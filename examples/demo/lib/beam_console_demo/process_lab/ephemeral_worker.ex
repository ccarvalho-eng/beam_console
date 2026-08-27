defmodule BeamConsoleDemo.ProcessLab.EphemeralWorker do
  @moduledoc false

  use GenServer

  def start_link(child_id) do
    GenServer.start_link(__MODULE__, child_id)
  end

  @impl true
  def init(child_id) do
    {:ok, %{child_id: child_id}}
  end
end
