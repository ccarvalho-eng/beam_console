if Code.ensure_loaded?(Phoenix.LiveViewTest) do
  defmodule BeamConsoleWeb.Components.ProcessMapComponentsTest do
    use ExUnit.Case, async: true

    import Phoenix.LiveViewTest

    alias BeamConsoleWeb.Components.ProcessMapComponents

    test "keeps relationship controls separate from the passive graph legend" do
      streams = %{
        processes: Phoenix.LiveView.LiveStream.new(:processes, 0, [], dom_id: & &1.id)
      }

      html =
        render_component(&ProcessMapComponents.process_map/1,
          streams: streams,
          process_count: 0,
          process_matching_count: 0,
          process_omitted_count: 0
        )

      assert html =~ ~s(class="beam-console-graph-controls")
      assert html =~ ~s(class="beam-console-edge-toggle")
      assert html =~ ~s(class="beam-console-legend")
      assert html =~ "Links + monitors"
    end
  end
end
