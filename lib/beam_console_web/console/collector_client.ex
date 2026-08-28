defmodule BeamConsoleWeb.Console.CollectorClient do
  @moduledoc """
  Provides an outage-safe boundary between the console LiveView and collector.

  Every operation accepts the monitored collector PID explicitly and converts
  expected process exits and bounded call timeouts into typed errors. This keeps
  transient supervisor restart windows and wedged calls out of LiveView
  callbacks.
  """

  alias BeamConsole.Collector
  alias BeamConsole.Collector.Status
  alias BeamConsole.Snapshot

  @default_timeout 250

  @type server :: pid() | nil
  @type call_error :: {:error, :timeout | :unavailable}

  @doc "Subscribes the caller to an available collector process."
  @spec subscribe(server(), timeout()) :: {:ok, Snapshot.t() | nil} | call_error()
  def subscribe(server, timeout \\ @default_timeout) do
    case safe_call(server, &Collector.subscribe(&1, timeout)) do
      {:ok, {:ok, snapshot}} -> {:ok, snapshot}
      {:error, _reason} = error -> error
    end
  end

  @doc "Returns the latest snapshot from an available collector process."
  @spec latest_snapshot(server(), timeout()) :: {:ok, Snapshot.t() | nil} | call_error()
  def latest_snapshot(server, timeout \\ @default_timeout) do
    case safe_call(server, &Collector.latest_snapshot(&1, timeout)) do
      {:ok, snapshot} -> {:ok, snapshot}
      {:error, _reason} = error -> error
    end
  end

  @doc "Returns health information from an available collector process."
  @spec status(server(), timeout()) :: {:ok, Status.t()} | call_error()
  def status(server, timeout \\ @default_timeout) do
    case safe_call(server, &Collector.status(&1, timeout)) do
      {:ok, status} -> {:ok, status}
      {:error, _reason} = error -> error
    end
  end

  @doc "Requests an operator refresh from an available collector process."
  @spec refresh(server(), timeout()) :: :ok | {:error, :rate_limited | :timeout | :unavailable}
  def refresh(server, timeout \\ @default_timeout) do
    case safe_call(server, &Collector.request_refresh(&1, timeout)) do
      {:ok, result} -> result
      {:error, _reason} = error -> error
    end
  end

  @doc "Acknowledges a delivered sequence to an available collector process."
  @spec acknowledge(server(), non_neg_integer(), timeout()) :: :ok | call_error()
  def acknowledge(server, sequence, timeout \\ @default_timeout) do
    case safe_call(server, &Collector.acknowledge(sequence, &1, timeout)) do
      {:ok, :ok} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp safe_call(server, operation) when is_pid(server) and is_function(operation, 1) do
    {:ok, operation.(server)}
  catch
    :exit, {:timeout, _details} -> {:error, :timeout}
    :exit, _reason -> {:error, :unavailable}
  end

  defp safe_call(_server, _operation) do
    {:error, :unavailable}
  end
end
