defmodule BeamConsoleWeb.Console.StatsPresenterTest do
  use ExUnit.Case, async: true

  alias BeamConsole.Activity.Sample, as: ActivitySample
  alias BeamConsole.Recorder.Frame
  alias BeamConsole.Recorder.Query
  alias BeamConsole.Runtime.Pressure
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
    first_runtime = %RuntimeSample{
      sequence: 1,
      sampled_at_ms: 1_000,
      monotonic_ms: 1_000,
      process_count: 40,
      inspected_process_count: 30,
      supervisor_count: 5,
      ets_count: 7,
      atom_count: 100,
      atom_limit: 1_000,
      run_queue: 1,
      pressure: %Pressure{
        uptime_ms: 60_000,
        port_count: 5,
        port_limit: 100,
        process_limit: 100,
        scheduler_total: 8,
        scheduler_online: 6,
        dirty_cpu_scheduler_total: 4,
        dirty_cpu_scheduler_online: 3,
        dirty_io_scheduler_total: 2,
        run_queue_total: 1,
        run_queue_cpu: 1,
        run_queue_io: 0,
        io_input_bytes: 1_000,
        io_output_bytes: 2_000
      }
    }

    latest_runtime = %{
      first_runtime
      | sequence: 2,
        sampled_at_ms: 2_000,
        monotonic_ms: 2_000,
        process_count: 42,
        run_queue: 2,
        pressure: %{
          first_runtime.pressure
          | uptime_ms: 61_000,
            run_queue_total: 2,
            run_queue_cpu: 1,
            run_queue_io: 1,
            io_input_bytes: 1_300,
            io_output_bytes: 2_500
        }
    }

    result =
      RuntimePresenter.present(
        %Query{
          items: [
            frame(2, runtime: latest_runtime, sampled_at_ms: 2_000, monotonic_ms: 2_000),
            frame(1, runtime: first_runtime, sampled_at_ms: 1_000, monotonic_ms: 1_000)
          ]
        },
        2
      )

    assert result.summary.process_count == 42
    assert result.summary.inspected_process_count == 30
    assert result.summary.atom_count == 100
    assert result.summary.atom_limit == 1_000
    assert result.summary.atom_utilization == 10.0
    assert result.summary.run_queue == 2
    assert result.summary.port_utilization == 5.0
    assert result.summary.process_utilization == 42.0
    assert result.summary.io_input_per_second == 300.0
    assert result.summary.io_output_per_second == 500.0
    assert length(result.charts) == 6

    atom_chart = Enum.find(result.charts, &(&1.id == "runtime-atoms"))

    assert Enum.map(atom_chart.series, & &1.key) == [
             :process_utilization,
             :port_utilization,
             :atom_utilization
           ]

    assert atom_chart.min == 0
    assert atom_chart.max == 100

    count_chart = Enum.find(result.charts, &(&1.id == "runtime-counts"))
    assert Enum.any?(count_chart.series, &(&1.key == :inspected_process_count))

    run_queue_chart = Enum.find(result.charts, &(&1.id == "runtime-run-queue"))
    assert Enum.map(run_queue_chart.series, & &1.key) == [:total, :cpu, :io]

    io_chart = Enum.find(result.charts, &(&1.id == "runtime-io"))
    assert Enum.map(io_chart.series, & &1.key) == [:input, :output]
    assert Enum.at(io_chart.series, 0).points |> List.last() |> Enum.at(1) == 300.0
    assert Enum.at(io_chart.series, 1).points |> List.last() |> Enum.at(1) == 500.0
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
    assert result.summary.port_count == nil
    assert result.summary.io_input_per_second == nil
  end

  test "runtime presentation tolerates retained samples from before the atom fields" do
    legacy_runtime =
      %RuntimeSample{sequence: 1, sampled_at_ms: 1, monotonic_ms: 1}
      |> Map.delete(:atom_count)
      |> Map.delete(:atom_limit)
      |> Map.delete(:pressure)

    result = RuntimePresenter.present(%Query{items: [frame(1, runtime: legacy_runtime)]}, 1)

    assert result.summary.atom_count == nil
    assert result.summary.atom_limit == nil
    assert result.summary.atom_utilization == nil
    assert result.summary.port_count == nil
    assert result.summary.io_input_per_second == nil

    atom_chart = Enum.find(result.charts, &(&1.id == "runtime-atoms"))
    assert Enum.all?(atom_chart.series, &(&1.points == []))
  end

  defp frame(sequence, options) do
    %Frame{
      sequence: sequence,
      sampled_at_ms: Keyword.get(options, :sampled_at_ms, sequence),
      monotonic_ms: Keyword.get(options, :monotonic_ms, sequence),
      activity: Keyword.get(options, :activity),
      runtime: Keyword.get(options, :runtime)
    }
  end
end
