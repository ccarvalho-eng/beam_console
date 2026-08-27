defmodule BeamConsoleWeb.Console.RuntimePresenter do
  @moduledoc "Presents compact node-wide samples as summaries and bounded chart events."

  alias BeamConsole.Recorder.Frame
  alias BeamConsole.Recorder.Query
  alias BeamConsole.Runtime.Sample
  alias BeamConsoleWeb.Console.ChartPresenter

  @spec present(Query.t(), non_neg_integer()) :: map()
  @doc "Builds the Runtime view without storing historical point arrays in LiveView assigns."
  def present(%Query{} = query, revision) do
    frames = Enum.filter(query.items, &match?(%Frame{}, &1))
    latest = Enum.find_value(frames, & &1.runtime)

    %{summary: summary(latest, query), charts: charts(frames, revision)}
  end

  defp summary(nil, query) do
    %{process_count: 0, supervisor_count: 0, ets_count: 0, run_queue: nil, omitted: query.omitted}
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
    |> Map.put(:omitted, query.omitted)
  end

  defp charts(frames, revision) do
    [
      memory_chart(frames, revision),
      scalar_chart(frames, revision, "runtime-run-queue", "Run queue", :run_queue, "items"),
      count_chart(frames, revision),
      scalar_chart(frames, revision, "runtime-scan", "Collector scan", :collector_scan_ms, "ms")
    ]
  end

  defp memory_chart(frames, revision) do
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
        ChartPresenter.series(frames, field, label, "bytes", &runtime_value(&1, field))
      end)

    ChartPresenter.chart("runtime-memory", "BEAM memory", "bytes", series, revision)
  end

  defp count_chart(frames, revision) do
    fields = [
      {:process_count, "Processes"},
      {:supervisor_count, "Supervisors"},
      {:application_count, "Applications"},
      {:ets_count, "ETS tables"}
    ]

    series =
      Enum.map(fields, fn {field, label} ->
        ChartPresenter.series(frames, field, label, "count", &runtime_value(&1, field))
      end)

    ChartPresenter.chart("runtime-counts", "Runtime inventory", "count", series, revision)
  end

  defp scalar_chart(frames, revision, id, title, field, unit) do
    series = ChartPresenter.series(frames, field, title, unit, &runtime_value(&1, field))
    ChartPresenter.chart(id, title, unit, [series], revision)
  end

  defp runtime_value(%Frame{runtime: %Sample{} = sample}, field) do
    Map.fetch!(sample, field)
  end

  defp runtime_value(_frame, _field) do
    nil
  end
end
