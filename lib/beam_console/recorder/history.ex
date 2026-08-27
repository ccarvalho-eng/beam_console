defmodule BeamConsole.Recorder.History do
  @moduledoc """
  Implements immutable, bounded storage for compact flight-recorder values.

  History rejects stale sequences, starts a new segment across sequence gaps,
  and enforces age, count, and estimated-byte limits on every append. It never
  stores historical runtime snapshots.
  """

  alias BeamConsole.EntityId
  alias BeamConsole.Lifecycle.Event
  alias BeamConsole.Recorder.Config
  alias BeamConsole.Recorder.Frame

  @base_estimated_bytes 64

  defstruct config: nil,
            frames: [],
            events: [],
            last_sequence: nil,
            segment: 0,
            estimated_bytes: 0,
            dropped_events: 0,
            dropped_frames: 0

  @type t :: %__MODULE__{
          config: Config.t(),
          frames: [Frame.t()],
          events: [Event.t()],
          last_sequence: non_neg_integer() | nil,
          segment: non_neg_integer(),
          estimated_bytes: non_neg_integer(),
          dropped_events: non_neg_integer(),
          dropped_frames: non_neg_integer()
        }
  @type append_result :: {:ok, t()} | {:stale, t()}
  @type size_estimator :: (map() -> non_neg_integer())

  @doc """
  Creates empty history under validated recorder configuration.

  ## Examples

      iex> history = BeamConsole.Recorder.History.new()
      iex> BeamConsole.Recorder.History.stats(history).frame_count
      0
  """
  @spec new(Config.t()) :: t()
  def new(config \\ Config.defaults()) do
    %__MODULE__{config: config}
  end

  @doc """
  Appends one committed frame plus bounded lifecycle events.

  Duplicate or older frame sequences return `{:stale, history}` without
  mutation. Pass `reset?: true` to start a new correlation segment explicitly.
  Tests may inject `:now_ms` and a deterministic unary `:size_estimator`.
  """
  @spec append(t(), Frame.t(), [Event.t()], keyword()) :: append_result()
  def append(history, frame, events \\ [], options \\ [])

  def append(
        %__MODULE__{last_sequence: last_sequence} = history,
        %Frame{} = frame,
        events,
        options
      )
      when is_integer(last_sequence) and frame.sequence <= last_sequence do
    if Keyword.get(options, :reset?, false) do
      append_valid(history, frame, events, options)
    else
      {:stale, history}
    end
  end

  def append(%__MODULE__{} = history, %Frame{} = frame, events, options)
      when is_list(events) do
    append_valid(history, frame, events, options)
  end

  @doc "Appends direct lifecycle events to the current segment under every history bound."
  @spec append_events(t(), [Event.t()], keyword()) :: t()
  def append_events(history, events, options \\ [])

  def append_events(%__MODULE__{} = history, [], _options) do
    history
  end

  def append_events(%__MODULE__{} = history, events, options) when is_list(events) do
    segment = history.segment
    events = Enum.map(events, &%{&1 | segment: segment})
    now_ms = Keyword.get(options, :now_ms, newest_event_time(events, 0))

    history
    |> Map.update!(:events, &sort_events(&1 ++ events))
    |> enforce_limits(now_ms, estimator(options))
  end

  @doc "Removes expired values and reapplies all hard limits at the supplied monotonic time."
  @spec prune(t(), integer(), size_estimator() | :default) :: t()
  def prune(history, now_ms, estimator \\ :default) do
    enforce_limits(history, now_ms, estimator)
  end

  @doc "Returns scalar usage and omission counters for recorder health reporting."
  @spec stats(t()) :: map()
  def stats(%__MODULE__{} = history) do
    %{
      frame_count: length(history.frames),
      event_count: length(history.events),
      estimated_bytes: history.estimated_bytes,
      dropped_events: history.dropped_events,
      dropped_frames: history.dropped_frames,
      last_sequence: history.last_sequence,
      segment: history.segment
    }
  end

  defp append_valid(history, frame, events, options) do
    reset? = Keyword.get(options, :reset?, false)
    gap? = sequence_gap?(history.last_sequence, frame.sequence)
    new_segment? = reset? or gap?
    segment = if new_segment?, do: history.segment + 1, else: history.segment
    now_ms = Keyword.get(options, :now_ms, frame.monotonic_ms)
    estimator = estimator(options)

    frame = %{frame | segment: segment}
    events = Enum.map(events, &%{&1 | segment: segment})
    boundary_events = boundary_events(frame, segment, reset?, gap?)

    history = %{
      history
      | frames: history.frames ++ [frame],
        events: sort_events(history.events ++ boundary_events ++ events),
        last_sequence: frame.sequence,
        segment: segment
    }

    {:ok, enforce_limits(history, now_ms, estimator)}
  end

  defp sequence_gap?(nil, _sequence) do
    false
  end

  defp sequence_gap?(last_sequence, sequence) do
    sequence != last_sequence + 1
  end

  defp newest_event_time([], fallback) do
    fallback
  end

  defp newest_event_time(events, _fallback) do
    events
    |> Enum.max_by(& &1.monotonic_ms)
    |> Map.fetch!(:monotonic_ms)
  end

  defp boundary_events(_frame, _segment, false, false) do
    []
  end

  defp boundary_events(frame, segment, reset?, _gap?) do
    kind = if reset?, do: :reset, else: :gap

    [
      %Event{
        id: EntityId.build(:event, {kind, segment, frame.sequence}),
        kind: kind,
        sequence: frame.sequence,
        segment: segment,
        observed_at_ms: frame.sampled_at_ms,
        monotonic_ms: frame.monotonic_ms,
        label: if(reset?, do: "Recording reset", else: "Recording gap"),
        evidence: :recorder,
        certainty: :direct
      }
    ]
  end

  defp enforce_limits(history, now_ms, estimator) do
    history
    |> evict_expired(now_ms)
    |> cap_frames()
    |> cap_events()
    |> enforce_byte_limit(estimator)
  end

  defp evict_expired(history, now_ms) do
    cutoff = now_ms - history.config.retention_ms
    {frames, expired_frames} = keep_recent(history.frames, cutoff)
    {events, expired_events} = keep_recent(history.events, cutoff)

    %{
      history
      | frames: frames,
        events: events,
        dropped_frames: history.dropped_frames + expired_frames,
        dropped_events: history.dropped_events + expired_events
    }
  end

  defp keep_recent(values, cutoff) do
    kept = Enum.drop_while(values, &(&1.monotonic_ms < cutoff))
    {kept, length(values) - length(kept)}
  end

  defp cap_frames(history) do
    {frames, dropped} = keep_newest(history.frames, history.config.frame_limit)
    %{history | frames: frames, dropped_frames: history.dropped_frames + dropped}
  end

  defp cap_events(history) do
    {events, dropped} = keep_newest(history.events, history.config.event_limit)
    %{history | events: events, dropped_events: history.dropped_events + dropped}
  end

  defp keep_newest(values, limit) do
    dropped = max(length(values) - limit, 0)
    {Enum.drop(values, dropped), dropped}
  end

  defp enforce_byte_limit(history, :default) do
    history
    |> default_estimate()
    |> then(&evict_default_bytes(history, &1))
  end

  defp enforce_byte_limit(history, estimator) when is_function(estimator, 1) do
    estimated_bytes = custom_estimate(history, estimator)

    cond do
      estimated_bytes <= history.config.byte_limit ->
        %{history | estimated_bytes: estimated_bytes}

      empty?(history) ->
        %{history | estimated_bytes: estimated_bytes}

      true ->
        eviction_count = minimal_eviction_count(history, estimator)
        reduced = evict_oldest_items(history, eviction_count)
        %{reduced | estimated_bytes: custom_estimate(reduced, estimator)}
    end
  end

  defp evict_default_bytes(history, estimated_bytes) do
    cond do
      estimated_bytes <= history.config.byte_limit ->
        %{history | estimated_bytes: estimated_bytes}

      empty?(history) ->
        %{history | estimated_bytes: estimated_bytes}

      true ->
        candidate = oldest_candidate(history)
        reclaimed = default_candidate_size(history, candidate)
        reduced = evict_candidate(history, candidate)
        next_estimate = max(estimated_bytes - reclaimed, @base_estimated_bytes)
        evict_default_bytes(reduced, next_estimate)
    end
  end

  defp minimal_eviction_count(history, estimator) do
    find_eviction_count(history, estimator, 1, total_item_count(history))
  end

  defp find_eviction_count(_history, _estimator, lower, upper) when lower >= upper do
    lower
  end

  defp find_eviction_count(history, estimator, lower, upper) do
    midpoint = div(lower + upper, 2)
    candidate = evict_oldest_items(history, midpoint)

    if custom_estimate(candidate, estimator) <= history.config.byte_limit do
      find_eviction_count(history, estimator, lower, midpoint)
    else
      find_eviction_count(history, estimator, midpoint + 1, upper)
    end
  end

  defp evict_oldest_items(history, 0) do
    history
  end

  defp evict_oldest_items(history, remaining) do
    if empty?(history) do
      history
    else
      history |> evict_oldest_item() |> evict_oldest_items(remaining - 1)
    end
  end

  defp evict_oldest_item(history) do
    evict_candidate(history, oldest_candidate(history))
  end

  defp evict_candidate(history, candidate) do
    case candidate do
      {_key, :frame, _id} ->
        %{history | frames: tl(history.frames), dropped_frames: history.dropped_frames + 1}

      {_key, :event, _id} ->
        %{history | events: tl(history.events), dropped_events: history.dropped_events + 1}

      nil ->
        history
    end
  end

  defp oldest_candidate(history) do
    history
    |> oldest_candidates()
    |> Enum.min_by(&elem(&1, 0), fn -> nil end)
  end

  defp oldest_candidates(history) do
    frame = List.first(history.frames)
    event = List.first(history.events)

    []
    |> maybe_candidate(frame, :frame, frame && frame.sequence, 0)
    |> maybe_candidate(event, :event, event && event.id, 1)
  end

  defp maybe_candidate(candidates, nil, _kind, _id, _rank) do
    candidates
  end

  defp maybe_candidate(candidates, value, kind, id, rank) do
    [{{value.monotonic_ms, rank, id}, kind, id} | candidates]
  end

  defp empty?(history) do
    history.frames == [] and history.events == []
  end

  defp total_item_count(history) do
    length(history.frames) + length(history.events)
  end

  defp custom_estimate(history, estimator) do
    value =
      estimator.(%{
        frames: history.frames,
        events: history.events
      })

    if is_integer(value) and value >= 0, do: value, else: 0
  end

  defp estimator(options) do
    case Keyword.get(options, :size_estimator) do
      function when is_function(function, 1) -> function
      _other -> :default
    end
  end

  defp default_estimate(history) do
    frame_bytes = Enum.reduce(history.frames, 0, &(&2 + default_item_size(&1)))
    event_bytes = Enum.reduce(history.events, 0, &(&2 + default_item_size(&1)))

    @base_estimated_bytes + frame_bytes + event_bytes
  end

  defp default_candidate_size(history, {_key, :frame, _id}) do
    history.frames |> List.first() |> default_item_size()
  end

  defp default_candidate_size(history, {_key, :event, _id}) do
    history.events |> List.first() |> default_item_size()
  end

  defp default_item_size(value) do
    :erlang.external_size(value) * 2 + 16
  end

  defp sort_events(events) do
    Enum.sort_by(events, &{&1.monotonic_ms, &1.observed_at_ms, &1.sequence, &1.id})
  end
end
