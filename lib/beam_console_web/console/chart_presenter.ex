defmodule BeamConsoleWeb.Console.ChartPresenter do
  @moduledoc "Builds capped, JSON-safe chart payloads from compact recorder frames."

  alias BeamConsole.Recorder.Frame
  alias BeamConsole.Series.Downsampler

  @point_limit 240

  @type getter :: (Frame.t() -> number() | nil)

  @spec series([Frame.t()], atom(), String.t(), String.t(), getter()) :: map()
  @doc "Builds one chronologically ordered, gap-aware, downsampled chart series."
  def series(frames, key, label, unit, getter) when is_function(getter, 1) do
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
      |> Downsampler.downsample(@point_limit)
      |> Enum.map(&[&1.sampled_at_ms, &1.value, &1.segment])

    %{key: key, label: label, unit: unit, points: points}
  end

  @spec chart(String.t(), String.t(), String.t(), [map()], non_neg_integer()) :: map()
  @doc "Wraps one or more series in a revisioned browser chart payload."
  def chart(id, title, unit, series, revision) do
    %{
      id: id,
      title: title,
      unit: unit,
      revision: revision,
      series: series
    }
  end
end
