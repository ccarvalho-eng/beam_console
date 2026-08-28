if Code.ensure_loaded?(Phoenix.LiveViewTest) do
  defmodule BeamConsoleWeb.Components.StatsComponentsTest do
    use ExUnit.Case, async: true

    import Phoenix.LiveViewTest

    alias BeamConsoleWeb.Components.StatsComponents
    alias BeamConsoleWeb.Console.RuntimePresenter

    test "renders readable and accessible atom table capacity" do
      summary = %{
        atom_count: 123_456,
        atom_limit: 1_048_576,
        atom_utilization: 11.77,
        collector_partial?: false,
        ets_count: 12,
        inspected_process_count: 300,
        io_input_per_second: 2_048.0,
        io_output_per_second: 4_096.0,
        port_count: 17,
        port_limit: 65_536,
        port_utilization: 0.03,
        process_count: 345,
        process_limit: 1_048_576,
        process_utilization: 0.03,
        run_queue: 1,
        run_queue_cpu: 1,
        run_queue_io: 0,
        scheduler_online: 8,
        scheduler_total: 10,
        dirty_cpu_scheduler_online: 4,
        dirty_cpu_scheduler_total: 5,
        dirty_io_scheduler_total: 3,
        supervisor_count: 23,
        uptime_ms: 93_784_000
      }

      html =
        render_component(&StatsComponents.runtime/1,
          summary: summary,
          has_samples?: false
        )

      assert html =~ ">123,456</strong>"
      assert html =~ ">23</strong>"
      assert html =~ "300 inspected by the bounded collector"
      assert html =~ "of 1,048,576 · 11.77% used"
      assert html =~ "Atoms persist for the VM lifetime."
      assert html =~ "17 of 65,536"
      assert html =~ "8 of 10 online"
      assert html =~ "CPU 1 · I/O 0"
      assert html =~ "In 2.0 KB/s · Out 4.0 KB/s"
      assert html =~ "1d 2h 3m"
      assert html =~ ~s(role="group")
      assert html =~ ~s(aria-labelledby="beam-console-atom-label")
      assert html =~ ~s(aria-describedby="beam-console-atom-description")
    end

    test "renders the complete unavailable runtime state without misleading utilization" do
      html =
        render_component(&StatsComponents.runtime/1,
          summary: RuntimePresenter.empty_summary(),
          has_samples?: false
        )

      assert html =~ "Limit unavailable"
      assert html =~ "Usage unavailable"
      assert html =~ "Dirty scheduler topology unavailable"
      assert html =~ "Queue split unavailable"
      assert html =~ "In — · Out —"
      refute html =~ "% used"
    end
  end
end
