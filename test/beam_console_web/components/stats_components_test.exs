if Code.ensure_loaded?(Phoenix.LiveViewTest) do
  defmodule BeamConsoleWeb.Components.StatsComponentsTest do
    use ExUnit.Case, async: true

    import Phoenix.LiveViewTest

    alias BeamConsoleWeb.Components.StatsComponents

    test "renders readable and accessible atom table capacity" do
      summary = %{
        atom_count: 123_456,
        atom_limit: 1_048_576,
        atom_utilization: 11.77,
        collector_partial?: false,
        ets_count: 12,
        process_count: 345,
        run_queue: 1,
        supervisor_count: 23
      }

      html =
        render_component(&StatsComponents.runtime/1,
          summary: summary,
          has_samples?: false
        )

      assert html =~ ">123,456</strong>"
      assert html =~ ">23</strong>"
      assert html =~ "of 1,048,576 · 11.77% used"
      assert html =~ "Atoms persist for the VM lifetime."
      assert html =~ ~s(role="group")
      assert html =~ ~s(aria-labelledby="beam-console-atom-label")
      assert html =~ ~s(aria-describedby="beam-console-atom-description")
    end
  end
end
