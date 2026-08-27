defmodule BeamConsole.Recorder do
  @moduledoc """
  Provides PID-free read access to BeamConsole's bounded process flight recorder.

  The recorder starts automatically according to its configured mode. The
  default `:subscribers` mode records while at least one BeamConsole page is
  connected; `:always` records from application startup.
  """

  alias BeamConsole.Lifecycle.Recorder, as: LifecycleRecorder
  alias BeamConsole.Recorder.Query
  alias BeamConsole.Recorder.Status

  @spec status(GenServer.server()) :: Status.t()
  @doc "Returns recording activity, watch coverage, and bounded-history usage."
  def status(server \\ LifecycleRecorder) do
    LifecycleRecorder.status(server)
  end

  @spec pause(GenServer.server()) :: Status.t()
  @doc "Pauses process recording while preserving bounded in-memory history."
  def pause(server \\ LifecycleRecorder) do
    LifecycleRecorder.pause(server)
  end

  @spec resume(GenServer.server()) :: Status.t()
  @doc "Resumes process recording when the configured demand mode allows it."
  def resume(server \\ LifecycleRecorder) do
    LifecycleRecorder.resume(server)
  end

  @spec events(keyword(), GenServer.server()) :: Query.t()
  @doc "Returns the newest bounded lifecycle events and explicit omission metadata."
  def events(options \\ [], server \\ LifecycleRecorder) do
    LifecycleRecorder.events(options, server)
  end

  @spec samples(keyword(), GenServer.server()) :: Query.t()
  @doc "Returns bounded aggregate samples for Activity and Runtime views."
  def samples(options \\ [], server \\ LifecycleRecorder) do
    LifecycleRecorder.samples(options, server)
  end
end
