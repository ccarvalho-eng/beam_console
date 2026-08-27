defmodule BeamConsoleDemo.ProcessLab.PaymentsSupervisor do
  @moduledoc false

  use Supervisor

  @doc "Starts the demo payments supervision subtree."
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(options) do
    Supervisor.start_link(__MODULE__, options, name: __MODULE__)
  end

  @impl Supervisor
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
