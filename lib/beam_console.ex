defmodule BeamConsole do
  @moduledoc """
  Read-only access to sampled BEAM runtime topology.

  The public API returns bounded normalized data. It never accepts PID strings,
  atom names, or encoded Erlang terms from clients.
  """

  alias BeamConsole.Collector
  alias BeamConsole.Collector.Status
  alias BeamConsole.Runtime.Local
  alias BeamConsole.Snapshot

  @doc """
  Subscribes the calling process to sampled snapshot notifications.

  The return value contains the latest snapshot when one has already completed.
  Subscribers receive `{:beam_console_snapshot, sequence}` version-invalidating
  messages and are removed automatically when they terminate. A subscriber must
  acknowledge each delivered sequence after reading the latest bounded state.
  """
  @spec subscribe(GenServer.server()) :: {:ok, Snapshot.t() | nil}
  def subscribe(server \\ Collector) do
    Collector.subscribe(server)
  end

  @doc "Stops snapshot notifications for the calling process."
  @spec unsubscribe(GenServer.server()) :: :ok
  def unsubscribe(server \\ Collector) do
    Collector.unsubscribe(server)
  end

  @doc "Acknowledges the caller's outstanding snapshot notification."
  @spec acknowledge(non_neg_integer(), GenServer.server()) :: :ok
  def acknowledge(sequence, server \\ Collector) do
    Collector.acknowledge(sequence, server)
  end

  @doc """
  Requests a new bounded runtime scan.

  Concurrent requests are coalesced so the collector never overlaps scans.
  Rapid operator requests return `{:error, :rate_limited}`.
  """
  @spec refresh(GenServer.server()) :: :ok | {:error, :rate_limited}
  def refresh(server \\ Collector) do
    Collector.request_refresh(server)
  end

  @doc "Returns bounded collector health and snapshot freshness information."
  @spec status(GenServer.server()) :: Status.t()
  def status(server \\ Collector) do
    Collector.status(server)
  end

  @doc "Returns the latest completed snapshot, or `nil` before the first scan."
  @spec latest_snapshot(GenServer.server()) :: Snapshot.t() | nil
  def latest_snapshot(server \\ Collector) do
    Collector.latest_snapshot(server)
  end

  @doc "Returns the directly following bounded diff or a full snapshot resync instruction."
  @spec changes_since(non_neg_integer(), GenServer.server()) :: Collector.changes_result()
  def changes_since(sequence, server \\ Collector) do
    Collector.changes_since(sequence, server)
  end

  @doc """
  Searches process labels and safe metadata in a snapshot.

  Matching is case-insensitive and the result count is bounded by `limit`. A
  missing snapshot returns an empty list.
  """
  @spec search(Snapshot.t() | nil, String.t(), non_neg_integer()) :: [BeamConsole.ProcessInfo.t()]
  def search(snapshot, query, limit \\ 100)

  def search(nil, _query, _limit) do
    []
  end

  def search(%Snapshot{} = snapshot, query, limit) do
    normalized_query = query |> String.trim() |> String.downcase()

    snapshot.processes
    |> Map.values()
    |> Enum.filter(&matches?(&1, normalized_query))
    |> Enum.sort_by(&{&1.application || :zz_unattributed, &1.label, &1.pid_text})
    |> Enum.take(limit)
  end

  @doc """
  Loads allowlisted details for an opaque process entity ID.

  Unknown IDs return `{:error, :unknown}`. A process that has exited or is not
  local to the inspected snapshot returns `{:error, :unavailable}`.
  """
  @spec detail(Snapshot.t() | nil, String.t()) ::
          {:ok, BeamConsole.ProcessDetail.t()} | {:error, :unknown | :unavailable}
  def detail(nil, _entity_id) do
    {:error, :unknown}
  end

  def detail(%Snapshot{} = snapshot, entity_id) when is_binary(entity_id) do
    case Map.get(snapshot.index, entity_id) do
      {:process, pid} -> Local.detail(pid, snapshot)
      _other -> {:error, :unknown}
    end
  end

  def detail(%Snapshot{}, _entity_id) do
    {:error, :unknown}
  end

  defp matches?(_process, "") do
    true
  end

  defp matches?(process, query) do
    [
      process.label,
      process.pid_text,
      process.module,
      process.registered_name,
      process.application
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.any?(fn value ->
      value
      |> to_string()
      |> String.downcase()
      |> String.contains?(query)
    end)
  end
end
