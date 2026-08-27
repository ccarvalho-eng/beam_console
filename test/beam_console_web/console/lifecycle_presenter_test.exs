defmodule BeamConsoleWeb.Console.LifecyclePresenterTest do
  use ExUnit.Case, async: true

  alias BeamConsole.Lifecycle.Event
  alias BeamConsole.Recorder.Query
  alias BeamConsoleWeb.Console.LifecyclePresenter

  test "includes lifecycle changes represented by retained gap events" do
    query = %Query{
      omitted: 2,
      dropped: 3,
      items: [gap_event(4), gap_event(0), observed_event()]
    }

    assert LifecyclePresenter.omitted_count(query) == 9
  end

  defp gap_event(omitted) do
    event(:gap, %{omitted: omitted})
  end

  defp observed_event do
    event(:observed_start, %{})
  end

  defp event(kind, details) do
    %Event{
      id: "event-#{kind}",
      kind: kind,
      sequence: 1,
      segment: 0,
      observed_at_ms: 1,
      monotonic_ms: 1,
      evidence: :snapshot_diff,
      certainty: :sampled,
      details: details
    }
  end
end
