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
        assert_receive {:beam_console_snapshot, _sequence, _diff}, 2_000
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

    send(view.pid, {:beam_console_snapshot, snapshot.sequence, %{}})

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
end
