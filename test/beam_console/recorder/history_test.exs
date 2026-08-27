defmodule BeamConsole.Recorder.HistoryTest do
  use ExUnit.Case, async: true

  alias BeamConsole.Lifecycle.Event
  alias BeamConsole.Recorder.Config
  alias BeamConsole.Recorder.Frame
  alias BeamConsole.Recorder.History
  alias BeamConsole.Recorder.Point
  alias BeamConsole.Recorder.Query

  test "enforces frame and event caps at cap plus one" do
    history = history(frame_limit: 3, event_limit: 3, timeline_limit: 3)

    history =
      Enum.reduce(1..4, history, fn sequence, current ->
        {:ok, current} =
          History.append(current, frame(sequence), [event(sequence)], [], now_ms: sequence)

        current
      end)

    assert Enum.map(history.frames, & &1.sequence) == [2, 3, 4]
    assert Enum.map(history.events, & &1.sequence) == [2, 3, 4]
    assert history.dropped_frames == 1
    assert history.dropped_events == 1
  end

  test "rejects duplicate and out-of-order sequences without mutation" do
    history = history()
    {:ok, history} = History.append(history, frame(3), [], [], now_ms: 3)

    assert {:stale, ^history} = History.append(history, frame(3))
    assert {:stale, ^history} = History.append(history, frame(2))
  end

  test "starts new segments for sequence gaps and explicit resets" do
    history = history()
    {:ok, history} = History.append(history, frame(1), [], [], now_ms: 1)
    {:ok, history} = History.append(history, frame(3), [], [], now_ms: 3)

    assert history.segment == 1
    assert [%Event{kind: :gap, segment: 1}] = history.events
    assert Enum.map(history.frames, & &1.segment) == [0, 1]

    {:ok, history} = History.append(history, frame(4), [], [], reset?: true, now_ms: 4)
    assert history.segment == 2
    assert Enum.map(history.events, & &1.kind) == [:gap, :reset]
  end

  test "explicit resets accept a restarted sequence and direct events stay bounded" do
    history = history(event_limit: 2, timeline_limit: 2)
    {:ok, history} = History.append(history, frame(5), [], [], now_ms: 5)
    {:ok, history} = History.append(history, frame(1, 6), [], [], reset?: true, now_ms: 6)

    history = History.append_events(history, [event(1, 7), event(1, 8)], now_ms: 8)

    assert history.last_sequence == 1
    assert history.segment == 1
    assert Enum.map(history.events, & &1.monotonic_ms) == [7, 8]
    assert history.dropped_events == 1
    assert History.append_events(history, []) == history
  end

  test "evicts values only after the retention boundary" do
    history = history(retention_ms: 100)
    {:ok, history} = History.append(history, frame(1, 0), [event(1, 0)], [], now_ms: 0)

    retained = History.prune(history, 100, fn _payload -> 0 end)
    assert History.stats(retained).frame_count == 1
    assert History.stats(retained).event_count == 1

    expired = History.prune(retained, 101, fn _payload -> 0 end)
    assert History.stats(expired).frame_count == 0
    assert History.stats(expired).event_count == 0
  end

  test "applies deterministic series LRU, per-series, and total-point caps" do
    history =
      history(
        series_limit: 2,
        points_per_series: 2,
        total_points_limit: 3,
        chart_points_limit: 2
      )

    points = [point("a", 1), point("b", 1), point("c", 1)]
    {:ok, history} = History.append(history, frame(1), [], points, now_ms: 1)

    refute Map.has_key?(history.series, "a")
    assert Map.keys(history.series) |> Enum.sort() == ["b", "c"]

    more_points = [point("b", 2), point("b", 3), point("c", 2)]
    {:ok, history} = History.append(history, frame(2), [], more_points, now_ms: 3)

    assert History.stats(history).series_count == 2
    assert History.stats(history).point_count == 3
    assert Enum.map(history.series["b"].points, & &1.value) == [2, 3]
    assert Enum.map(history.series["c"].points, & &1.value) == [2]
    assert history.dropped_series == 1
    assert history.dropped_points == 3
  end

  test "evicts oldest values until the injected byte estimate is within its cap" do
    history = history(byte_limit: 25)
    estimator = &logical_size/1

    {:ok, history} =
      History.append(history, frame(1), [event(1), event(1, 2)], [],
        now_ms: 2,
        size_estimator: estimator
      )

    assert history.estimated_bytes <= 25
    assert History.stats(history).frame_count == 0
    assert History.stats(history).event_count == 2
  end

  test "byte pressure can evict events and both single and repeated series points" do
    estimator = &logical_size/1

    event_history = history(byte_limit: 10)

    {:ok, event_history} =
      History.append(event_history, frame(1, 2), [event(1, 1)], [],
        now_ms: 2,
        size_estimator: estimator
      )

    assert History.stats(event_history).event_count == 0
    assert History.stats(event_history).frame_count == 1

    point_history = history(byte_limit: 20)

    {:ok, point_history} =
      History.append(
        point_history,
        frame(1, 3),
        [],
        [point("worker", 1), point("worker", 2)],
        now_ms: 3,
        size_estimator: estimator
      )

    assert Enum.map(point_history.series["worker"].points, & &1.value) == [2]
    assert point_history.dropped_points == 1

    single_point_history = history(byte_limit: 10)

    {:ok, single_point_history} =
      History.append(single_point_history, frame(1, 2), [], [point("worker", 1)],
        now_ms: 2,
        size_estimator: estimator
      )

    assert single_point_history.series == %{}
    assert single_point_history.dropped_points == 1
  end

  test "terminates byte eviction when an estimator reports overhead for empty history" do
    history = history(byte_limit: 1)

    {:ok, history} =
      History.append(history, frame(1), [], [],
        now_ms: 1,
        size_estimator: fn _payload -> 10 end
      )

    assert History.stats(history).frame_count == 0
    assert history.estimated_bytes == 10
  end

  test "all logical caps hold after ten times capacity" do
    history =
      history(
        event_limit: 5,
        frame_limit: 5,
        timeline_limit: 5,
        series_limit: 2,
        points_per_series: 3,
        total_points_limit: 5,
        chart_points_limit: 3
      )

    history =
      Enum.reduce(1..50, history, fn sequence, current ->
        points = [point("entity-#{rem(sequence, 4)}", sequence)]

        {:ok, current} =
          History.append(current, frame(sequence), [event(sequence)], points,
            now_ms: sequence,
            size_estimator: fn _payload -> 0 end
          )

        current
      end)

    stats = History.stats(history)
    assert stats.frame_count <= 5
    assert stats.event_count <= 5
    assert stats.series_count <= 2
    assert stats.point_count <= 5
  end

  test "event queries expose newest results, omissions, drops, and available range" do
    history = history(event_limit: 4, timeline_limit: 3)

    history =
      Enum.reduce(1..5, history, fn sequence, current ->
        {:ok, current} =
          History.append(current, frame(sequence), [event(sequence)], [], now_ms: sequence)

        current
      end)

    {history, result} = Query.events(history, limit: 2, now_ms: 5)

    assert Enum.map(result.items, & &1.sequence) == [5, 4]
    assert result.omitted == 2
    assert result.dropped == 1
    assert result.available_from_ms == 2
    assert result.available_to_ms == 5
    assert History.stats(history).event_count == 4
  end

  test "queries filter events and return bounded or empty process series" do
    history = history(chart_points_limit: 2)

    events = [
      event(1, 1),
      %{event(1, 2) | kind: :observed_stop}
    ]

    points = [point("worker", 1), point("worker", 2), point("worker", 3)]
    {:ok, history} = History.append(history, frame(1, 3), events, points, now_ms: 3)

    {_history, filtered} =
      Query.events(history,
        kinds: [:observed_stop],
        since_ms: 2,
        limit: 0,
        now_ms: 3,
        size_estimator: fn _payload -> 0 end
      )

    assert Enum.map(filtered.items, & &1.kind) == [:observed_stop]

    {_history, series} = Query.series(history, "worker", now_ms: 3)
    assert Enum.map(series.items, & &1.value) == [3, 2]
    assert series.omitted == 1

    {_history, empty} = Query.series(history, "missing", now_ms: 3)
    assert empty.items == []
    assert empty.available_from_ms == nil
    assert empty.available_to_ms == nil
  end

  test "default query entry points return empty bounded results" do
    empty_history = history()

    {_history, events} = Query.events(empty_history)
    {_history, series} = Query.series(empty_history, "missing")

    assert events.items == []
    assert series.items == []
  end

  defp history(overrides \\ []) do
    defaults = [
      retention_ms: 10_000,
      event_limit: 10,
      frame_limit: 10,
      timeline_limit: 10,
      series_limit: 4,
      points_per_series: 10,
      total_points_limit: 40,
      chart_points_limit: 10,
      byte_limit: 1_000_000
    ]

    defaults
    |> Keyword.merge(overrides)
    |> Config.new!()
    |> History.new()
  end

  defp frame(sequence, monotonic_ms \\ nil) do
    monotonic_ms = monotonic_ms || sequence

    %Frame{
      sequence: sequence,
      sampled_at_ms: monotonic_ms,
      monotonic_ms: monotonic_ms
    }
  end

  defp event(sequence, monotonic_ms \\ nil) do
    monotonic_ms = monotonic_ms || sequence

    %Event{
      id: "event-#{sequence}-#{monotonic_ms}",
      kind: :observed_start,
      sequence: sequence,
      segment: 0,
      observed_at_ms: monotonic_ms,
      monotonic_ms: monotonic_ms,
      evidence: :snapshot_diff,
      certainty: :sampled
    }
  end

  defp point(entity_id, monotonic_ms) do
    %Point{
      entity_id: entity_id,
      sampled_at_ms: monotonic_ms,
      monotonic_ms: monotonic_ms,
      value: monotonic_ms
    }
  end

  defp logical_size(payload) do
    point_count =
      Enum.reduce(payload.series, 0, fn {_entity_id, entry}, count ->
        count + length(entry.points)
      end)

    (length(payload.frames) + length(payload.events) + point_count) * 10
  end
end
