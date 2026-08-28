defmodule BeamConsole.Recording do
  @moduledoc """
  Coordinates operator control of BeamConsole recording demand.

  Pausing removes lifecycle watches and suppresses opt-in always-on background
  scans after the last viewer disconnects. Connected viewers continue receiving
  live read-only runtime samples. Retained recorder history remains bounded and
  available while recording is paused.
  """

  alias BeamConsole.Recording.Control
  alias BeamConsole.Recording.Status

  @doc "Pauses recording and zero-viewer background sampling."
  @spec pause(GenServer.server(), timeout()) :: Status.t()
  def pause(server \\ Control, timeout \\ 5_000) do
    Control.pause(server, timeout)
  end

  @doc "Resumes recording according to the configured demand mode."
  @spec resume(GenServer.server(), timeout()) :: Status.t()
  def resume(server \\ Control, timeout \\ 5_000) do
    Control.resume(server, timeout)
  end

  @doc "Returns the authoritative operator recording control state."
  @spec status(GenServer.server(), timeout()) :: Status.t()
  def status(server \\ Control, timeout \\ 5_000) do
    Control.status(server, timeout)
  end
end
