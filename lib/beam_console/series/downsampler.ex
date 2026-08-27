defmodule BeamConsole.Series.Downsampler do
  @moduledoc """
  Deterministically reduces numeric chart points while retaining endpoints and spikes.

  Points are maps containing `:sampled_at_ms` and `:value`. Segment metadata is
  preserved, allowing the browser renderer to keep recording gaps disconnected.
  """

  @type point :: %{
          required(:sampled_at_ms) => integer(),
          required(:value) => number(),
          optional(:segment) => non_neg_integer()
        }

  @doc """
  Applies Largest-Triangle-Three-Buckets downsampling to an ordered series.

  ## Examples

      iex> points = for value <- 1..10, do: %{sampled_at_ms: value, value: value}
      iex> result = BeamConsole.Series.Downsampler.downsample(points, 4)
      iex> {length(result), hd(result).value, List.last(result).value}
      {4, 1, 10}
  """
  @spec downsample([point()], pos_integer()) :: [point()]
  def downsample(points, limit) when is_list(points) and is_integer(limit) and limit > 0 do
    cond do
      length(points) <= limit -> points
      limit == 1 -> [List.last(points)]
      limit == 2 -> [hd(points), List.last(points)]
      true -> largest_triangle(points, limit)
    end
  end

  defp largest_triangle(points, limit) do
    point_count = length(points)
    bucket_width = (point_count - 2) / (limit - 2)

    {_anchor, selected} =
      Enum.reduce(0..(limit - 3), {hd(points), [hd(points)]}, fn bucket, {anchor, result} ->
        candidates = bucket_slice(points, bucket, bucket_width, point_count)
        average = next_bucket_average(points, bucket, bucket_width, point_count)
        chosen = Enum.max_by(candidates, &triangle_area(anchor, &1, average))
        {chosen, [chosen | result]}
      end)

    selected
    |> then(&[List.last(points) | &1])
    |> Enum.reverse()
  end

  defp bucket_slice(points, bucket, width, point_count) do
    first = floor(bucket * width) + 1
    last = min(floor((bucket + 1) * width) + 1, point_count - 1)
    Enum.slice(points, first, max(last - first, 1))
  end

  defp next_bucket_average(points, bucket, width, point_count) do
    first = min(floor((bucket + 1) * width) + 1, point_count - 1)
    last = min(floor((bucket + 2) * width) + 1, point_count)
    values = Enum.slice(points, first, max(last - first, 1))
    count = max(length(values), 1)

    {
      Enum.reduce(values, 0, &(&1.sampled_at_ms + &2)) / count,
      Enum.reduce(values, 0, &(&1.value + &2)) / count
    }
  end

  defp triangle_area(anchor, candidate, {average_x, average_y}) do
    abs(
      (anchor.sampled_at_ms - average_x) * (candidate.value - anchor.value) -
        (anchor.sampled_at_ms - candidate.sampled_at_ms) * (average_y - anchor.value)
    )
  end
end
