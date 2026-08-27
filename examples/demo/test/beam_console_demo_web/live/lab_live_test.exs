defmodule BeamConsoleDemoWeb.LabLiveTest do
  use BeamConsoleDemoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias BeamConsoleDemo.ProcessLab

  @churn_supervisor BeamConsoleDemo.ProcessLab.ChurnSupervisor

  setup do
    Enum.each(DynamicSupervisor.which_children(@churn_supervisor), fn
      {_id, pid, _type, _modules} when is_pid(pid) ->
        DynamicSupervisor.terminate_child(@churn_supervisor, pid)

      _child ->
        :ok
    end)

    :ok
  end

  test "controls the demo topology outside the read-only console", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/lab")

    assert has_element?(view, "#process-lab")
    assert has_element?(view, "a[href='/beam']")

    view |> element("#start-child") |> render_click()

    assert has_element?(view, "#dynamic-count", "1")
    assert ProcessLab.snapshot().dynamic_children == 1
  end

  test "mounts BeamConsole through the demo browser pipeline", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/beam")

    assert has_element?(view, "#beam-console")
    assert has_element?(view, "#beam-console-graph")
  end
end
