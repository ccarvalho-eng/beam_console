defmodule BeamConsole.Series.DownsamplerTest do
  use ExUnit.Case, async: true

  doctest BeamConsole.Series.Downsampler

  alias BeamConsole.Series.Downsampler

  test "preserves endpoints, segment data, and a narrow spike" do
    points =
      for index <- 0..99 do
        %{sampled_at_ms: index, value: if(index == 50, do: 1_000, else: 1), segment: 3}
      end

    result = Downsampler.downsample(points, 12)

    assert length(result) == 12
    assert hd(result).sampled_at_ms == 0
    assert List.last(result).sampled_at_ms == 99
    assert Enum.any?(result, &(&1.value == 1_000))
    assert Enum.all?(result, &(&1.segment == 3))
  end

  test "supports tiny limits and already bounded input" do
    points = [%{sampled_at_ms: 1, value: 1}, %{sampled_at_ms: 2, value: 2}]

    assert Downsampler.downsample(points, 3) == points
    assert Downsampler.downsample(points, 1) == [List.last(points)]
    assert Downsampler.downsample(points, 2) == points
  end
end
