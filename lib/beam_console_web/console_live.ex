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
    alias BeamConsole.Recorder.Status, as: RecorderStatus
    alias BeamConsole.Recording.Control, as: RecordingControl
    alias BeamConsole.Recording.Status, as: RecordingStatus
    alias BeamConsole.Snapshot
    alias BeamConsoleWeb.Console.ActivityPresenter
    alias BeamConsoleWeb.Console.ApplicationTreePresenter
    alias BeamConsoleWeb.Console.CollectorClient
    alias BeamConsoleWeb.Console.DashboardPresenter
    alias BeamConsoleWeb.Console.LifecyclePresenter
    alias BeamConsoleWeb.Console.OrderedStream
    alias BeamConsoleWeb.Console.Params
    alias BeamConsoleWeb.Console.Paths
    alias BeamConsoleWeb.Console.RecorderClient
    alias BeamConsoleWeb.Console.RecordingControlClient
    alias BeamConsoleWeb.Console.RuntimePresenter
    alias BeamConsoleWeb.Console.SelectionState
    alias BeamConsoleWeb.Graph

    @process_limit 150
    @collector_retry_min_ms 100
    @collector_retry_max_ms 5_000

    @impl Phoenix.LiveView
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
        |> assign(:status_label, "Sampling runtime")
        |> assign(:status_state, :loading)
        |> assign(:collector_pid, nil)
        |> assign(:collector_epoch, nil)
        |> assign(:collector_monitor_ref, nil)
        |> assign(:collector_retry_attempt, 0)
        |> assign(:collector_retry_timer, nil)
        |> assign(:collector_retry_token, nil)
        |> assign(:recorder_status, %RecorderStatus{})
        |> assign(:recording_status, %RecordingStatus{paused?: false, revision: 0})
        |> assign(:recording_control_available?, false)
        |> assign(:recorder_label, "Inactive")
        |> assign(:process_count, 0)
        |> assign(:process_matching_count, 0)
        |> assign(:process_omitted_count, 0)
        |> assign(:application_count, 0)
        |> assign(:application_categories, [])
        |> assign(:nodes, [])
        |> assign(:coverage_warnings, [])
        |> assign(:lifecycle_meta, %{empty?: true, omitted: 0})
        |> assign(:activity_summary, empty_activity_summary())
        |> assign(:activity_has_samples?, false)
        |> assign(:runtime_summary, RuntimePresenter.empty_summary())
        |> assign(:runtime_has_samples?, false)
        |> assign(:process_stream_order, [])
        |> assign(:lifecycle_stream_ids, MapSet.new())
        |> assign(:mover_stream_order, [])
        |> assign(:filter_form, to_form(%{"q" => ""}, as: :filters))
        |> stream(:processes, [])
        |> stream(:lifecycle_events, [])
        |> stream(:top_movers, [])

      if connected?(socket) do
        {:ok, subscribe_collector(socket)}
      else
        {:ok, socket}
      end
    end

    @impl Phoenix.LiveView
    def handle_params(raw_params, _uri, socket) do
      params = Params.normalize(raw_params, socket.assigns.live_action)

      socket =
        socket
        |> assign_navigation(params)
        |> maybe_refresh_view()

      {:noreply, socket}
    end

    @impl Phoenix.LiveView
    def handle_event("search", %{"filters" => %{"q" => query}}, socket) when is_binary(query) do
      params = %{socket.assigns.params | query: String.slice(query, 0, 120)}
      {:noreply, push_patch(socket, to: current_path(socket, params))}
    end

    def handle_event("search", _params, socket) do
      {:noreply, socket}
    end

    def handle_event("select_entity", %{"id" => entity_id}, socket)
        when is_binary(entity_id) and entity_id != "" do
      case CollectorClient.latest_snapshot(socket.assigns.collector_pid) do
        {:ok, snapshot} ->
          selected_id =
            if DashboardPresenter.valid_selection?(snapshot, entity_id), do: entity_id, else: nil

          params = %{socket.assigns.params | selected_id: selected_id}
          {:noreply, push_patch(socket, to: current_path(socket, params))}

        {:error, reason} when reason in [:timeout, :unavailable] ->
          {:noreply, collector_unavailable(socket)}
      end
    end

    def handle_event("select_entity", _params, socket) do
      {:noreply, socket}
    end

    def handle_event("request_graph", _params, socket) do
      {:noreply, push_latest_graph(socket)}
    end

    def handle_event("set_edges", %{"edges" => edges}, socket)
        when edges in ["supervision", "relationships"] do
      params = %{socket.assigns.params | edges: edges}
      {:noreply, push_patch(socket, to: current_path(socket, params))}
    end

    def handle_event("set_edges", _params, socket) do
      {:noreply, socket}
    end

    def handle_event("refresh", _params, socket) do
      case CollectorClient.refresh(socket.assigns.collector_pid) do
        :ok ->
          {:noreply, assign(socket, :graph_refresh_pending?, true)}

        {:error, :rate_limited} ->
          {:noreply, socket}

        {:error, reason} when reason in [:timeout, :unavailable] ->
          {:noreply, collector_unavailable(socket)}
      end
    end

    def handle_event("toggle_recording", _params, socket) do
      result =
        case socket.assigns.recording_status.paused? do
          true -> RecordingControlClient.resume()
          false -> RecordingControlClient.pause()
        end

      case result do
        {:ok, status} ->
          socket =
            socket
            |> assign(:recording_status, status)
            |> assign(:recording_control_available?, true)
            |> assign_current_recorder_status()
            |> load_lifecycle()
            |> load_stats()

          {:noreply, socket}

        {:error, reason} when reason in [:timeout, :unavailable] ->
          {:noreply, assign(socket, :recording_control_available?, false)}
      end
    end

    @impl Phoenix.LiveView
    def handle_info(
          {RecordingControl, %RecordingStatus{} = status},
          socket
        ) do
      socket =
        socket
        |> assign(:recording_status, status)
        |> assign(:recording_control_available?, true)
        |> assign_current_recorder_status()
        |> load_lifecycle()
        |> load_stats()

      {:noreply, socket}
    end

    def handle_info({:beam_console_snapshot, sequence}, socket) do
      case CollectorClient.latest_snapshot(socket.assigns.collector_pid) do
        {:ok, snapshot} ->
          socket =
            socket
            |> refresh_view(snapshot)
            |> assign(:graph_refresh_pending?, false)

          _result = CollectorClient.acknowledge(socket.assigns.collector_pid, sequence)
          {:noreply, socket}

        {:error, reason} when reason in [:timeout, :unavailable] ->
          {:noreply, collector_unavailable(socket)}
      end
    end

    def handle_info(
          {:DOWN, reference, :process, _pid, _reason},
          %{assigns: %{collector_monitor_ref: reference}} = socket
        ) do
      socket =
        socket
        |> assign(:collector_pid, nil)
        |> assign(:collector_monitor_ref, nil)
        |> assign(:status_label, "Reconnecting collector")
        |> assign(:status_state, :stale)
        |> schedule_collector_retry()

      {:noreply, socket}
    end

    def handle_info(
          {:beam_console_resubscribe, token},
          %{assigns: %{collector_retry_token: token}} = socket
        ) do
      socket =
        socket
        |> assign(:collector_retry_timer, nil)
        |> assign(:collector_retry_token, nil)
        |> subscribe_collector()

      {:noreply, socket}
    end

    def handle_info({:beam_console_resubscribe, _stale_token}, socket) do
      {:noreply, socket}
    end

    @impl Phoenix.LiveView
    def render(assigns) do
      ~H"""
      <div id="beam-console" class="beam-console-shell" phx-hook="BeamConsoleTheme">
        <div
          id="beam-console-panels"
          class="beam-console-frame"
          phx-hook="BeamConsolePanels"
          data-beam-console-focus-key={"beam-console:focus:#{@prefix}"}
          data-beam-console-has-selection={if(is_nil(@selected), do: "false", else: "true")}
        >
          <.header
            page_title={@page_title}
            status_label={@status_label}
            status_state={@status_state}
            filter_form={@filter_form}
            tab={@tab}
            tab_paths={@tab_paths}
            recording_paused?={@recording_status.paused?}
            recording_control_available?={@recording_control_available?}
            refresh_pending?={@graph_refresh_pending?}
          />

          <span
            id="beam-console-focus-announcement"
            class="beam-console-visually-hidden"
            role="status"
            aria-live="polite"
            aria-atomic="true"
          ></span>
          <div id="beam-console-focus-bar" class="beam-console-focus-bar">
            <span class="beam-console-focus-label">Focus</span>
            <div class="beam-console-focus-actions">
              <button
                id="beam-console-focus-runtime"
                type="button"
                class="beam-console-icon-button"
                data-beam-console-panel-toggle="runtime"
                aria-controls="beam-console-runtime-panel"
                aria-expanded="false"
                aria-label="Open runtime hierarchy"
                data-tooltip="Runtime hierarchy"
              >
                <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
                  <path d="M4 6h6M4 12h10M4 18h16" />
                  <circle cx="13" cy="6" r="2" />
                  <circle cx="17" cy="12" r="2" />
                </svg>
              </button>
              <button
                id="beam-console-focus-inspector"
                type="button"
                class="beam-console-icon-button beam-console-focus-inspector"
                data-beam-console-panel-toggle="inspector"
                aria-controls="beam-console-inspector-panel"
                aria-expanded="false"
                aria-label="Open inspector"
                data-tooltip="Inspector"
              >
                <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
                  <circle cx="11" cy="11" r="6" />
                  <path d="m16 16 4 4M11 8v6M8 11h6" />
                </svg>
              </button>
              <button
                id="beam-console-focus-exit"
                type="button"
                class="beam-console-icon-button beam-console-focus-exit"
                data-beam-console-focus-toggle
                aria-label="Exit focus mode"
                aria-keyshortcuts="Escape"
                aria-pressed="false"
                data-tooltip="Exit focus mode (Esc)"
              >
                <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
                  <path d="M4 9h5V4M20 9h-5V4M20 15h-5v5M4 15h5v5" />
                </svg>
              </button>
            </div>
          </div>

          <.runtime_tree
            nodes={@nodes}
            categories={@application_categories}
            application_count={@application_count}
            selected_id={@selected_id}
            selected={@selected}
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
            edge_preset={@params.edges}
          />

          <.lifecycle
            :if={@tab == :lifecycle}
            streams={@streams}
            recorder_status={@recorder_status}
            recorder_label={@recorder_label}
            lifecycle_meta={@lifecycle_meta}
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
          <button
            type="button"
            class="beam-console-panel-backdrop"
            data-beam-console-panel-dismiss
            aria-label="Close runtime panels"
          ></button>
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

    defp subscribe_collector(socket) do
      socket = subscribe_recording_control(socket)

      case Process.whereis(BeamConsole.Collector) do
        collector when is_pid(collector) ->
          subscribe_to_collector(socket, collector)

        nil ->
          schedule_collector_retry(socket)
      end
    end

    defp subscribe_to_collector(socket, collector) do
      reference = Process.monitor(collector)

      case CollectorClient.subscribe(collector) do
        {:ok, snapshot} ->
          socket =
            socket
            |> cancel_collector_retry()
            |> assign(:collector_pid, collector)
            |> assign(:collector_monitor_ref, reference)
            |> assign(:collector_retry_attempt, 0)

          if is_nil(snapshot) do
            _result = CollectorClient.refresh(collector)
            socket
          else
            refresh_view(socket, snapshot)
          end

        {:error, reason} when reason in [:timeout, :unavailable] ->
          Process.demonitor(reference, [:flush])
          socket |> assign(:collector_pid, nil) |> schedule_collector_retry()
      end
    end

    defp schedule_collector_retry(%{assigns: %{collector_retry_timer: timer}} = socket)
         when is_reference(timer) do
      socket
    end

    defp schedule_collector_retry(socket) do
      attempt = min(socket.assigns.collector_retry_attempt + 1, 16)
      delay = min(@collector_retry_min_ms * Integer.pow(2, attempt - 1), @collector_retry_max_ms)
      token = make_ref()
      timer = Process.send_after(self(), {:beam_console_resubscribe, token}, delay)

      socket
      |> assign(:collector_retry_attempt, attempt)
      |> assign(:collector_retry_timer, timer)
      |> assign(:collector_retry_token, token)
    end

    defp cancel_collector_retry(%{assigns: %{collector_retry_timer: nil}} = socket) do
      socket
    end

    defp cancel_collector_retry(socket) do
      Process.cancel_timer(socket.assigns.collector_retry_timer)

      socket
      |> assign(:collector_retry_timer, nil)
      |> assign(:collector_retry_token, nil)
    end

    defp maybe_refresh_view(socket) do
      if connected?(socket) do
        case CollectorClient.latest_snapshot(socket.assigns.collector_pid) do
          {:ok, snapshot} ->
            refresh_view(socket, snapshot)

          {:error, reason} when reason in [:timeout, :unavailable] ->
            collector_unavailable(socket)
        end
      else
        socket
      end
    end

    defp refresh_view(socket, nil) do
      socket
      |> assign(:loading?, true)
      |> assign(:sequence, 0)
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
      |> reconcile_ordered_stream(:processes, [], :process_stream_order)
    end

    defp refresh_view(socket, %Snapshot{} = snapshot) do
      process_result =
        DashboardPresenter.process_result(snapshot, socket.assigns.query, @process_limit)

      {selected, detail} =
        SelectionState.resolve(
          snapshot,
          socket.assigns.selected_id,
          socket.assigns.selected,
          socket.assigns.detail
        )

      graph_focus_id = stable_graph_focus(snapshot, socket.assigns.graph_focus_id)
      categories = ApplicationTreePresenter.present(snapshot, ApplicationTreeConfig.load())

      socket =
        socket
        |> assign(:loading?, false)
        |> assign(:collector_epoch, snapshot.collector_epoch)
        |> assign(:sequence, snapshot.sequence)
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
        |> reconcile_ordered_stream(:processes, process_result.items, :process_stream_order)

      push_graph(socket, snapshot)
    end

    defp assign_health(socket) do
      collector_status =
        case CollectorClient.status(socket.assigns.collector_pid) do
          {:ok, status} -> status
          {:error, reason} when reason in [:timeout, :unavailable] -> nil
        end

      {status_label, status_state} =
        cond do
          is_nil(collector_status) -> {"Reconnecting collector", :stale}
          collector_status.stale? -> {"Stale · sample #{collector_status.sequence}", :stale}
          collector_status.sequence == 0 -> {"Sampling runtime", :loading}
          true -> {"Live · sample #{collector_status.sequence}", :live}
        end

      socket
      |> assign(:status_label, status_label)
      |> assign(:status_state, status_state)
      |> assign_current_recording_status()
      |> assign_current_recorder_status()
    end

    defp assign_current_recording_status(socket) do
      case RecordingControlClient.status() do
        {:ok, status} ->
          socket
          |> assign(:recording_status, status)
          |> assign(:recording_control_available?, true)

        {:error, reason} when reason in [:timeout, :unavailable] ->
          assign(socket, :recording_control_available?, false)
      end
    end

    defp subscribe_recording_control(socket) do
      case RecordingControlClient.subscribe() do
        {:ok, status} ->
          socket
          |> assign(:recording_status, status)
          |> assign(:recording_control_available?, true)

        {:error, reason} when reason in [:timeout, :unavailable] ->
          assign(socket, :recording_control_available?, false)
      end
    end

    defp assign_current_recorder_status(socket) do
      case RecorderClient.status() do
        {:ok, status} ->
          assign_recorder_status(socket, status)

        {:error, reason} when reason in [:timeout, :unavailable] ->
          assign_recorder_unavailable(socket)
      end
    end

    defp assign_recorder_status(socket, recorder_status) do
      recorder_status = reflect_control_pause(recorder_status, socket.assigns.recording_status)

      socket
      |> assign(:recorder_status, recorder_status)
      |> assign(:recorder_label, LifecyclePresenter.activity_label(recorder_status))
    end

    defp assign_recorder_unavailable(socket) do
      socket
      |> assign(:recorder_status, %RecorderStatus{})
      |> assign(:recorder_label, "Unavailable")
    end

    defp reflect_control_pause(recorder_status, %RecordingStatus{paused?: true}) do
      %{
        recorder_status
        | activity: :paused,
          active?: false,
          paused?: true,
          watched: 0,
          pending_correlations: 0
      }
    end

    defp reflect_control_pause(recorder_status, %RecordingStatus{paused?: false}) do
      recorder_status
    end

    defp load_lifecycle(socket) do
      if socket.assigns.tab == :lifecycle do
        case RecorderClient.events(LifecyclePresenter.query_options(socket.assigns.params)) do
          {:ok, query} ->
            rows = LifecyclePresenter.rows(query, socket.assigns.query)

            socket
            |> assign(:lifecycle_meta, %{
              empty?: rows == [],
              omitted: LifecyclePresenter.omitted_count(query)
            })
            |> reconcile_stream(:lifecycle_events, rows, :lifecycle_stream_ids)

          {:error, _reason} ->
            socket
        end
      else
        socket
      end
    end

    defp load_stats(%{assigns: %{tab: :activity}} = socket) do
      case stats_query(socket) do
        {:ok, result} -> load_activity_stats(socket, result)
        {:error, _reason} -> socket
      end
    end

    defp load_stats(%{assigns: %{tab: :runtime}} = socket) do
      case stats_query(socket) do
        {:ok, result} -> load_runtime_stats(socket, result)
        {:error, _reason} -> socket
      end
    end

    defp load_stats(socket) do
      socket
    end

    defp stats_query(socket) do
      window_ms = Params.window_ms(socket.assigns.params)
      RecorderClient.samples(since_ms: System.system_time(:millisecond) - window_ms)
    end

    defp load_activity_stats(socket, result) do
      presentation = ActivityPresenter.present(result, socket.assigns.sequence)
      has_samples? = Enum.count(result.items, & &1.activity) >= 2

      socket
      |> assign(:activity_summary, presentation.summary)
      |> assign(:activity_has_samples?, has_samples?)
      |> reconcile_ordered_stream(:top_movers, presentation.movers, :mover_stream_order)
      |> push_event("beam_console_charts", %{
        epoch: socket.assigns.collector_epoch,
        revision: socket.assigns.sequence,
        charts: presentation.charts
      })
    end

    defp load_runtime_stats(socket, result) do
      presentation = RuntimePresenter.present(result, socket.assigns.sequence)
      has_samples? = Enum.any?(result.items, & &1.runtime)

      socket
      |> assign(:runtime_summary, presentation.summary)
      |> assign(:runtime_has_samples?, has_samples?)
      |> push_event("beam_console_charts", %{
        epoch: socket.assigns.collector_epoch,
        revision: socket.assigns.sequence,
        charts: presentation.charts
      })
    end

    defp push_latest_graph(socket) do
      case CollectorClient.latest_snapshot(socket.assigns.collector_pid) do
        {:ok, %Snapshot{} = snapshot} ->
          push_graph(socket, snapshot)

        {:ok, nil} ->
          socket

        {:error, reason} when reason in [:timeout, :unavailable] ->
          collector_unavailable(socket)
      end
    end

    defp collector_unavailable(socket) do
      demonitor_collector(socket.assigns.collector_monitor_ref)

      socket
      |> assign(:collector_pid, nil)
      |> assign(:collector_monitor_ref, nil)
      |> assign(:status_label, "Reconnecting collector")
      |> assign(:status_state, :stale)
      |> schedule_collector_retry()
    end

    defp demonitor_collector(reference) when is_reference(reference) do
      Process.demonitor(reference, [:flush])
    end

    defp demonitor_collector(_reference) do
      :ok
    end

    defp push_graph(%{assigns: %{tab: :process_map}} = socket, snapshot) do
      payload =
        Graph.payload(snapshot,
          selected_id: socket.assigns.selected_id,
          focus_id: socket.assigns.graph_focus_id,
          edge_preset: socket.assigns.params.edges,
          selected_detail: socket.assigns.detail
        )

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

    defp reconcile_stream(socket, stream_name, items, ids_assign) do
      previous_ids = Map.fetch!(socket.assigns, ids_assign)
      current_ids = MapSet.new(items, & &1.id)

      socket =
        previous_ids
        |> MapSet.difference(current_ids)
        |> Enum.reduce(socket, fn id, acc ->
          stream_delete(acc, stream_name, %{id: id})
        end)

      socket =
        items
        |> Enum.with_index()
        |> Enum.reduce(socket, fn {item, index}, acc ->
          stream_insert(acc, stream_name, item, at: index)
        end)

      assign(socket, ids_assign, current_ids)
    end

    defp reconcile_ordered_stream(socket, stream_name, items, order_assign) do
      previous_ids = Map.fetch!(socket.assigns, order_assign)
      current_ids = OrderedStream.ids(items)

      socket =
        if OrderedStream.reordered?(previous_ids, current_ids) do
          reorder_stream(socket, stream_name, previous_ids, items)
        else
          update_stream(socket, stream_name, items)
        end

      assign(socket, order_assign, current_ids)
    end

    defp reorder_stream(socket, stream_name, previous_ids, items) do
      socket =
        Enum.reduce(previous_ids, socket, fn id, acc ->
          stream_delete(acc, stream_name, %{id: id})
        end)

      items
      |> Enum.with_index()
      |> Enum.reduce(socket, fn {item, index}, acc ->
        stream_insert(acc, stream_name, item, at: index)
      end)
    end

    defp update_stream(socket, stream_name, items) do
      Enum.reduce(items, socket, fn item, acc ->
        stream_insert(acc, stream_name, item)
      end)
    end

    defp empty_activity_summary do
      %{reductions_per_second: 0, mailbox_delta: 0, memory_delta: 0, omitted: 0}
    end
  end
end
