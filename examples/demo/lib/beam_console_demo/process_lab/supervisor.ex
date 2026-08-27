defmodule BeamConsoleDemo.ProcessLab.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(options) do
    Supervisor.start_link(__MODULE__, options, name: __MODULE__)
  end

  @impl true
  def init(_options) do
    children = [
      BeamConsoleDemo.ProcessLab.PaymentsSupervisor,
      {Task.Supervisor, name: BeamConsoleDemo.ProcessLab.TaskSupervisor},
      {DynamicSupervisor,
       name: BeamConsoleDemo.ProcessLab.ChurnSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
