defmodule BeamConsoleDemo.ProcessLab.PaymentsSupervisor do
  @moduledoc false

  use Supervisor

  def start_link(options) do
    Supervisor.start_link(__MODULE__, options, name: __MODULE__)
  end

  @impl true
  def init(_options) do
    children = [
      {BeamConsoleDemo.ProcessLab.PaymentProcessor,
       name: BeamConsoleDemo.ProcessLab.PaymentProcessor},
      {BeamConsoleDemo.ProcessLab.QueueWorker, name: BeamConsoleDemo.ProcessLab.QueueWorker},
      BeamConsoleDemo.ProcessLab.RelationshipWatcher
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
