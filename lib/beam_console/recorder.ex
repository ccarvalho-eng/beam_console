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

  @doc "Returns recording activity, watch coverage, and bounded-history usage."
  @spec status(GenServer.server()) :: Status.t()
  def status(server \\ LifecycleRecorder) do
    LifecycleRecorder.status(server)
  end

  @doc "Pauses process recording through its configured authority while preserving history."
  @spec pause(GenServer.server()) :: Status.t()
  def pause(server \\ LifecycleRecorder) do
    LifecycleRecorder.pause(server)
  end

  @doc "Resumes process recording through its configured authority when demand allows it."
  @spec resume(GenServer.server()) :: Status.t()
  def resume(server \\ LifecycleRecorder) do
    LifecycleRecorder.resume(server)
  end

  @doc "Returns the newest bounded lifecycle events and explicit omission metadata."
  @spec events(keyword(), GenServer.server()) :: Query.t() | LifecycleRecorder.query_error()
  def events(options \\ [], server \\ LifecycleRecorder) do
    LifecycleRecorder.events(options, server)
  end

  @doc "Returns bounded aggregate samples for Activity and Runtime views."
  @spec samples(keyword(), GenServer.server()) :: Query.t() | LifecycleRecorder.query_error()
  def samples(options \\ [], server \\ LifecycleRecorder) do
    LifecycleRecorder.samples(options, server)
  end
end
