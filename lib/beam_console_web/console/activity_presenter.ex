defmodule BeamConsoleWeb.Console.ActivityPresenter do
  @moduledoc "Presents compact activity samples as summaries, movers, and chart events."

  alias BeamConsole.Activity.Sample
  alias BeamConsole.Recorder.Frame
  alias BeamConsole.Recorder.Query
  alias BeamConsoleWeb.Console.ChartPresenter

  @spec present(Query.t(), non_neg_integer()) :: map()
  @doc "Builds the current activity view without retaining historical frames in LiveView assigns."
  def present(%Query{} = query, revision) do
    frames = Enum.filter(query.items, &match?(%Frame{}, &1))
    latest = Enum.find_value(frames, & &1.activity)

    %{
      summary: summary(latest, query),
      movers: movers(latest),
      charts: charts(frames, revision)
    }
  end

  defp summary(nil, query) do
    %{reductions_per_second: 0, mailbox_delta: 0, memory_delta: 0, omitted: query.omitted}
  end

  defp summary(%Sample{} = sample, query) do
    Map.merge(sample.aggregates, %{omitted: sample.omitted + query.omitted})
  end

  defp movers(nil) do
    []
  end

  defp movers(%Sample{} = sample) do
    Enum.map(sample.top_movers, fn mover ->
      Map.put(mover, :id, "#{mover.entity_id}:#{mover.metric}")
    end)
  end

  defp charts(frames, revision) do
    [
      metric_chart(
        frames,
        revision,
        "activity-reductions",
        "Reductions / second",
        :reductions_per_second,
        "reductions/s"
      ),
      metric_chart(
        frames,
        revision,
        "activity-mailbox",
        "Mailbox change",
        :mailbox_delta,
        "messages"
      ),
      metric_chart(
        frames,
        revision,
        "activity-memory",
        "Process memory change",
        :memory_delta,
        "bytes"
      )
    ]
  end

  defp metric_chart(frames, revision, id, title, metric, unit) do
    series =
      ChartPresenter.series(frames, metric, title, unit, fn frame ->
        get_in(frame, [Access.key(:activity), Access.key(:aggregates), metric])
      end)

    ChartPresenter.chart(id, title, unit, [series], revision)
  end
end
