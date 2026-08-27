defmodule BeamConsoleWeb.Console.ChartPresenter do
  @moduledoc "Builds capped, JSON-safe chart payloads from compact recorder frames."

  alias BeamConsole.Recorder.Frame
  alias BeamConsole.Series.Downsampler

  @type getter :: (Frame.t() -> number() | nil)
  @type series_definition :: %{
          key: atom(),
          label: String.t(),
          unit: String.t(),
          point_limit: pos_integer()
        }
  @type chart_definition :: %{id: String.t(), title: String.t(), unit: String.t()}

  @doc "Builds one chronologically ordered, gap-aware, downsampled chart series."
  @spec series([Frame.t()], series_definition(), getter()) :: map()
  def series(frames, definition, getter) when is_function(getter, 1) do
    point_limit = Map.fetch!(definition, :point_limit)

    points =
      frames
      |> Enum.reverse()
      |> Enum.flat_map(fn frame ->
        case getter.(frame) do
          value when is_number(value) ->
            [%{sampled_at_ms: frame.sampled_at_ms, value: value, segment: frame.segment}]

          _other ->
            []
        end
      end)
      |> Downsampler.downsample(point_limit)
      |> Enum.map(&[&1.sampled_at_ms, &1.value, &1.segment])

    definition
    |> Map.delete(:point_limit)
    |> Map.put(:points, points)
  end

  @doc "Wraps one or more series in a revisioned browser chart payload."
  @spec chart(chart_definition(), [map()], non_neg_integer()) :: map()
  def chart(definition, series, revision) do
    Map.merge(definition, %{revision: revision, series: series})
  end
end
