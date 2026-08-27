defmodule BeamConsoleWeb.Console.RecorderClient do
  @moduledoc """
  Provides an outage-safe boundary around the lifecycle recorder.

  Expected process exits during supervisor restart windows become structured
  unavailable results so connected LiveViews can preserve their bounded view.
  """

  alias BeamConsole.Lifecycle.Recorder, as: LifecycleRecorder
  alias BeamConsole.Recorder
  alias BeamConsole.Recorder.Query
  alias BeamConsole.Recorder.Status

  @type server :: GenServer.server() | nil
  @type unavailable :: {:error, :unavailable}
  @type query_error :: unavailable() | {:error, {:invalid_query_options, term()}}

  @doc "Returns recorder health when the recorder process is available."
  @spec status(server()) :: {:ok, Status.t()} | unavailable()
  def status(server \\ LifecycleRecorder) do
    safe_call(server, &Recorder.status/1)
  end

  @doc "Pauses recording when the recorder process is available."
  @spec pause(server()) :: {:ok, Status.t()} | unavailable()
  def pause(server \\ LifecycleRecorder) do
    safe_call(server, &Recorder.pause/1)
  end

  @doc "Resumes recording when the recorder process is available."
  @spec resume(server()) :: {:ok, Status.t()} | unavailable()
  def resume(server \\ LifecycleRecorder) do
    safe_call(server, &Recorder.resume/1)
  end

  @doc "Returns bounded lifecycle events when the recorder process is available."
  @spec events(keyword(), server()) :: {:ok, Query.t()} | query_error()
  def events(options, server \\ LifecycleRecorder) do
    safe_query(server, &Recorder.events(options, &1))
  end

  @doc "Returns bounded aggregate samples when the recorder process is available."
  @spec samples(keyword(), server()) :: {:ok, Query.t()} | query_error()
  def samples(options, server \\ LifecycleRecorder) do
    safe_query(server, &Recorder.samples(options, &1))
  end

  defp safe_query(server, operation) do
    case safe_call(server, operation) do
      {:ok, %Query{} = query} -> {:ok, query}
      {:ok, {:error, reason}} -> {:error, reason}
      {:error, :unavailable} = error -> error
    end
  end

  defp safe_call(server, operation) when not is_nil(server) and is_function(operation, 1) do
    {:ok, operation.(server)}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp safe_call(_server, _operation) do
    {:error, :unavailable}
  end
end
