defmodule BeamConsoleWeb.Console.RuntimePresenter do
  @moduledoc "Presents compact node-wide samples as summaries and bounded chart events."

  alias BeamConsole.Recorder.Frame
  alias BeamConsole.Recorder.Query
  alias BeamConsole.Runtime.Sample
  alias BeamConsoleWeb.Console.ChartPresenter

  @scalar_charts [
    %{id: "runtime-run-queue", title: "Run queue", field: :run_queue, unit: "items"},
    %{id: "runtime-scan", title: "Collector scan", field: :collector_scan_ms, unit: "ms"}
  ]

  @doc "Builds the Runtime view without storing historical point arrays in LiveView assigns."
  @spec present(Query.t(), non_neg_integer()) :: map()
  def present(%Query{} = query, revision) do
    frames = Enum.filter(query.items, &match?(%Frame{}, &1))
    latest = Enum.find_value(frames, & &1.runtime)

    %{
      summary: summary(latest, query),
      charts: charts(frames, revision, query.chart_points_limit)
    }
  end

  defp summary(nil, query) do
    %{
      process_count: 0,
      supervisor_count: 0,
      ets_count: 0,
      run_queue: nil,
      collector_partial?: false,
      omitted: query.omitted + query.dropped
    }
  end

  defp summary(%Sample{} = sample, query) do
    sample
    |> Map.take([
      :process_count,
      :supervisor_count,
      :application_count,
      :ets_count,
      :node_count,
      :memory_total,
      :run_queue,
      :scheduler_count,
      :collector_scan_ms,
      :collector_partial?
    ])
    |> Map.put(:omitted, query.omitted + query.dropped)
  end

  defp charts(frames, revision, point_limit) do
    scalar_charts =
      Enum.map(@scalar_charts, &scalar_chart(frames, revision, point_limit, &1))

    [
      memory_chart(frames, revision, point_limit),
      Enum.at(scalar_charts, 0),
      count_chart(frames, revision, point_limit),
      Enum.at(scalar_charts, 1)
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

  defp count_chart(frames, revision, point_limit) do
    fields = [
      {:process_count, "Processes"},
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

  defp scalar_chart(frames, revision, point_limit, definition) do
    series_definition = %{
      key: definition.field,
      label: definition.title,
      unit: definition.unit,
      point_limit: point_limit
    }

    series =
      ChartPresenter.series(frames, series_definition, &runtime_value(&1, definition.field))

    chart_definition = Map.take(definition, [:id, :title, :unit])
    ChartPresenter.chart(chart_definition, [series], revision)
  end

  defp runtime_value(%Frame{runtime: %Sample{} = sample}, field) do
    Map.fetch!(sample, field)
  end

  defp runtime_value(_frame, _field) do
    nil
  end
end
