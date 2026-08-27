if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule BeamConsoleWeb.ConsoleLive do
    @moduledoc """
    Coordinates the URL-backed Process Map, Lifecycle, Activity, and Runtime views.

    Runtime snapshots are transformed inside callbacks and never retained in
    the long-lived LiveView socket. Lists use bounded streams and browser-owned
    graph/chart surfaces receive bounded scalar payloads.
    """

    use BeamConsoleWeb, :live_view

    import BeamConsoleWeb.Components.InspectorComponents, only: [inspector: 1]
    import BeamConsoleWeb.Components.LifecycleComponents, only: [lifecycle: 1]
    import BeamConsoleWeb.Components.ProcessMapComponents, only: [process_map: 1]
    import BeamConsoleWeb.Components.ShellComponents, only: [header: 1]
    import BeamConsoleWeb.Components.StatsComponents, only: [activity: 1, runtime: 1]
    import BeamConsoleWeb.Components.TreeComponents, only: [runtime_tree: 1]

    alias BeamConsole.ApplicationTreeConfig
    alias BeamConsole.Recorder
    alias BeamConsole.Recorder.Status, as: RecorderStatus
    alias BeamConsole.Snapshot
    alias BeamConsoleWeb.Console.ActivityPresenter
    alias BeamConsoleWeb.Console.ApplicationTreePresenter
    alias BeamConsoleWeb.Console.DashboardPresenter
    alias BeamConsoleWeb.Console.LifecyclePresenter
    alias BeamConsoleWeb.Console.Params
    alias BeamConsoleWeb.Console.Paths
    alias BeamConsoleWeb.Console.RuntimePresenter
    alias BeamConsoleWeb.Graph

    @process_limit 150

    @impl true
    def mount(_params, _session, socket) do
      socket =
        socket
        |> assign(:page_title, "Process Map")
        |> assign(:params, %Params{})
        |> assign(:tab, :process_map)
        |> assign(:tab_paths, %{})
        |> assign(:query, "")
        |> assign(:selected_id, nil)
        |> assign(:selected, nil)
        |> assign(:detail, nil)
        |> assign(:graph_focus_id, nil)
        |> assign(:graph_refresh_pending?, false)
        |> assign(:loading?, true)
        |> assign(:sequence, 0)
        |> assign(:sampled_at, nil)
        |> assign(:status_label, "Sampling runtime")
        |> assign(:status_state, :loading)
        |> assign(:collector_status, nil)
        |> assign(:recorder_status, %RecorderStatus{})
        |> assign(:recorder_label, "Inactive")
        |> assign(:process_count, 0)
        |> assign(:process_matching_count, 0)
        |> assign(:process_omitted_count, 0)
        |> assign(:application_count, 0)
        |> assign(:application_categories, [])
        |> assign(:nodes, [])
        |> assign(:coverage_warnings, [])
        |> assign(:lifecycle_query, %BeamConsole.Recorder.Query{})
        |> assign(:activity_summary, empty_activity_summary())
        |> assign(:activity_has_samples?, false)
        |> assign(:runtime_summary, empty_runtime_summary())
        |> assign(:runtime_has_samples?, false)
        |> assign(:filter_form, to_form(%{"q" => ""}, as: :filters))
        |> stream(:processes, [])
        |> stream(:lifecycle_events, [])
        |> stream(:top_movers, [])

      if connected?(socket) do
        {:ok, snapshot} = BeamConsole.subscribe()

        if is_nil(snapshot) do
          _result = BeamConsole.refresh()
        end

        {:ok, socket}
      else
        {:ok, socket}
      end
    end

    @impl true
    def handle_params(raw_params, _uri, socket) do
      params = Params.normalize(raw_params, socket.assigns.live_action)

      socket =
        socket
        |> assign_navigation(params)
        |> maybe_refresh_view()

      {:noreply, socket}
    end

    @impl true
    def handle_event("search", %{"filters" => %{"q" => query}}, socket) when is_binary(query) do
      params = %{socket.assigns.params | query: String.slice(query, 0, 120)}
      {:noreply, push_patch(socket, to: current_path(socket, params))}
    end

    def handle_event("search", _params, socket) do
      {:noreply, socket}
    end

    def handle_event("select_entity", %{"id" => entity_id}, socket)
        when is_binary(entity_id) and entity_id != "" do
      snapshot = BeamConsole.latest_snapshot()

      selected_id =
        if DashboardPresenter.valid_selection?(snapshot, entity_id), do: entity_id, else: nil

      params = %{socket.assigns.params | selected_id: selected_id}
      {:noreply, push_patch(socket, to: current_path(socket, params))}
    end

    def handle_event("select_entity", _params, socket) do
      {:noreply, socket}
    end

    def handle_event("request_graph", _params, socket) do
      {:noreply, push_latest_graph(socket)}
    end

    def handle_event("refresh", _params, socket) do
      case BeamConsole.refresh() do
        :ok -> {:noreply, assign(socket, :graph_refresh_pending?, true)}
        {:error, :rate_limited} -> {:noreply, socket}
      end
    end

    def handle_event("toggle_recording", _params, socket) do
      status =
        case socket.assigns.recorder_status.activity do
          :recording -> Recorder.pause()
          _other -> Recorder.resume()
        end

      socket =
        socket
        |> assign_recorder_status(status)
        |> load_lifecycle()
        |> load_stats()

      {:noreply, socket}
    end

    @impl true
    def handle_info({:beam_console_snapshot, sequence}, socket) do
      socket =
        socket
        |> refresh_view(BeamConsole.latest_snapshot())
        |> assign(:graph_refresh_pending?, false)

      :ok = BeamConsole.acknowledge(sequence)
      {:noreply, socket}
    end

    @impl true
    def render(assigns) do
      ~H"""
      <div id="beam-console" class="beam-console-shell" phx-hook="BeamConsoleTheme">
        <div class="beam-console-frame">
          <.header
            page_title={@page_title}
            status_label={@status_label}
            status_state={@status_state}
            filter_form={@filter_form}
            tab={@tab}
            tab_paths={@tab_paths}
            recorder_activity={@recorder_status.activity}
            refresh_pending?={@graph_refresh_pending?}
          />

          <.runtime_tree
            nodes={@nodes}
            categories={@application_categories}
            application_count={@application_count}
            selected_id={@selected_id}
            coverage_warnings={@coverage_warnings}
          />

          <.process_map
            :if={@tab == :process_map}
            streams={@streams}
            process_count={@process_count}
            process_matching_count={@process_matching_count}
            process_omitted_count={@process_omitted_count}
            selected_id={@selected_id}
            loading?={@loading?}
          />

          <.lifecycle
            :if={@tab == :lifecycle}
            streams={@streams}
            recorder_status={@recorder_status}
            recorder_label={@recorder_label}
            lifecycle_query={@lifecycle_query}
            selected_id={@selected_id}
          />

          <.activity
            :if={@tab == :activity}
            streams={@streams}
            summary={@activity_summary}
            has_samples?={@activity_has_samples?}
          />
          <.runtime
            :if={@tab == :runtime}
            summary={@runtime_summary}
            has_samples?={@runtime_has_samples?}
          />

          <.inspector selected={@selected} detail={@detail} />
        </div>
      </div>
      """
    end

    defp assign_navigation(socket, params) do
      tab_paths =
        Map.new([:process_map, :lifecycle, :activity, :runtime], fn tab ->
          {tab, Paths.path(socket.assigns.prefix, tab, params)}
        end)

      socket
      |> assign(:params, params)
      |> assign(:tab, params.tab)
      |> assign(:page_title, page_title(params.tab))
      |> assign(:tab_paths, tab_paths)
      |> assign(:query, params.query)
      |> assign(:selected_id, params.selected_id)
      |> assign(:filter_form, to_form(%{"q" => params.query}, as: :filters))
    end

    defp maybe_refresh_view(socket) do
      if connected?(socket) do
        refresh_view(socket, BeamConsole.latest_snapshot())
      else
        socket
      end
    end

    defp refresh_view(socket, nil) do
      socket
      |> assign(:loading?, true)
      |> assign(:sequence, 0)
      |> assign(:sampled_at, nil)
      |> assign(:selected, nil)
      |> assign(:detail, nil)
      |> assign(:nodes, [])
      |> assign(:application_categories, [])
      |> assign(:application_count, 0)
      |> assign(:process_count, 0)
      |> assign(:process_matching_count, 0)
      |> assign(:process_omitted_count, 0)
      |> assign(:coverage_warnings, [])
      |> assign_health()
      |> load_lifecycle()
      |> load_stats()
      |> stream(:processes, [], reset: true)
    end

    defp refresh_view(socket, %Snapshot{} = snapshot) do
      process_result =
        DashboardPresenter.process_result(snapshot, socket.assigns.query, @process_limit)

      selected = DashboardPresenter.selection(snapshot, socket.assigns.selected_id)
      detail = selected_detail(snapshot, selected)
      graph_focus_id = stable_graph_focus(snapshot, socket.assigns.graph_focus_id)
      categories = ApplicationTreePresenter.present(snapshot, ApplicationTreeConfig.load())

      socket =
        socket
        |> assign(:loading?, false)
        |> assign(:sequence, snapshot.sequence)
        |> assign(:sampled_at, snapshot.sampled_at)
        |> assign(:selected, selected)
        |> assign(:detail, detail)
        |> assign(:nodes, DashboardPresenter.nodes(snapshot))
        |> assign(:application_categories, categories)
        |> assign(:application_count, map_size(snapshot.applications))
        |> assign(:process_count, length(process_result.items))
        |> assign(:process_matching_count, process_result.matching_count)
        |> assign(:process_omitted_count, process_result.omitted_count)
        |> assign(:graph_focus_id, graph_focus_id)
        |> assign(:coverage_warnings, snapshot.coverage.warnings)
        |> assign_health()
        |> load_lifecycle()
        |> load_stats()
        |> stream(:processes, process_result.items, reset: true)

      push_graph(socket, snapshot)
    end

    defp assign_health(socket) do
      collector_status = BeamConsole.status()
      recorder_status = Recorder.status()

      {status_label, status_state} =
        cond do
          collector_status.stale? -> {"Stale · sample #{collector_status.sequence}", :stale}
          collector_status.sequence == 0 -> {"Sampling runtime", :loading}
          true -> {"Live · sample #{collector_status.sequence}", :live}
        end

      socket
      |> assign(:collector_status, collector_status)
      |> assign(:status_label, status_label)
      |> assign(:status_state, status_state)
      |> assign_recorder_status(recorder_status)
    end

    defp assign_recorder_status(socket, recorder_status) do
      socket
      |> assign(:recorder_status, recorder_status)
      |> assign(:recorder_label, LifecyclePresenter.activity_label(recorder_status))
    end

    defp load_lifecycle(socket) do
      if socket.assigns.tab == :lifecycle do
        query = Recorder.events(LifecyclePresenter.query_options(socket.assigns.params))
        rows = LifecyclePresenter.rows(query, socket.assigns.query)

        socket
        |> assign(:lifecycle_query, query)
        |> stream(:lifecycle_events, rows, reset: true)
      else
        socket
      end
    end

    defp load_stats(%{assigns: %{tab: :activity}} = socket) do
      result = stats_query(socket)
      presentation = ActivityPresenter.present(result, socket.assigns.sequence)
      has_samples? = Enum.count(result.items, & &1.activity) >= 2

      socket
      |> assign(:activity_summary, presentation.summary)
      |> assign(:activity_has_samples?, has_samples?)
      |> stream(:top_movers, presentation.movers, reset: true)
      |> push_event("beam_console_charts", %{
        revision: socket.assigns.sequence,
        charts: presentation.charts
      })
    end

    defp load_stats(%{assigns: %{tab: :runtime}} = socket) do
      result = stats_query(socket)
      presentation = RuntimePresenter.present(result, socket.assigns.sequence)
      has_samples? = Enum.any?(result.items, & &1.runtime)

      socket
      |> assign(:runtime_summary, presentation.summary)
      |> assign(:runtime_has_samples?, has_samples?)
      |> push_event("beam_console_charts", %{
        revision: socket.assigns.sequence,
        charts: presentation.charts
      })
    end

    defp load_stats(socket) do
      socket
    end

    defp stats_query(socket) do
      window_ms = Params.window_ms(socket.assigns.params)
      Recorder.samples(since_ms: System.system_time(:millisecond) - window_ms)
    end

    defp selected_detail(_snapshot, %{kind: kind}) when kind != :process do
      nil
    end

    defp selected_detail(snapshot, %{id: selected_id, kind: :process}) do
      case BeamConsole.detail(snapshot, selected_id) do
        {:ok, detail} -> detail
        {:error, _reason} -> nil
      end
    end

    defp selected_detail(_snapshot, _selected) do
      nil
    end

    defp push_latest_graph(socket) do
      case BeamConsole.latest_snapshot() do
        %Snapshot{} = snapshot -> push_graph(socket, snapshot)
        nil -> socket
      end
    end

    defp push_graph(%{assigns: %{tab: :process_map}} = socket, snapshot) do
      payload = Graph.payload(snapshot, socket.assigns.selected_id, socket.assigns.graph_focus_id)
      push_event(socket, "beam_console_graph", payload)
    end

    defp push_graph(socket, _snapshot) do
      socket
    end

    defp stable_graph_focus(snapshot, focus_id) do
      case Map.get(snapshot.index, focus_id) do
        {:application, _application} -> focus_id
        _other -> Graph.default_focus_id(snapshot)
      end
    end

    defp current_path(socket, params) do
      Paths.path(socket.assigns.prefix, socket.assigns.tab, params)
    end

    defp page_title(:process_map) do
      "Process Map"
    end

    defp page_title(:lifecycle) do
      "Lifecycle"
    end

    defp page_title(:activity) do
      "Activity"
    end

    defp page_title(:runtime) do
      "Runtime"
    end

    defp empty_activity_summary do
      %{reductions_per_second: 0, mailbox_delta: 0, memory_delta: 0, omitted: 0}
    end

    defp empty_runtime_summary do
      %{
        process_count: 0,
        supervisor_count: 0,
        ets_count: 0,
        run_queue: nil,
        collector_partial?: false,
        omitted: 0
      }
    end
  end
end
