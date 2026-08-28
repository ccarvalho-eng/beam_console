defmodule BeamConsoleWeb.Console.RecordingControlClient do
  @moduledoc "Provides an outage-safe boundary around operator recording control."

  alias BeamConsole.Recording
  alias BeamConsole.Recording.Control
  alias BeamConsole.Recording.Status

  @default_timeout 250

  @type server :: GenServer.server() | nil
  @type call_error :: {:error, :timeout | :unavailable}

  @doc "Returns authoritative recording control state when available."
  @spec status(server(), timeout()) :: {:ok, Status.t()} | call_error()
  def status(server \\ Control, timeout \\ @default_timeout) do
    safe_call(server, &Recording.status(&1, timeout))
  end

  @doc "Subscribes the caller to authoritative recording-state transitions."
  @spec subscribe(server(), timeout()) :: {:ok, Status.t()} | call_error()
  def subscribe(server \\ Control, timeout \\ @default_timeout) do
    safe_call(server, &Control.subscribe(&1, timeout))
  end

  @doc "Pauses recording through the authoritative control process."
  @spec pause(server(), timeout()) :: {:ok, Status.t()} | call_error()
  def pause(server \\ Control, timeout \\ @default_timeout) do
    safe_call(server, &Recording.pause(&1, timeout))
  end

  @doc "Resumes recording through the authoritative control process."
  @spec resume(server(), timeout()) :: {:ok, Status.t()} | call_error()
  def resume(server \\ Control, timeout \\ @default_timeout) do
    safe_call(server, &Recording.resume(&1, timeout))
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
