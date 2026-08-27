defmodule BeamConsoleWeb.Console.CollectorClient do
  @moduledoc """
  Provides an outage-safe boundary between the console LiveView and collector.

  Every operation accepts the monitored collector PID explicitly and converts
  expected process exits into `{:error, :unavailable}`. This keeps transient
  supervisor restart windows out of LiveView callbacks.
  """

  alias BeamConsole.Collector.Status
  alias BeamConsole.Snapshot

  @type server :: pid() | nil
  @type unavailable :: {:error, :unavailable}

  @doc "Subscribes the caller to an available collector process."
  @spec subscribe(server()) :: {:ok, Snapshot.t() | nil} | unavailable()
  def subscribe(server) do
    case safe_call(server, &BeamConsole.subscribe/1) do
      {:ok, {:ok, snapshot}} -> {:ok, snapshot}
      {:error, :unavailable} = error -> error
    end
  end

  @doc "Returns the latest snapshot from an available collector process."
  @spec latest_snapshot(server()) :: {:ok, Snapshot.t() | nil} | unavailable()
  def latest_snapshot(server) do
    case safe_call(server, &BeamConsole.latest_snapshot/1) do
      {:ok, snapshot} -> {:ok, snapshot}
      {:error, :unavailable} = error -> error
    end
  end

  @doc "Returns health information from an available collector process."
  @spec status(server()) :: {:ok, Status.t()} | unavailable()
  def status(server) do
    case safe_call(server, &BeamConsole.status/1) do
      {:ok, status} -> {:ok, status}
      {:error, :unavailable} = error -> error
    end
  end

  @doc "Requests an operator refresh from an available collector process."
  @spec refresh(server()) :: :ok | {:error, :rate_limited | :unavailable}
  def refresh(server) do
    case safe_call(server, &BeamConsole.refresh/1) do
      {:ok, result} -> result
      {:error, :unavailable} = error -> error
    end
  end

  @doc "Acknowledges a delivered sequence to an available collector process."
  @spec acknowledge(server(), non_neg_integer()) :: :ok | unavailable()
  def acknowledge(server, sequence) do
    case safe_call(server, &BeamConsole.acknowledge(sequence, &1)) do
      {:ok, :ok} -> :ok
      {:error, :unavailable} = error -> error
    end
  end

  defp safe_call(server, operation) when is_pid(server) and is_function(operation, 1) do
    {:ok, operation.(server)}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp safe_call(_server, _operation) do
    {:error, :unavailable}
  end
end
