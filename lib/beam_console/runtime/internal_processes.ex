defmodule BeamConsole.Runtime.InternalProcesses do
  @moduledoc """
  Identifies transient processes owned by BeamConsole's sampling machinery.

  Sampling tasks must not become lifecycle observations themselves. Otherwise,
  their normal exits can request another sample and create a feedback loop.
  """

  alias BeamConsole.Lifecycle.Observation

  @spec task_supervisor_pid(GenServer.server()) :: pid() | nil
  @doc "Resolves the current PID for BeamConsole's sampling task supervisor."
  def task_supervisor_pid(server) do
    case GenServer.whereis(server) do
      pid when is_pid(pid) -> pid
      nil -> nil
    end
  catch
    :exit, _reason -> nil
  end

  @spec reject_probe_observations([Observation.t()], GenServer.server()) :: [Observation.t()]
  @doc "Removes lifecycle observations for children owned by the sampling task supervisor."
  def reject_probe_observations(observations, task_supervisor) do
    case task_supervisor_pid(task_supervisor) do
      pid when is_pid(pid) ->
        Enum.reject(observations, &(&1.supervisor_pid == pid))

      nil ->
        observations
    end
  end
end
