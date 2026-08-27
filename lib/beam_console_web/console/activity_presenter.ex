defmodule BeamConsoleWeb.Console.ActivityPresenter do
  @moduledoc "Presents compact activity samples as summaries, movers, and chart events."

  alias BeamConsole.Activity.Sample
  alias BeamConsole.Recorder.Frame
  alias BeamConsole.Recorder.Query
  alias BeamConsoleWeb.Console.ChartPresenter

  @chart_definitions [
    %{
      id: "activity-reductions",
      title: "Reductions / second",
      metric: :reductions_per_second,
      unit: "reductions/s"
    },
    %{
      id: "activity-mailbox",
      title: "Mailbox change",
      metric: :mailbox_delta,
      unit: "messages"
    },
    %{
      id: "activity-memory",
      title: "Process memory change",
      metric: :memory_delta,
      unit: "bytes"
    }
  ]

  @doc "Builds the current activity view without retaining historical frames in LiveView assigns."
  @spec present(Query.t(), non_neg_integer()) :: map()
  def present(%Query{} = query, revision) do
    frames = Enum.filter(query.items, &match?(%Frame{}, &1))
    latest = Enum.find_value(frames, & &1.activity)

    %{
      summary: summary(latest, query),
      movers: movers(latest),
      charts: charts(frames, revision, query.chart_points_limit)
    }
  end

  defp summary(nil, query) do
    %{
      reductions_per_second: 0,
      mailbox_delta: 0,
      memory_delta: 0,
      omitted: query.omitted + query.dropped
    }
  end

  defp summary(%Sample{} = sample, query) do
    Map.merge(sample.aggregates, %{omitted: sample.omitted + query.omitted + query.dropped})
  end

  defp movers(nil) do
    []
  end

  defp movers(%Sample{} = sample) do
    Enum.map(sample.top_movers, fn mover ->
      Map.put(mover, :id, "#{mover.entity_id}:#{mover.metric}")
    end)
  end

  defp charts(frames, revision, point_limit) do
    Enum.map(@chart_definitions, &metric_chart(frames, revision, point_limit, &1))
  end

  defp metric_chart(frames, revision, point_limit, definition) do
    series_definition = %{
      key: definition.metric,
      label: definition.title,
      unit: definition.unit,
      point_limit: point_limit
    }

    series =
      ChartPresenter.series(frames, series_definition, fn frame ->
        get_in(frame, [Access.key(:activity), Access.key(:aggregates), definition.metric])
      end)

    chart_definition = Map.take(definition, [:id, :title, :unit])
    ChartPresenter.chart(chart_definition, [series], revision)
  end
end
