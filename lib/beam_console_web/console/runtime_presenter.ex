defmodule BeamConsoleWeb.Console.RuntimePresenter do
  @moduledoc "Presents compact node-wide samples as summaries and bounded chart events."

  alias BeamConsole.Recorder.Frame
  alias BeamConsole.Recorder.Query
  alias BeamConsole.Runtime.Pressure
  alias BeamConsole.Runtime.Sample
  alias BeamConsoleWeb.Console.AdjacentRatePresenter
  alias BeamConsoleWeb.Console.ChartPresenter

  @scan_chart %{
    id: "runtime-scan",
    title: "Collector scan",
    field: :collector_scan_ms,
    unit: "ms"
  }

  @doc "Builds the Runtime view without storing historical point arrays in LiveView assigns."
  @spec present(Query.t(), non_neg_integer()) :: map()
  def present(%Query{} = query, revision) do
    frames = Enum.filter(query.items, &match?(%Frame{}, &1))
    latest = Enum.find_value(frames, & &1.runtime)

    %{
      summary: summary(latest, frames, query),
      charts: charts(frames, revision, query.chart_points_limit)
    }
  end

  @doc "Returns the complete zero-value contract used before a runtime sample is available."
  @spec empty_summary() :: map()
  def empty_summary do
    %{
      process_count: 0,
      inspected_process_count: 0,
      supervisor_count: 0,
      application_count: 0,
      ets_count: 0,
      node_count: 0,
      atom_count: nil,
      atom_limit: nil,
      atom_utilization: nil,
      memory_total: nil,
      uptime_ms: nil,
      port_count: nil,
      port_limit: nil,
      port_utilization: nil,
      process_limit: nil,
      process_utilization: nil,
      scheduler_count: nil,
      scheduler_total: nil,
      scheduler_online: nil,
      dirty_cpu_scheduler_total: nil,
      dirty_cpu_scheduler_online: nil,
      dirty_io_scheduler_total: nil,
      run_queue: nil,
      run_queue_total: nil,
      run_queue_cpu: nil,
      run_queue_io: nil,
      io_input_per_second: nil,
      io_output_per_second: nil,
      collector_scan_ms: nil,
      collector_partial?: false,
      omitted: 0
    }
  end

  defp summary(nil, _frames, query) do
    Map.put(empty_summary(), :omitted, query.omitted + query.dropped)
  end

  defp summary(%Sample{} = sample, frames, query) do
    pressure = Map.get(sample, :pressure)
    atom_count = Map.get(sample, :atom_count)
    atom_limit = Map.get(sample, :atom_limit)
    process_count = Map.get(sample, :process_count, 0)
    process_limit = pressure_value(pressure, :process_limit)
    port_count = pressure_value(pressure, :port_count)
    port_limit = pressure_value(pressure, :port_limit)

    empty_summary()
    |> Map.merge(
      Map.take(sample, [
        :process_count,
        :inspected_process_count,
        :supervisor_count,
        :application_count,
        :ets_count,
        :node_count,
        :atom_count,
        :atom_limit,
        :memory_total,
        :run_queue,
        :scheduler_count,
        :collector_scan_ms,
        :collector_partial?
      ])
    )
    |> Map.merge(pressure_summary(pressure))
    |> Map.put(:atom_count, atom_count)
    |> Map.put(:atom_limit, atom_limit)
    |> Map.put(:atom_utilization, utilization(atom_count, atom_limit))
    |> Map.put(:process_utilization, utilization(process_count, process_limit))
    |> Map.put(:port_utilization, utilization(port_count, port_limit))
    |> Map.put(:io_input_per_second, latest_io_rate(frames, :io_input_bytes))
    |> Map.put(:io_output_per_second, latest_io_rate(frames, :io_output_bytes))
    |> Map.put(:omitted, query.omitted + query.dropped)
  end

  defp pressure_summary(%Pressure{} = pressure) do
    pressure
    |> Map.from_struct()
    |> Map.take([
      :uptime_ms,
      :port_count,
      :port_limit,
      :process_limit,
      :scheduler_total,
      :scheduler_online,
      :dirty_cpu_scheduler_total,
      :dirty_cpu_scheduler_online,
      :dirty_io_scheduler_total,
      :run_queue_total,
      :run_queue_cpu,
      :run_queue_io
    ])
  end

  defp pressure_summary(_pressure) do
    %{}
  end

  defp charts(frames, revision, point_limit) do
    [
      memory_chart(frames, revision, point_limit),
      run_queue_chart(frames, revision, point_limit),
      io_chart(frames, revision, point_limit),
      count_chart(frames, revision, point_limit),
      scalar_chart(frames, revision, point_limit, @scan_chart),
      capacity_chart(frames, revision, point_limit)
    ]
  end

  defp memory_chart(frames, revision, point_limit) do
    fields = [
      {:memory_processes, "Processes"},
      {:memory_ets, "ETS"},
      {:memory_binary, "Binaries"},
      {:memory_atom, "Atoms"},
      {:memory_code, "Code"},
      {:memory_system, "System"}
    ]

    series =
      Enum.map(fields, fn {field, label} ->
        definition = %{key: field, label: label, unit: "bytes", point_limit: point_limit}
        ChartPresenter.series(frames, definition, &runtime_value(&1, field))
      end)

    definition = %{id: "runtime-memory", title: "BEAM memory", unit: "bytes"}
    ChartPresenter.chart(definition, series, revision)
  end

  defp run_queue_chart(frames, revision, point_limit) do
    fields = [
      {:total, "Total", :run_queue_total},
      {:cpu, "CPU", :run_queue_cpu},
      {:io, "I/O", :run_queue_io}
    ]

    series =
      Enum.map(fields, fn {key, label, field} ->
        definition = %{key: key, label: label, unit: "items", point_limit: point_limit}
        ChartPresenter.series(frames, definition, &run_queue_value(&1, field))
      end)

    definition = %{id: "runtime-run-queue", title: "Run queues", unit: "items"}
    ChartPresenter.chart(definition, series, revision)
  end

  defp io_chart(frames, revision, point_limit) do
    fields = [
      {:input, "Input", :io_input_bytes},
      {:output, "Output", :io_output_bytes}
    ]

    series =
      Enum.map(fields, fn {key, label, field} ->
        definition = %{key: key, label: label, unit: "bytes/s", point_limit: point_limit}

        AdjacentRatePresenter.series(
          frames,
          definition,
          &runtime_pressure_value(&1, field)
        )
      end)

    definition = %{id: "runtime-io", title: "I/O throughput", unit: "bytes/s"}
    ChartPresenter.chart(definition, series, revision)
  end

  defp count_chart(frames, revision, point_limit) do
    fields = [
      {:process_count, "Processes"},
      {:inspected_process_count, "Inspected processes"},
      {:supervisor_count, "Supervisors"},
      {:application_count, "Applications"},
      {:ets_count, "ETS tables"}
    ]

    series =
      Enum.map(fields, fn {field, label} ->
        definition = %{key: field, label: label, unit: "count", point_limit: point_limit}
        ChartPresenter.series(frames, definition, &runtime_value(&1, field))
      end)

    definition = %{id: "runtime-counts", title: "Runtime inventory", unit: "count"}
    ChartPresenter.chart(definition, series, revision)
  end

  defp capacity_chart(frames, revision, point_limit) do
    fields = [
      {:process_utilization, "Processes", :process_count, :process_limit},
      {:port_utilization, "Ports", :port_count, :port_limit},
      {:atom_utilization, "Atoms", :atom_count, :atom_limit}
    ]

    series =
      Enum.map(fields, fn {key, label, count_field, limit_field} ->
        definition = %{key: key, label: label, unit: "%", point_limit: point_limit}

        ChartPresenter.series(
          frames,
          definition,
          &capacity_value(&1, count_field, limit_field)
        )
      end)

    definition = %{
      id: "runtime-atoms",
      title: "Runtime capacity",
      unit: "%",
      min: 0,
      max: 100
    }

    ChartPresenter.chart(definition, series, revision)
  end

  defp scalar_chart(frames, revision, point_limit, definition) do
    series_definition = %{
      key: definition.field,
      label: Map.get(definition, :label, definition.title),
      unit: definition.unit,
      point_limit: point_limit
    }

    series =
      ChartPresenter.series(frames, series_definition, &runtime_value(&1, definition.field))

    chart_definition = Map.take(definition, [:id, :title, :unit, :min, :max])
    ChartPresenter.chart(chart_definition, [series], revision)
  end

  defp capacity_value(frame, :atom_count, :atom_limit) do
    utilization(runtime_value(frame, :atom_count), runtime_value(frame, :atom_limit))
  end

  defp capacity_value(frame, :process_count, :process_limit) do
    utilization(
      runtime_value(frame, :process_count),
      runtime_pressure_value(frame, :process_limit)
    )
  end

  defp capacity_value(frame, :port_count, :port_limit) do
    utilization(
      runtime_pressure_value(frame, :port_count),
      runtime_pressure_value(frame, :port_limit)
    )
  end

  defp run_queue_value(frame, :run_queue_total) do
    runtime_pressure_value(frame, :run_queue_total) || runtime_value(frame, :run_queue)
  end

  defp run_queue_value(frame, field) do
    runtime_pressure_value(frame, field)
  end

  defp runtime_value(%Frame{runtime: %Sample{} = sample}, field) do
    Map.get(sample, field)
  end

  defp runtime_value(_frame, _field) do
    nil
  end

  defp runtime_pressure_value(%Frame{runtime: %Sample{} = sample}, field) do
    sample
    |> Map.get(:pressure)
    |> pressure_value(field)
  end

  defp runtime_pressure_value(_frame, _field) do
    nil
  end

  defp pressure_value(%Pressure{} = pressure, field) do
    Map.get(pressure, field)
  end

  defp pressure_value(_pressure, _field) do
    nil
  end

  defp latest_io_rate(frames, field) do
    AdjacentRatePresenter.latest(frames, &runtime_pressure_value(&1, field))
  end

  defp utilization(count, limit)
       when is_integer(count) and is_integer(limit) and limit > 0 do
    count / limit * 100
  end

  defp utilization(_count, _limit) do
    nil
  end
end
