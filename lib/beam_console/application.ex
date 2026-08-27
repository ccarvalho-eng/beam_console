defmodule BeamConsole.Application do
  @moduledoc """
  Starts the shared runtime collector and its bounded scan task supervisor.

  Applications normally start this module through BeamConsole's OTP application
  specification rather than calling it directly.
  """

  use Application

  @impl true
  def start(_type, _args) do
    recorder_config = BeamConsole.Config.recorder()

    children = [
      {Task.Supervisor, name: BeamConsole.TaskSupervisor},
      {BeamConsole.Lifecycle.Recorder, config: recorder_config},
      {BeamConsole.Collector,
       lifecycle_recorder: BeamConsole.Lifecycle.Recorder,
       always_record?: recorder_config.mode == :always}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: BeamConsole.Supervisor)
  end
end
