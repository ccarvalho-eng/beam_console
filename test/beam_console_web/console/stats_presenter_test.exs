defmodule BeamConsoleWeb.Console.StatsPresenterTest do
  use ExUnit.Case, async: true

  alias BeamConsole.Activity.Sample, as: ActivitySample
  alias BeamConsole.Recorder.Frame
  alias BeamConsole.Recorder.Query
  alias BeamConsole.Runtime.Sample, as: RuntimeSample
  alias BeamConsoleWeb.Console.ActivityPresenter
  alias BeamConsoleWeb.Console.RuntimePresenter

  test "activity presentation exposes scalar assigns and capped chart payloads" do
    frames =
      for sequence <- 1..300 do
        activity = %ActivitySample{
          sequence: sequence,
          sampled_at_ms: sequence,
          monotonic_ms: sequence,
          aggregates: %{reductions_per_second: sequence, mailbox_delta: 1, memory_delta: 2}
        }

        frame(sequence, activity: activity)
      end

    query = %Query{
      items: Enum.reverse(frames),
      dropped: 4,
      omitted: 3,
      chart_points_limit: 17
    }

    result = ActivityPresenter.present(query, 300)

    assert result.summary.reductions_per_second == 300
    assert result.summary.omitted == 7

    assert Enum.all?(result.charts, fn chart ->
             Enum.all?(chart.series, &(length(&1.points) <= 17))
           end)

    refute Map.has_key?(result.summary, :charts)
  end

  test "runtime presentation reads only normalized runtime samples" do
    runtime = %RuntimeSample{
      sequence: 1,
      sampled_at_ms: 1,
      monotonic_ms: 1,
      process_count: 42,
      supervisor_count: 5,
      ets_count: 7,
      run_queue: 2
    }

    result = RuntimePresenter.present(%Query{items: [frame(1, runtime: runtime)]}, 1)

    assert result.summary.process_count == 42
    assert result.summary.run_queue == 2
    assert length(result.charts) == 4
  end

  test "empty runtime presentation exposes the complete render contract" do
    result = RuntimePresenter.present(%Query{omitted: 2, dropped: 3}, 0)

    assert result.summary.collector_partial? == false
    assert result.summary.omitted == 5
    assert result.summary.process_count == 0
  end

  defp frame(sequence, options) do
    %Frame{
      sequence: sequence,
      sampled_at_ms: sequence,
      monotonic_ms: sequence,
      activity: Keyword.get(options, :activity),
      runtime: Keyword.get(options, :runtime)
    }
  end
end
