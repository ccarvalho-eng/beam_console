defmodule BeamConsoleWeb.Console.AdjacentRatePresenter do
  @moduledoc """
  Derives bounded rates from adjacent cumulative recorder counters.

  Rates are emitted only within one recorder segment and when elapsed time and
  both counters are valid. Every invalid transition starts a new chart segment,
  so gaps, resets, missing values, and counter regressions remain visible.
  """

  alias BeamConsole.Recorder.Frame
  alias BeamConsole.Series.Downsampler
  alias BeamConsoleWeb.Console.ChartPresenter

  @type counter_getter :: (Frame.t() -> non_neg_integer() | nil)

  @doc "Builds one gap-aware, downsampled rate series from newest-first frames."
  @spec series([Frame.t()], ChartPresenter.series_definition(), counter_getter()) :: map()
  def series(frames, definition, counter_getter) when is_function(counter_getter, 1) do
    point_limit = Map.fetch!(definition, :point_limit)

    points =
      frames
      |> Enum.reverse()
      |> rate_points(counter_getter)
      |> Downsampler.downsample(point_limit)
      |> Enum.map(&[&1.sampled_at_ms, &1.value, &1.segment])

    definition
    |> Map.delete(:point_limit)
    |> Map.put(:points, points)
  end

  @doc "Returns the rate for the latest adjacent frame pair, or `nil` across a discontinuity."
  @spec latest([Frame.t()], counter_getter()) :: number() | nil
  def latest([current, previous | _frames], counter_getter)
      when is_function(counter_getter, 1) do
    case transition(previous, current, counter_getter) do
      {:ok, rate} -> rate
      :error -> nil
    end
  end

  def latest(_frames, counter_getter) when is_function(counter_getter, 1) do
    nil
  end

  defp rate_points([], _counter_getter) do
    []
  end

  defp rate_points([first | rest], counter_getter) do
    initial = %{previous: first, discontinuity: 0, points: []}

    rest
    |> Enum.reduce(initial, &rate_point(&1, &2, counter_getter))
    |> Map.fetch!(:points)
    |> Enum.reverse()
  end

  defp rate_point(current, state, counter_getter) do
    case transition(state.previous, current, counter_getter) do
      {:ok, rate} ->
        point = %{
          sampled_at_ms: current.sampled_at_ms,
          value: rate,
          segment: rate_segment(current.segment, state.discontinuity)
        }

        %{state | previous: current, points: [point | state.points]}

      :error ->
        %{state | previous: current, discontinuity: state.discontinuity + 1}
    end
  end

  defp transition(previous, current, counter_getter) do
    previous_counter = counter_getter.(previous)
    current_counter = counter_getter.(current)
    elapsed_ms = current.monotonic_ms - previous.monotonic_ms

    if current.segment == previous.segment and elapsed_ms > 0 and
         valid_counter?(previous_counter) and valid_counter?(current_counter) and
         current_counter >= previous_counter do
      {:ok, (current_counter - previous_counter) * 1_000 / elapsed_ms}
    else
      :error
    end
  end

  defp valid_counter?(counter) do
    is_integer(counter) and counter >= 0
  end

  defp rate_segment(segment, discontinuity) do
    "#{segment}:#{discontinuity}"
  end
end
