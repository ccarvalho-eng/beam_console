defmodule BeamConsoleWeb.ConsoleLiveTest do
  use ExUnit.Case

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint BeamConsoleWeb.TestEndpoint

  setup do
    start_supervised!(@endpoint)

    {:ok, snapshot} = BeamConsole.subscribe()

    snapshot =
      if snapshot do
        snapshot
      else
        BeamConsole.refresh()
        assert_receive {:beam_console_snapshot, sequence}, 2_000
        :ok = BeamConsole.acknowledge(sequence)
        BeamConsole.latest_snapshot()
      end

    on_exit(&BeamConsole.unsubscribe/0)

    %{snapshot: snapshot}
  end

  test "renders the accessible console shell through the embedded route" do
    {:ok, view, html} = live(build_conn(), "/beam")

    assert html =~ "/beam/assets/theme/#{BeamConsoleWeb.Assets.theme_digest()}"

    assert theme_script_position(html) < stylesheet_position(html)

    assert has_element?(view, "#beam-console[phx-hook='BeamConsoleTheme']")
    assert has_element?(view, "#beam-console-graph[phx-hook='BeamConsoleGraph']")

    assert has_element?(
             view,
             "#beam-console-runtime-tree[phx-hook='BeamConsoleTree'] details[open]"
           )

    assert has_element?(view, "#beam-console-search")
    assert has_element?(view, "#beam-console-tab-process_map[aria-current='page']")
    assert has_element?(view, "#beam-console-tab-lifecycle")
    assert has_element?(view, "#beam-console-recorder-control")
    assert has_element?(view, "#beam-console-refresh[aria-label='Refresh runtime sample'] svg")

    assert has_element?(
             view,
             "#beam-console-refresh + #beam-console-theme-switcher button[data-beam-console-theme='system']"
           )

    assert has_element?(
             view,
             "button[data-beam-console-theme='light'][aria-label='Use light theme']"
           )

    assert has_element?(
             view,
             "button[data-beam-console-theme='dark'][aria-label='Use dark theme']"
           )

    assert has_element?(view, "#beam-console-detail-empty")

    assert has_element?(
             view,
             "#beam-console-runtime-panel [aria-label='Close runtime hierarchy']"
           )

    assert has_element?(view, "#beam-console-inspector-panel [aria-label='Close inspector']")
    assert has_element?(view, "#beam-console-status-announcement", "Runtime sampling is live")
    refute render(view) =~ "Runtime sampling is live · sample"
    assert has_element?(view, "button[phx-value-edges='supervision'][aria-pressed='true']")
    assert has_element?(view, "button[phx-value-edges='relationships'][aria-pressed='false']")
  end

  test "updates process-map labels with the selected connection mode" do
    {:ok, view, _html} = live(build_conn(), "/beam")

    render_click(view, "set_edges", %{"edges" => "relationships"})

    assert has_element?(view, "section[aria-label='Process relationship topology']")
    assert has_element?(view, "button[phx-value-edges='relationships'][aria-pressed='true']")

    assert has_element?(view, ".beam-console-graph-toolbar strong", "Live links and monitors")
  end

  test "pushes live topology samples while the graph preserves positions", %{snapshot: snapshot} do
    {:ok, view, _html} = live(build_conn(), "/beam")
    assert_push_event(view, "beam_console_graph", %{sequence: _initial_sequence})

    send(view.pid, {:beam_console_snapshot, snapshot.sequence})

    assert_push_event(view, "beam_console_graph", %{sequence: _sequence})
  end

  test "preserves selected process rows across ordinary sample updates", %{snapshot: snapshot} do
    process =
      snapshot
      |> BeamConsoleWeb.Console.DashboardPresenter.process_result("", 150)
      |> Map.fetch!(:items)
      |> List.first()

    {:ok, view, _html} =
      live(build_conn(), "/beam?" <> URI.encode_query(%{"entity" => process.id}))

    assert has_element?(view, "#processes-#{process.id}[aria-pressed='true']")
    send(view.pid, {:beam_console_snapshot, snapshot.sequence})
    assert has_element?(view, "#processes-#{process.id}[aria-pressed='true']")
    assert has_element?(view, "#beam-console-tab-process_map[aria-current='page']")
  end

  test "loads an allowlisted process detail from a URL selection", %{snapshot: snapshot} do
    process = snapshot.processes |> Map.values() |> Enum.find(&Process.alive?(&1.pid))

    {:ok, view, _html} =
      live(build_conn(), "/beam?" <> URI.encode_query(%{"entity" => process.id}))

    assert has_element?(view, "#beam-console-detail")
  end

  test "handles an unknown selection without resolving client data" do
    {:ok, view, _html} = live(build_conn(), "/beam?entity=not-a-runtime-id")

    assert has_element?(view, "#beam-console-detail-empty")
  end

  test "runs host authorization hooks with merged session data" do
    assert {:ok, authorized, _html} = live(build_conn(), "/secure-beam")
    assert :sys.get_state(authorized.pid).socket.assigns.authorized_by_host?

    assert {:error, {:redirect, %{to: "/"}}} = live(build_conn(), "/blocked-beam")
  end

  test "renders URL-backed lifecycle, activity, and runtime tabs" do
    {:ok, lifecycle, _html} = live(build_conn(), "/beam/lifecycle")
    assert page_title(lifecycle) == "BeamConsole · Lifecycle"
    assert has_element?(lifecycle, "#beam-console-tab-lifecycle[aria-current='page']")
    assert has_element?(lifecycle, "#beam-console-lifecycle-list")

    {:ok, activity, _html} = live(build_conn(), "/beam/activity")
    assert page_title(activity) == "BeamConsole · Activity"
    assert has_element?(activity, "#beam-console-tab-activity[aria-current='page']")
    assert has_element?(activity, "#beam-console-search.is-placeholder input[disabled]")

    {:ok, runtime, _html} = live(build_conn(), "/beam/runtime")
    assert page_title(runtime) == "BeamConsole · Runtime"
    assert has_element?(runtime, "#beam-console-tab-runtime[aria-current='page']")
    assert has_element?(runtime, ".beam-console-runtime-summary div", "Supervisors")
    assert has_element?(runtime, "#beam-console-atom-usage strong")
    assert has_element?(runtime, "#beam-console-atom-description")
    assert has_element?(runtime, "[data-chart-id='runtime-atoms']")
  end

  test "pauses and resumes recording from the header" do
    {:ok, view, _html} = live(build_conn(), "/beam/lifecycle")

    assert has_element?(view, "#beam-console-recorder-control[aria-label='Pause recording']")
    render_click(view, "toggle_recording", %{})
    assert has_element?(view, "#beam-console-recorder-control[aria-label='Resume recording']")
    assert has_element?(view, ".beam-console-recording-badge.is-paused")

    render_click(view, "toggle_recording", %{})
    assert has_element?(view, "#beam-console-recorder-control[aria-label='Pause recording']")
  end

  test "does not retain full runtime snapshots in LiveView assigns" do
    {:ok, view, _html} = live(build_conn(), "/beam")
    %{socket: %{assigns: assigns}} = :sys.get_state(view.pid)

    refute Map.has_key?(assigns, :snapshot)
    refute Enum.any?(Map.values(assigns), &match?(%BeamConsole.Snapshot{}, &1))
    refute contains_chart_points?(assigns)
  end

  test "resubscribes after the shared collector restarts" do
    {:ok, view, _html} = live(build_conn(), "/beam")
    assert_push_event(view, "beam_console_graph", %{epoch: original_epoch})
    original_collector = Process.whereis(BeamConsole.Collector)

    assert :ok = Supervisor.terminate_child(BeamConsole.Supervisor, BeamConsole.Collector)

    assert eventually(fn ->
             state = :sys.get_state(view.pid)
             state.socket.assigns.collector_pid == nil
           end)

    render_patch(view, "/beam/runtime")
    render_click(view, "refresh", %{})
    render_hook(view, "request_graph", %{})
    assert Process.alive?(view.pid)

    assert {:ok, replacement_collector} =
             Supervisor.restart_child(BeamConsole.Supervisor, BeamConsole.Collector)

    refute replacement_collector == original_collector

    assert eventually(fn ->
             Process.alive?(view.pid) and BeamConsole.status().subscriber_count >= 1
           end)

    assert eventually(fn ->
             case BeamConsole.latest_snapshot() do
               %BeamConsole.Snapshot{collector_epoch: epoch} -> epoch != original_epoch
               nil -> false
             end
           end)

    replacement_snapshot = BeamConsole.latest_snapshot()
    replacement_epoch = replacement_snapshot.collector_epoch

    render_patch(view, "/beam")

    assert_push_event(
      view,
      "beam_console_graph",
      %{epoch: ^replacement_epoch, sequence: replacement_sequence},
      2_000
    )

    assert replacement_sequence >= 1
  end

  test "survives lifecycle recorder restart windows" do
    {:ok, view, _html} = live(build_conn(), "/beam/lifecycle")

    assert :ok =
             Supervisor.terminate_child(
               BeamConsole.Supervisor,
               BeamConsole.Lifecycle.Recorder
             )

    on_exit(&ensure_child_started/0)

    render_click(view, "toggle_recording", %{})
    render_patch(view, "/beam/runtime")
    assert Process.alive?(view.pid)

    assert {:ok, _pid} =
             Supervisor.restart_child(
               BeamConsole.Supervisor,
               BeamConsole.Lifecycle.Recorder
             )

    render_patch(view, "/beam/lifecycle")
    assert Process.alive?(view.pid)
  end

  test "clears lazy recorder demand when the collector restarts after a view closes" do
    BeamConsole.unsubscribe()
    {:ok, view, _html} = live(build_conn(), "/beam")

    assert eventually(fn -> BeamConsole.Recorder.status().demanded? end)
    assert :ok = Supervisor.terminate_child(BeamConsole.Supervisor, BeamConsole.Collector)

    on_exit(&ensure_child_started/0)
    GenServer.stop(view.pid, :normal)

    assert {:ok, _pid} =
             Supervisor.restart_child(BeamConsole.Supervisor, BeamConsole.Collector)

    assert eventually(fn -> not BeamConsole.Recorder.status().demanded? end)
  end

  test "renders categorized application folders and application details", %{snapshot: snapshot} do
    application = snapshot.applications |> Map.values() |> List.first()
    {:ok, view, _html} = live(build_conn(), "/beam?entity=#{application.id}")

    assert has_element?(view, "[id$='application-category-host']")
    assert has_element?(view, "[id$='application-category-dependencies']")
    assert has_element?(view, "[id$='application-category-otp']")
    assert has_element?(view, "#beam-console-application-detail")
  end

  test "keeps folder disclosure separate from node inspection", %{snapshot: snapshot} do
    runtime_node = snapshot.nodes |> Map.values() |> List.first()
    {:ok, view, _html} = live(build_conn(), "/beam")

    assert has_element?(view, "#disclose-#{runtime_node.id}")
    refute has_element?(view, "#disclose-#{runtime_node.id}[phx-click]")
    assert has_element?(view, ".beam-console-node-row > #select-#{runtime_node.id}")

    assert has_element?(
             view,
             "#select-#{runtime_node.id}[phx-click='select_entity'][aria-pressed='false']"
           )
  end

  defp contains_chart_points?(value) when is_struct(value) do
    false
  end

  defp contains_chart_points?(value) when is_map(value) do
    Enum.any?(value, fn
      {:points, points} when is_list(points) -> points != []
      {_key, nested} -> contains_chart_points?(nested)
    end)
  end

  defp contains_chart_points?(value) when is_list(value) do
    Enum.any?(value, &contains_chart_points?/1)
  end

  defp contains_chart_points?(_value) do
    false
  end

  defp theme_script_position(html) do
    {position, _length} = :binary.match(html, "/assets/theme/")
    position
  end

  defp stylesheet_position(html) do
    {position, _length} = :binary.match(html, "rel=\"stylesheet\"")
    position
  end

  defp ensure_child_started do
    Enum.each([BeamConsole.Lifecycle.Recorder, BeamConsole.Collector], fn child ->
      if is_nil(Process.whereis(child)) do
        Supervisor.restart_child(BeamConsole.Supervisor, child)
      end
    end)
  end

  defp eventually(function, attempts \\ 40)

  defp eventually(function, 0) do
    function.()
  end

  defp eventually(function, attempts) do
    if function.() do
      true
    else
      Process.sleep(25)
      eventually(function, attempts - 1)
    end
  end
end
