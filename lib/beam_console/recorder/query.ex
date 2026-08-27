defmodule BeamConsole.Recorder.Query do
  @moduledoc """
  Returns bounded recorder history views with explicit omission and range metadata.

  Querying first prunes expired history at an injected or current monotonic
  timestamp, so stale values cannot survive merely because sampling paused.
  """

  alias BeamConsole.Lifecycle.Event
  alias BeamConsole.Recorder.Frame
  alias BeamConsole.Recorder.History
  alias BeamConsole.Recorder.Point

  defstruct items: [],
            omitted: 0,
            dropped: 0,
            available_from_ms: nil,
            available_to_ms: nil,
            segment: 0

  @type item :: Event.t() | Frame.t() | Point.t()
  @type t :: %__MODULE__{
          items: [item()],
          omitted: non_neg_integer(),
          dropped: non_neg_integer(),
          available_from_ms: integer() | nil,
          available_to_ms: integer() | nil,
          segment: non_neg_integer()
        }

  @spec events(History.t(), keyword()) :: {History.t(), t()}
  @doc "Returns newest lifecycle events under the configured timeline cap."
  def events(history, options \\ []) do
    history = prune(history, options)
    kinds = Keyword.get(options, :kinds)
    since_ms = Keyword.get(options, :since_ms)

    filtered =
      Enum.filter(history.events, fn event ->
        (is_nil(kinds) or event.kind in kinds) and
          (is_nil(since_ms) or event.observed_at_ms >= since_ms)
      end)

    {history,
     build_result(
       filtered,
       requested_limit(options, history.config.timeline_limit),
       history.dropped_events,
       history.segment
     )}
  end

  @spec series(History.t(), String.t(), keyword()) :: {History.t(), t()}
  @doc "Returns ordered scalar points for one opaque process entity ID."
  def series(history, entity_id, options \\ []) when is_binary(entity_id) do
    history = prune(history, options)
    points = history.series |> Map.get(entity_id, %{points: []}) |> Map.fetch!(:points)
    limit = requested_limit(options, history.config.chart_points_limit)

    {history, build_result(points, limit, history.dropped_points, history.segment)}
  end

  @spec frames(History.t(), keyword()) :: {History.t(), t()}
  @doc "Returns ordered aggregate frames under the configured frame cap."
  def frames(history, options \\ []) do
    history = prune(history, options)
    since_ms = Keyword.get(options, :since_ms)

    filtered =
      Enum.filter(history.frames, fn frame ->
        is_nil(since_ms) or frame.sampled_at_ms >= since_ms
      end)

    {history,
     build_result(
       filtered,
       requested_limit(options, history.config.frame_limit),
       history.dropped_frames,
       history.segment
     )}
  end

  defp prune(history, options) do
    now_ms = Keyword.get(options, :now_ms, System.monotonic_time(:millisecond))

    case Keyword.get(options, :size_estimator) do
      estimator when is_function(estimator, 1) -> History.prune(history, now_ms, estimator)
      _other -> History.prune(history, now_ms)
    end
  end

  defp requested_limit(options, maximum) do
    case Keyword.get(options, :limit, maximum) do
      value when is_integer(value) and value > 0 -> min(value, maximum)
      _other -> maximum
    end
  end

  defp build_result(values, limit, dropped, segment) do
    kept = values |> Enum.take(-limit) |> Enum.reverse()

    %__MODULE__{
      items: kept,
      omitted: max(length(values) - length(kept), 0),
      dropped: dropped,
      available_from_ms: boundary_time(List.first(values)),
      available_to_ms: boundary_time(List.last(values)),
      segment: segment
    }
  end

  defp boundary_time(nil) do
    nil
  end

  defp boundary_time(value) do
    value.monotonic_ms
  end
end
