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
      inspected_process_count: 30,
      supervisor_count: 5,
      ets_count: 7,
      atom_count: 100,
      atom_limit: 1_000,
      run_queue: 2
    }

    result = RuntimePresenter.present(%Query{items: [frame(1, runtime: runtime)]}, 1)

    assert result.summary.process_count == 42
    assert result.summary.inspected_process_count == 30
    assert result.summary.atom_count == 100
    assert result.summary.atom_limit == 1_000
    assert result.summary.atom_utilization == 10.0
    assert result.summary.run_queue == 2
    assert length(result.charts) == 5

    atom_chart = Enum.find(result.charts, &(&1.id == "runtime-atoms"))

    assert atom_chart.series == [
             %{key: :atom_utilization, label: "Atoms", unit: "%", points: [[1, 10.0, 0]]}
           ]

    assert atom_chart.min == 0
    assert atom_chart.max == 100

    count_chart = Enum.find(result.charts, &(&1.id == "runtime-counts"))
    assert Enum.any?(count_chart.series, &(&1.key == :inspected_process_count))
  end

  test "empty runtime presentation exposes the complete render contract" do
    result = RuntimePresenter.present(%Query{omitted: 2, dropped: 3}, 0)

    assert result.summary.collector_partial? == false
    assert result.summary.omitted == 5
    assert result.summary.process_count == 0
    assert result.summary.inspected_process_count == 0
    assert result.summary.atom_count == nil
    assert result.summary.atom_limit == nil
    assert result.summary.atom_utilization == nil
  end

  test "runtime presentation tolerates retained samples from before the atom fields" do
    legacy_runtime =
      %RuntimeSample{sequence: 1, sampled_at_ms: 1, monotonic_ms: 1}
      |> Map.delete(:atom_count)
      |> Map.delete(:atom_limit)

    result = RuntimePresenter.present(%Query{items: [frame(1, runtime: legacy_runtime)]}, 1)

    assert result.summary.atom_count == nil
    assert result.summary.atom_limit == nil
    assert result.summary.atom_utilization == nil

    atom_chart = Enum.find(result.charts, &(&1.id == "runtime-atoms"))
    assert atom_chart.series == [%{key: :atom_utilization, label: "Atoms", unit: "%", points: []}]
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
