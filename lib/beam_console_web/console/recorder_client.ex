defmodule BeamConsoleWeb.Console.RecorderClient do
  @moduledoc """
  Provides an outage-safe boundary around the lifecycle recorder.

  Expected process exits during supervisor restart windows become structured
  unavailable and timeout results so connected LiveViews can preserve their
  bounded view.
  """

  alias BeamConsole.Lifecycle.Recorder, as: LifecycleRecorder
  alias BeamConsole.Recorder.Query
  alias BeamConsole.Recorder.Status

  @default_timeout 250

  @type server :: GenServer.server() | nil
  @type call_error :: {:error, :timeout | :unavailable}
  @type query_error :: call_error() | {:error, {:invalid_query_options, term()}}

  @doc "Returns recorder health when the recorder process is available."
  @spec status(server(), timeout()) :: {:ok, Status.t()} | call_error()
  def status(server \\ LifecycleRecorder, timeout \\ @default_timeout) do
    safe_call(server, &LifecycleRecorder.status(&1, timeout))
  end

  @doc "Pauses recording when the recorder process is available."
  @spec pause(server(), timeout()) :: {:ok, Status.t()} | call_error()
  def pause(server \\ LifecycleRecorder, timeout \\ @default_timeout) do
    safe_call(server, &LifecycleRecorder.pause(&1, timeout))
  end

  @doc "Resumes recording when the recorder process is available."
  @spec resume(server(), timeout()) :: {:ok, Status.t()} | call_error()
  def resume(server \\ LifecycleRecorder, timeout \\ @default_timeout) do
    safe_call(server, &LifecycleRecorder.resume(&1, timeout))
  end

  @doc "Returns bounded lifecycle events when the recorder process is available."
  @spec events(keyword(), server(), timeout()) :: {:ok, Query.t()} | query_error()
  def events(options, server \\ LifecycleRecorder, timeout \\ @default_timeout) do
    safe_query(server, &LifecycleRecorder.events(options, &1, timeout))
  end

  @doc "Returns bounded aggregate samples when the recorder process is available."
  @spec samples(keyword(), server(), timeout()) :: {:ok, Query.t()} | query_error()
  def samples(options, server \\ LifecycleRecorder, timeout \\ @default_timeout) do
    safe_query(server, &LifecycleRecorder.samples(options, &1, timeout))
  end

  defp safe_query(server, operation) do
    case safe_call(server, operation) do
      {:ok, %Query{} = query} -> {:ok, query}
      {:ok, {:error, reason}} -> {:error, reason}
      {:error, reason} = error when reason in [:timeout, :unavailable] -> error
    end
  end

  defp safe_call(server, operation) when not is_nil(server) and is_function(operation, 1) do
    {:ok, operation.(server)}
  catch
    :exit, {:timeout, _details} -> {:error, :timeout}
    :exit, _reason -> {:error, :unavailable}
  end

  defp safe_call(_server, _operation) do
    {:error, :unavailable}
  end
end
