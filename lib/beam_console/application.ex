defmodule BeamConsole.Application do
  @moduledoc """
  Starts the shared runtime collector and its bounded scan task supervisor.

  Applications normally start this module through BeamConsole's OTP application
  specification rather than calling it directly.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: BeamConsole.TaskSupervisor},
      BeamConsole.Collector
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: BeamConsole.Supervisor)
  end
end
