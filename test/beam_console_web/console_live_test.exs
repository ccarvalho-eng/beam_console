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
    {:ok, view, _html} = live(build_conn(), "/beam")

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
  end

  test "pushes live topology samples while the graph preserves positions", %{snapshot: snapshot} do
    {:ok, view, _html} = live(build_conn(), "/beam")
    assert_push_event(view, "beam_console_graph", %{sequence: _initial_sequence})

    send(view.pid, {:beam_console_snapshot, snapshot.sequence})

    assert_push_event(view, "beam_console_graph", %{sequence: _sequence})
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

  test "renders URL-backed lifecycle, activity, and runtime tabs" do
    {:ok, lifecycle, _html} = live(build_conn(), "/beam/lifecycle")
    assert has_element?(lifecycle, "#beam-console-tab-lifecycle[aria-current='page']")
    assert has_element?(lifecycle, "#beam-console-lifecycle-list")

    {:ok, activity, _html} = live(build_conn(), "/beam/activity")
    assert has_element?(activity, "#beam-console-tab-activity[aria-current='page']")

    {:ok, runtime, _html} = live(build_conn(), "/beam/runtime")
    assert has_element?(runtime, "#beam-console-tab-runtime[aria-current='page']")
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
  end

  test "renders categorized application folders and application details", %{snapshot: snapshot} do
    application = snapshot.applications |> Map.values() |> List.first()
    {:ok, view, _html} = live(build_conn(), "/beam?entity=#{application.id}")

    assert has_element?(view, "[id$='application-category-host']")
    assert has_element?(view, "[id$='application-category-dependencies']")
    assert has_element?(view, "[id$='application-category-otp']")
    assert has_element?(view, "#beam-console-application-detail")
  end
end
