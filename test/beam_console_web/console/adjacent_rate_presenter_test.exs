defmodule BeamConsoleWeb.Console.AdjacentRatePresenterTest do
  use ExUnit.Case, async: true

  alias BeamConsole.Recorder.Frame
  alias BeamConsole.Runtime.Pressure
  alias BeamConsole.Runtime.Sample
  alias BeamConsoleWeb.Console.AdjacentRatePresenter

  test "derives rates only from valid adjacent frames and preserves discontinuities" do
    frames = [
      frame(1, 0, 1_000, 100),
      frame(2, 0, 2_000, 300),
      frame(3, 1, 3_000, 900),
      frame(4, 1, 4_000, 1_000),
      frame(5, 1, 4_000, 1_100),
      frame(6, 1, 5_000, 900),
      frame(7, 1, 6_000, nil),
      frame(8, 1, 7_000, 1_200),
      frame(9, 1, 8_000, 1_300)
    ]

    definition = %{key: :input, label: "Input", unit: "bytes/s", point_limit: 20}

    series =
      AdjacentRatePresenter.series(Enum.reverse(frames), definition, fn frame ->
        frame.runtime.pressure.io_input_bytes
      end)

    assert Enum.map(series.points, &Enum.at(&1, 1)) == [200.0, 100.0, 100.0]
    assert series.points |> Enum.map(&Enum.at(&1, 2)) |> Enum.uniq() |> length() == 3
  end

  test "caps derived points after calculating adjacent rates" do
    frames =
      for sequence <- 1..100 do
        frame(sequence, 0, sequence * 1_000, sequence * 100)
      end

    definition = %{key: :input, label: "Input", unit: "bytes/s", point_limit: 7}

    series =
      AdjacentRatePresenter.series(Enum.reverse(frames), definition, fn frame ->
        frame.runtime.pressure.io_input_bytes
      end)

    assert length(series.points) == 7
  end

  test "returns no latest rate across a segment boundary or counter regression" do
    getter = fn frame -> frame.runtime.pressure.io_input_bytes end

    assert AdjacentRatePresenter.latest(
             [frame(2, 1, 2_000, 200), frame(1, 0, 1_000, 100)],
             getter
           ) == nil

    assert AdjacentRatePresenter.latest(
             [frame(2, 0, 2_000, 90), frame(1, 0, 1_000, 100)],
             getter
           ) == nil
  end

  defp frame(sequence, segment, monotonic_ms, counter) do
    %Frame{
      sequence: sequence,
      segment: segment,
      sampled_at_ms: monotonic_ms,
      monotonic_ms: monotonic_ms,
      runtime: %Sample{
        sequence: sequence,
        sampled_at_ms: monotonic_ms,
        monotonic_ms: monotonic_ms,
        pressure: %Pressure{io_input_bytes: counter}
      }
    }
  end
end
