defmodule BeamConsoleWeb.GraphTest do
  use ExUnit.Case, async: false

  alias BeamConsole.ApplicationInfo
  alias BeamConsole.Coverage
  alias BeamConsole.NodeInfo
  alias BeamConsole.ProcessInfo
  alias BeamConsole.Runtime.Local
  alias BeamConsole.Snapshot
  alias BeamConsole.SupervisionEdge
  alias BeamConsoleWeb.Graph

  test "renders one focused application as a directed supervision hierarchy" do
    snapshot = snapshot_fixture()
    payload = Graph.payload(snapshot, nil)

    nodes = Enum.filter(payload.elements, &(&1.data[:source] == nil))
    edges = Enum.reject(payload.elements, &(&1.data[:source] == nil))

    assert Enum.map(nodes, & &1.data.id) |> Enum.sort() == [
             "app-demo",
             "node-local",
             "proc-child",
             "proc-root"
           ]

    assert Enum.any?(edges, &(&1.data.kind == "contains"))
    assert Enum.any?(edges, &(&1.data.kind == "owns"))
    assert Enum.any?(edges, &(&1.data.kind == "supervises"))
    refute Enum.any?(nodes, &(&1.data.id == "proc-other"))
  end

  test "changes focus when a process from another application is selected" do
    snapshot = snapshot_fixture()
    payload = Graph.payload(snapshot, "proc-other")

    assert payload.focus == "other"
    assert payload.selected == "proc-other"
    assert Enum.any?(payload.elements, &(&1.data.id == "app-other"))
    refute Enum.any?(payload.elements, &(&1.data.id == "proc-child"))
  end

  test "consecutive observer tasks produce the same rendered topology" do
    first = observed_graph_topology(31)
    second = observed_graph_topology(32)

    assert first == second
  end

  defp snapshot_fixture do
    demo = %ApplicationInfo{
      id: "app-demo",
      name: :demo,
      node_id: "node-local",
      root_supervisor_id: "proc-root"
    }

    other = %ApplicationInfo{
      id: "app-other",
      name: :other,
      node_id: "node-local",
      root_supervisor_id: "proc-other"
    }

    root = process("proc-root", :demo, "Root")
    child = process("proc-child", :demo, "Child")
    other_process = process("proc-other", :other, "Other")

    %Snapshot{
      sequence: 7,
      sampled_at: DateTime.utc_now(),
      local_node_id: "node-local",
      nodes: %{
        "node-local" => %NodeInfo{
          id: "node-local",
          name: "nonode@nohost",
          kind: :local,
          inspectable?: true
        }
      },
      applications: %{"app-demo" => demo, "app-other" => other},
      processes: %{
        "proc-root" => root,
        "proc-child" => child,
        "proc-other" => other_process
      },
      edges: %{
        "edge-child" => %SupervisionEdge{
          id: "edge-child",
          parent_id: "proc-root",
          child_id: "proc-child",
          label: "child",
          state: :running,
          child_type: :worker
        }
      },
      coverage: %Coverage{},
      index: %{
        "app-demo" => {:application, :demo},
        "app-other" => {:application, :other},
        "proc-root" => {:process, self()},
        "proc-child" => {:process, self()},
        "proc-other" => {:process, self()}
      }
    }
  end

  defp process(id, application, label) do
    %ProcessInfo{
      id: id,
      node_id: "node-local",
      pid: self(),
      pid_text: inspect(self()),
      label: label,
      application: application,
      supervision_application: application,
      attribution: :otp_and_supervision
    }
  end

  defp observed_graph_topology(sequence) do
    task =
      Task.Supervisor.async_nolink(BeamConsole.TaskSupervisor, fn ->
        {:ok, snapshot} = Local.snapshot(sequence: sequence, process_limit: 20_000)

        snapshot
        |> Graph.payload(nil)
        |> Map.fetch!(:elements)
        |> Enum.map(fn element ->
          data = element.data
          {data.id, data[:source], data[:target], data.kind}
        end)
        |> Enum.sort()
      end)

    Task.await(task, 5_000)
  end
end
