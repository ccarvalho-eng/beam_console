defmodule BeamConsole.Recorder.History do
  @moduledoc """
  Implements immutable, bounded storage for compact flight-recorder values.

  History rejects stale sequences, starts a new segment across sequence gaps,
  and enforces age, count, process-series, point, and estimated-byte limits on
  every append. It never stores historical runtime snapshots.
  """

  alias BeamConsole.EntityId
  alias BeamConsole.Lifecycle.Event
  alias BeamConsole.Recorder.Config
  alias BeamConsole.Recorder.Frame
  alias BeamConsole.Recorder.Point

  defstruct config: nil,
            frames: [],
            events: [],
            series: %{},
            last_sequence: nil,
            segment: 0,
            estimated_bytes: 0,
            dropped_events: 0,
            dropped_frames: 0,
            dropped_points: 0,
            dropped_series: 0

  @type series_entry :: %{points: [Point.t()], last_seen_ms: integer()}
  @type t :: %__MODULE__{
          config: Config.t(),
          frames: [Frame.t()],
          events: [Event.t()],
          series: %{String.t() => series_entry()},
          last_sequence: non_neg_integer() | nil,
          segment: non_neg_integer(),
          estimated_bytes: non_neg_integer(),
          dropped_events: non_neg_integer(),
          dropped_frames: non_neg_integer(),
          dropped_points: non_neg_integer(),
          dropped_series: non_neg_integer()
        }
  @type append_result :: {:ok, t()} | {:stale, t()}
  @type size_estimator :: (map() -> non_neg_integer())

  @spec new(Config.t()) :: t()
  @doc """
  Creates empty history under validated recorder configuration.

  ## Examples

      iex> history = BeamConsole.Recorder.History.new()
      iex> BeamConsole.Recorder.History.stats(history).frame_count
      0
  """
  def new(config \\ Config.defaults()) do
    %__MODULE__{config: config}
  end

  @spec append(t(), Frame.t(), [Event.t()], [Point.t()], keyword()) :: append_result()
  @doc """
  Appends one committed frame plus bounded events and scalar series points.

  Duplicate or older frame sequences return `{:stale, history}` without
  mutation. Pass `reset?: true` to start a new correlation segment explicitly.
  Tests may inject `:now_ms` and a deterministic unary `:size_estimator`.
  """
  def append(history, frame, events \\ [], points \\ [], options \\ [])

  def append(
        %__MODULE__{last_sequence: last_sequence} = history,
        %Frame{} = frame,
        events,
        points,
        options
      )
      when is_integer(last_sequence) and frame.sequence <= last_sequence do
    if Keyword.get(options, :reset?, false) do
      append_valid(history, frame, events, points, options)
    else
      {:stale, history}
    end
  end

  def append(%__MODULE__{} = history, %Frame{} = frame, events, points, options)
      when is_list(events) and is_list(points) do
    append_valid(history, frame, events, points, options)
  end

  @spec append_events(t(), [Event.t()], keyword()) :: t()
  @doc "Appends direct lifecycle events to the current segment under every history bound."
  def append_events(history, events, options \\ [])

  def append_events(%__MODULE__{} = history, [], _options) do
    history
  end

  def append_events(%__MODULE__{} = history, events, options) when is_list(events) do
    segment = history.segment
    events = Enum.map(events, &%{&1 | segment: segment})
    now_ms = Keyword.get(options, :now_ms, newest_event_time(events, 0))

    history
    |> Map.update!(:events, &(&1 ++ events))
    |> enforce_limits(now_ms, estimator(options))
  end

  @spec prune(t(), integer(), size_estimator()) :: t()
  @doc "Removes expired values and reapplies all hard limits at the supplied monotonic time."
  def prune(history, now_ms, estimator \\ &default_size_estimator/1) do
    enforce_limits(history, now_ms, estimator)
  end

  @spec stats(t()) :: map()
  @doc "Returns scalar usage and omission counters for recorder health reporting."
  def stats(%__MODULE__{} = history) do
    %{
      frame_count: length(history.frames),
      event_count: length(history.events),
      series_count: map_size(history.series),
      point_count: point_count(history.series),
      estimated_bytes: history.estimated_bytes,
      dropped_events: history.dropped_events,
      dropped_frames: history.dropped_frames,
      dropped_points: history.dropped_points,
      dropped_series: history.dropped_series,
      last_sequence: history.last_sequence,
      segment: history.segment
    }
  end

  defp append_valid(history, frame, events, points, options) do
    reset? = Keyword.get(options, :reset?, false)
    gap? = sequence_gap?(history.last_sequence, frame.sequence)
    new_segment? = reset? or gap?
    segment = if new_segment?, do: history.segment + 1, else: history.segment
    now_ms = Keyword.get(options, :now_ms, frame.monotonic_ms)
    estimator = estimator(options)

    frame = %{frame | segment: segment}
    events = Enum.map(events, &%{&1 | segment: segment})
    points = Enum.map(points, &%{&1 | segment: segment})
    boundary_events = boundary_events(frame, segment, reset?, gap?)

    history = %{
      history
      | frames: history.frames ++ [frame],
        events: history.events ++ boundary_events ++ events,
        series: append_points(history.series, points),
        last_sequence: frame.sequence,
        segment: segment
    }

    {:ok, enforce_limits(history, now_ms, estimator)}
  end

  defp sequence_gap?(nil, _sequence), do: false
  defp sequence_gap?(last_sequence, sequence), do: sequence != last_sequence + 1

  defp newest_event_time([], fallback) do
    fallback
  end

  defp newest_event_time(events, _fallback) do
    events |> List.last() |> Map.fetch!(:monotonic_ms)
  end

  defp boundary_events(_frame, _segment, false, false), do: []

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

  defp append_points(series, points) do
    Enum.reduce(points, series, fn %Point{entity_id: entity_id} = point, result ->
      Map.update(
        result,
        entity_id,
        %{points: [point], last_seen_ms: point.monotonic_ms},
        fn entry ->
          %{
            points: entry.points ++ [point],
            last_seen_ms: max(entry.last_seen_ms, point.monotonic_ms)
          }
        end
      )
    end)
  end

  defp enforce_limits(history, now_ms, estimator) do
    history
    |> evict_expired(now_ms)
    |> cap_frames()
    |> cap_events()
    |> cap_points_per_series()
    |> cap_series()
    |> cap_total_points()
    |> enforce_byte_limit(estimator)
  end

  defp evict_expired(history, now_ms) do
    cutoff = now_ms - history.config.retention_ms
    {frames, expired_frames} = keep_recent(history.frames, cutoff)
    {events, expired_events} = keep_recent(history.events, cutoff)

    {series, expired_points} =
      Enum.reduce(history.series, {%{}, 0}, fn {entity_id, entry}, {kept, dropped} ->
        {points, point_count} = keep_recent(entry.points, cutoff)

        if points == [] do
          {kept, dropped + point_count}
        else
          last_seen_ms = points |> List.last() |> Map.fetch!(:monotonic_ms)

          {Map.put(kept, entity_id, %{points: points, last_seen_ms: last_seen_ms}),
           dropped + point_count}
        end
      end)

    %{
      history
      | frames: frames,
        events: events,
        series: series,
        dropped_frames: history.dropped_frames + expired_frames,
        dropped_events: history.dropped_events + expired_events,
        dropped_points: history.dropped_points + expired_points
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

  defp cap_points_per_series(history) do
    {series, dropped} =
      Enum.reduce(history.series, {%{}, 0}, fn {entity_id, entry}, {result, total_dropped} ->
        {points, point_dropped} = keep_newest(entry.points, history.config.points_per_series)
        last_seen_ms = points |> List.last() |> Map.fetch!(:monotonic_ms)
        next_entry = %{points: points, last_seen_ms: last_seen_ms}
        {Map.put(result, entity_id, next_entry), total_dropped + point_dropped}
      end)

    %{history | series: series, dropped_points: history.dropped_points + dropped}
  end

  defp cap_series(history) when map_size(history.series) <= history.config.series_limit do
    history
  end

  defp cap_series(history) do
    overflow = map_size(history.series) - history.config.series_limit

    removed_ids =
      history.series
      |> Enum.sort_by(fn {entity_id, entry} -> {entry.last_seen_ms, entity_id} end)
      |> Enum.take(overflow)
      |> Enum.map(&elem(&1, 0))

    dropped_points =
      Enum.reduce(removed_ids, 0, fn entity_id, count ->
        count + length(get_in(history.series, [entity_id, :points]))
      end)

    %{
      history
      | series: Map.drop(history.series, removed_ids),
        dropped_series: history.dropped_series + length(removed_ids),
        dropped_points: history.dropped_points + dropped_points
    }
  end

  defp cap_total_points(history) do
    overflow = max(point_count(history.series) - history.config.total_points_limit, 0)

    if overflow == 0 do
      history
    else
      kept_points =
        history.series
        |> Enum.flat_map(fn {_entity_id, entry} -> entry.points end)
        |> Enum.sort_by(&{&1.monotonic_ms, &1.entity_id, &1.sampled_at_ms})
        |> Enum.drop(overflow)

      %{
        history
        | series: rebuild_series(kept_points),
          dropped_points: history.dropped_points + overflow
      }
    end
  end

  defp rebuild_series(points) do
    points
    |> Enum.group_by(& &1.entity_id)
    |> Map.new(fn {entity_id, entity_points} ->
      sorted = Enum.sort_by(entity_points, &{&1.monotonic_ms, &1.sampled_at_ms})
      {entity_id, %{points: sorted, last_seen_ms: List.last(sorted).monotonic_ms}}
    end)
  end

  defp enforce_byte_limit(history, estimator) do
    estimated_bytes = estimate(history, estimator)

    cond do
      estimated_bytes <= history.config.byte_limit ->
        %{history | estimated_bytes: estimated_bytes}

      empty?(history) ->
        %{history | estimated_bytes: estimated_bytes}

      true ->
        history
        |> evict_oldest_item()
        |> enforce_byte_limit(estimator)
    end
  end

  defp evict_oldest_item(history) do
    candidates = oldest_candidates(history)

    case Enum.min_by(candidates, &elem(&1, 0), fn -> nil end) do
      {_key, :frame, _id} ->
        %{history | frames: tl(history.frames), dropped_frames: history.dropped_frames + 1}

      {_key, :event, _id} ->
        %{history | events: tl(history.events), dropped_events: history.dropped_events + 1}

      {_key, :point, entity_id} ->
        drop_oldest_point(history, entity_id)

      nil ->
        history
    end
  end

  defp oldest_candidates(history) do
    frame = List.first(history.frames)
    event = List.first(history.events)

    point =
      history.series
      |> Enum.map(fn {entity_id, entry} -> {List.first(entry.points), entity_id} end)
      |> Enum.min_by(fn {value, entity_id} -> {value.monotonic_ms, entity_id} end, fn -> nil end)

    []
    |> maybe_candidate(frame, :frame, frame && frame.sequence, 0)
    |> maybe_candidate(event, :event, event && event.id, 1)
    |> maybe_point_candidate(point)
  end

  defp maybe_candidate(candidates, nil, _kind, _id, _rank), do: candidates

  defp maybe_candidate(candidates, value, kind, id, rank) do
    [{{value.monotonic_ms, rank, id}, kind, id} | candidates]
  end

  defp maybe_point_candidate(candidates, nil), do: candidates

  defp maybe_point_candidate(candidates, {point, entity_id}) do
    [{{point.monotonic_ms, 2, entity_id}, :point, entity_id} | candidates]
  end

  defp drop_oldest_point(history, entity_id) do
    entry = Map.fetch!(history.series, entity_id)

    case tl(entry.points) do
      [] ->
        %{
          history
          | series: Map.delete(history.series, entity_id),
            dropped_points: history.dropped_points + 1
        }

      points ->
        next_entry = %{points: points, last_seen_ms: List.last(points).monotonic_ms}

        %{
          history
          | series: Map.put(history.series, entity_id, next_entry),
            dropped_points: history.dropped_points + 1
        }
    end
  end

  defp empty?(history) do
    history.frames == [] and history.events == [] and map_size(history.series) == 0
  end

  defp estimate(history, estimator) do
    value =
      estimator.(%{
        frames: history.frames,
        events: history.events,
        series: history.series
      })

    if is_integer(value) and value >= 0, do: value, else: 0
  end

  defp estimator(options) do
    case Keyword.get(options, :size_estimator) do
      function when is_function(function, 1) -> function
      _other -> &default_size_estimator/1
    end
  end

  defp default_size_estimator(value) do
    :erlang.external_size(value) * 2
  end

  defp point_count(series) do
    Enum.reduce(series, 0, fn {_entity_id, entry}, count -> count + length(entry.points) end)
  end
end
