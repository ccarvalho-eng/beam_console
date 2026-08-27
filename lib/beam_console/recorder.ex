defmodule BeamConsole.Recorder do
  @moduledoc """
  Provides PID-free read access to BeamConsole's bounded process flight recorder.

  The recorder starts automatically according to its configured mode. The
  default `:subscribers` mode records while at least one BeamConsole page is
  connected; `:always` records from application startup.
  """

  alias BeamConsole.Lifecycle.Recorder, as: LifecycleRecorder
  alias BeamConsole.Recorder.Query

  @spec status(GenServer.server()) :: LifecycleRecorder.status()
  @doc "Returns recording activity, watch coverage, and bounded-history usage."
  def status(server \\ LifecycleRecorder) do
    LifecycleRecorder.status(server)
  end

  @spec events(keyword(), GenServer.server()) :: Query.t()
  @doc "Returns the newest bounded lifecycle events and explicit omission metadata."
  def events(options \\ [], server \\ LifecycleRecorder) do
    LifecycleRecorder.events(options, server)
  end
end
