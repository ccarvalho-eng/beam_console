defmodule BeamConsoleWeb.Console.DashboardPresenterTest do
  use ExUnit.Case, async: true

  alias BeamConsole.ApplicationInfo
  alias BeamConsole.ProcessInfo
  alias BeamConsole.Snapshot
  alias BeamConsoleWeb.Console.DashboardPresenter

  test "reports exact process omissions and bounded selection view models" do
    first = process("proc_1", "Alpha")
    second = process("proc_2", "Beta")
    application = %ApplicationInfo{id: "app_1", name: :sample, node_id: "node_1"}

    snapshot = %Snapshot{
      sequence: 1,
      sampled_at: ~U[2026-01-01 00:00:00Z],
      local_node_id: "node_1",
      processes: %{first.id => first, second.id => second},
      applications: %{application.id => application},
      index: %{
        first.id => {:process, self()},
        second.id => {:process, self()},
        application.id => {:application, :sample}
      }
    }

    assert %{items: [%{id: "proc_1"}], matching_count: 2, omitted_count: 1} =
             DashboardPresenter.process_result(snapshot, "", 1)

    assert %{kind: :application, label: "sample"} =
             DashboardPresenter.selection(snapshot, application.id)
  end

  defp process(id, label) do
    %ProcessInfo{
      id: id,
      node_id: "node_1",
      pid: self(),
      pid_text: "<0.1.0>",
      label: label
    }
  end
end
