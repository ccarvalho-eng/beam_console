if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule BeamConsoleWeb.ConsoleLive do
    @moduledoc """
    Renders the live process map, searchable runtime tree, and safe inspector.

    The LiveView subscribes to the shared collector and keeps entity selection
    URL-backed so a process can remain inspectable as an observed tombstone
    after it exits.
    """

    use BeamConsoleWeb, :live_view

    alias BeamConsole.Snapshot
    alias BeamConsoleWeb.Graph

    @process_limit 150

    @impl true
    def mount(_params, _session, socket) do
      snapshot = BeamConsole.latest_snapshot()

      socket =
        socket
        |> assign(:page_title, "Process Map")
        |> assign(:query, "")
        |> assign(:selected_id, nil)
        |> assign(:selected, nil)
        |> assign(:detail, nil)
        |> assign(:graph_focus_id, nil)
        |> assign(:graph_refresh_pending?, false)
        |> assign(:snapshot, snapshot)
        |> assign(:loading?, is_nil(snapshot))
        |> assign(:process_count, 0)
        |> assign(:applications, [])
        |> assign(:nodes, [])
        |> assign(:coverage_warnings, [])
        |> assign(:filter_form, to_form(%{"q" => ""}, as: :filters))
        |> stream(:processes, [])

      if connected?(socket) do
        {:ok, latest} = BeamConsole.subscribe()
        socket = load_snapshot(socket, latest || snapshot)

        if is_nil(latest), do: BeamConsole.refresh()

        {:ok, socket}
      else
        {:ok, load_snapshot(socket, snapshot)}
      end
    end

    @impl true
    def handle_params(params, _uri, socket) do
      query = Map.get(params, "q", "") |> String.slice(0, 120)
      selected_id = Map.get(params, "entity")

      socket =
        socket
        |> assign(:query, query)
        |> assign(:selected_id, selected_id)
        |> assign(:filter_form, to_form(%{"q" => query}, as: :filters))
        |> load_snapshot(BeamConsole.latest_snapshot())
        |> load_selection(selected_id)

      {:noreply, push_graph(socket)}
    end

    @impl true
    def handle_event("search", %{"filters" => %{"q" => query}}, socket) do
      path = console_path(socket, query, socket.assigns.selected_id)
      {:noreply, push_patch(socket, to: path)}
    end

    def handle_event("select_entity", %{"id" => entity_id}, socket)
        when is_binary(entity_id) do
      selected_id =
        if socket.assigns.snapshot && Map.has_key?(socket.assigns.snapshot.index, entity_id) do
          entity_id
        end

      path = console_path(socket, socket.assigns.query, selected_id)
      {:noreply, push_patch(socket, to: path)}
    end

    def handle_event("select_entity", _params, socket) do
      {:noreply, socket}
    end

    def handle_event("request_graph", _params, socket) do
      {:noreply, push_graph(socket)}
    end

    def handle_event("refresh", _params, socket) do
      BeamConsole.refresh()
      {:noreply, assign(socket, :graph_refresh_pending?, true)}
    end

    @impl true
    def handle_info({:beam_console_snapshot, _sequence, _diff}, socket) do
      socket =
        socket
        |> load_snapshot(BeamConsole.latest_snapshot())
        |> load_selection(socket.assigns.selected_id)
        |> assign(:graph_refresh_pending?, false)
        |> push_graph()

      {:noreply, socket}
    end

    @impl true
    def render(assigns) do
      ~H"""
      <div id="beam-console" class="beam-console-shell" phx-hook="BeamConsoleTheme">
        <div class="beam-console-frame">
          <header class="beam-console-header">
            <div class="beam-console-brand">
              <div class="beam-console-mark" aria-hidden="true">
                <svg viewBox="0 0 24 24" fill="none">
                  <circle cx="6" cy="6" r="2.25" />
                  <circle cx="18" cy="7" r="2.25" />
                  <circle cx="12" cy="18" r="2.25" />
                  <path d="M7.9 7.15 10.8 16M16.1 8.2 13.2 16M8.2 6.2l7.5.6" />
                </svg>
              </div>
              <div>
                <p class="beam-console-eyebrow">BeamConsole</p>
                <h1 class="beam-console-title">Process Map</h1>
              </div>
            </div>

            <div class="beam-console-actions">
              <span class={["beam-console-status", @loading? && "is-loading"]}>
                <%= if @snapshot do %>
                  Live · sample {@snapshot.sequence}
                <% else %>
                  Sampling runtime
                <% end %>
              </span>
              <.form
                for={@filter_form}
                id="beam-console-search"
                class="beam-console-search-form"
                phx-change="search"
              >
                <svg class="beam-console-search-icon" viewBox="0 0 24 24" fill="none" aria-hidden="true">
                  <circle cx="11" cy="11" r="6.5" />
                  <path d="m16 16 4 4" />
                </svg>
                <input
                  id="beam-console-query"
                  class="beam-console-search"
                  type="search"
                  name={@filter_form[:q].name}
                  value={@filter_form[:q].value}
                  placeholder="Search processes"
                  phx-debounce="250"
                  autocomplete="off"
                />
              </.form>
              <button
                id="beam-console-refresh"
                class={[
                  "beam-console-icon-button",
                  @graph_refresh_pending? && "is-pending"
                ]}
                phx-click="refresh"
                aria-label="Refresh runtime sample"
                data-tooltip="Refresh sample"
              >
                <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
                  <path d="M20 7v5h-5M4 17v-5h5" />
                  <path d="M18.4 9A7 7 0 0 0 6.2 6.8L4 9M5.6 15A7 7 0 0 0 17.8 17.2L20 15" />
                </svg>
              </button>
              <div
                id="beam-console-theme-switcher"
                class="beam-console-theme-switcher"
                aria-label="Theme"
              >
                <button
                  type="button"
                  class="beam-console-theme-button"
                  data-beam-console-theme="system"
                  aria-label="Use system theme"
                  title="Use system theme"
                >
                  <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
                    <rect x="3" y="4" width="18" height="13" rx="2" />
                    <path d="M8 21h8M12 17v4" />
                  </svg>
                </button>
                <button
                  type="button"
                  class="beam-console-theme-button"
                  data-beam-console-theme="light"
                  aria-label="Use light theme"
                  title="Use light theme"
                >
                  <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
                    <circle cx="12" cy="12" r="3.5" />
                    <path d="M12 2v2M12 20v2M4.93 4.93l1.42 1.42M17.65 17.65l1.42 1.42M2 12h2M20 12h2M4.93 19.07l1.42-1.42M17.65 6.35l1.42-1.42" />
                  </svg>
                </button>
                <button
                  type="button"
                  class="beam-console-theme-button"
                  data-beam-console-theme="dark"
                  aria-label="Use dark theme"
                  title="Use dark theme"
                >
                  <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
                    <path d="M20 15.2A8.2 8.2 0 0 1 8.8 4a8.2 8.2 0 1 0 11.2 11.2Z" />
                  </svg>
                </button>
              </div>
            </div>
          </header>

          <aside class="beam-console-sidebar" aria-label="Runtime hierarchy">
            <div class="beam-console-panel-heading">
              <div class="beam-console-heading-line">
                <h2>Runtime</h2>
                <span class="beam-console-heading-count">{length(@applications)} apps</span>
              </div>
              <p>Nodes and started applications</p>
            </div>

            <div :for={warning <- @coverage_warnings} class="beam-console-warning">{warning}</div>

            <ul id="beam-console-runtime-tree" class="beam-console-list" phx-hook="BeamConsoleTree">
              <li :for={runtime_node <- @nodes}>
                <details
                  id={"tree-#{runtime_node.id}"}
                  class="beam-console-tree-branch"
                  open
                >
                  <summary
                    id={"select-#{runtime_node.id}"}
                    class={[
                      "beam-console-link beam-console-tree-summary",
                      @selected_id == runtime_node.id && "is-selected"
                    ]}
                    phx-click="select_entity"
                    phx-value-id={runtime_node.id}
                  >
                    <span class="beam-console-link-label">
                      <span class="beam-console-tree-caret" aria-hidden="true"></span>
                      <span class="beam-console-node-dot"></span>
                      {runtime_node.name}
                    </span>
                    <span class="beam-console-count">
                      {if(runtime_node.inspectable?, do: "local", else: "inventory")}
                    </span>
                  </summary>

                  <ul :if={runtime_node.inspectable?}>
                    <li :for={application <- @applications}>
                      <button
                        id={"select-#{application.id}"}
                        class={[
                          "beam-console-link",
                          @selected_id == application.id && "is-selected"
                        ]}
                        phx-click="select_entity"
                        phx-value-id={application.id}
                      >
                        <span class="beam-console-link-label">
                          {application.name}
                        </span>
                        <span class="beam-console-count">app</span>
                      </button>
                    </li>
                  </ul>
                </details>
              </li>
            </ul>
          </aside>

          <main class="beam-console-main">
            <section class="beam-console-graph-stage" aria-label="Supervision topology">
              <div class="beam-console-graph-toolbar">
                <div>
                  <span class="beam-console-kicker">Topology</span>
                  <strong>Live supervision · positions preserved</strong>
                </div>
                <div class="beam-console-legend" aria-label="Graph legend">
                  <span><i class="is-app"></i>Application</span>
                  <span><i></i>Process</span>
                </div>
              </div>
              <div
                id="beam-console-graph"
                class="beam-console-graph"
                phx-hook="BeamConsoleGraph"
                phx-update="ignore"
                role="img"
                aria-label="Interactive runtime supervision graph"
              >
              </div>
            </section>

            <section class="beam-console-processes" aria-label="Process explorer">
              <div class="beam-console-panel-heading beam-console-process-heading">
                <div class="beam-console-heading-line">
                  <h2>Processes</h2>
                  <span class="beam-console-heading-count">{@process_count} shown</span>
                </div>
                <p>Latest bounded runtime sample</p>
              </div>

              <div :if={@process_count > 0} class="beam-console-process-columns" aria-hidden="true">
                <span>Process</span><span>Memory</span><span>Mailbox</span><span>Status</span>
              </div>

              <div :if={@process_count == 0} class="beam-console-empty">
                <div class="beam-console-empty-mark" aria-hidden="true">···</div>
                <%= if @loading? do %>
                  Collecting the first runtime sample…
                <% else %>
                  No processes match this search.
                <% end %>
              </div>

              <div id="beam-console-process-list" phx-update="stream">
                <button
                  :for={{dom_id, process} <- @streams.processes}
                  id={dom_id}
                  class={[
                    "beam-console-process-row",
                    @selected_id == process.id && "is-selected"
                  ]}
                  phx-click="select_entity"
                  phx-value-id={process.id}
                >
                  <span class="beam-console-process-label">
                    <i aria-hidden="true"></i>{process.label}
                  </span>
                  <span class="beam-console-process-meta">{format_bytes(process.memory)}</span>
                  <span class="beam-console-process-meta">{process.message_queue_len || 0}</span>
                  <span class="beam-console-process-status">{process.status || "unknown"}</span>
                </button>
              </div>
            </section>
          </main>

          <aside class="beam-console-inspector" aria-label="Selected entity details">
            <div class="beam-console-panel-heading">
              <div class="beam-console-heading-line">
                <h2>Inspector</h2>
                <span class="beam-console-heading-count">read only</span>
              </div>
              <p>Allowlisted runtime metadata</p>
            </div>

            <%= if @detail do %>
              <div id="beam-console-detail" class="beam-console-detail">
                <div class="beam-console-detail-heading">
                  <div>
                    <p class="beam-console-kicker">Process</p>
                    <h3>{@detail.label}</h3>
                    <p class="beam-console-detail-pid">{@detail.pid_text}</p>
                  </div>
                  <span class="beam-console-detail-status">{@detail.status || "unknown"}</span>
                </div>

                <div class="beam-console-metrics">
                  <div><span>Memory</span><strong>{format_bytes(@detail.memory)}</strong></div>
                  <div>
                    <span>Reductions</span><strong>{format_integer(@detail.reductions)}</strong>
                  </div>
                  <div><span>Mailbox</span><strong>{@detail.message_queue_len || 0}</strong></div>
                </div>

                <dl class="beam-console-fields">
                  <dt>Application</dt><dd>{@detail.application || "unattributed"}</dd>
                  <dt>Module</dt><dd>{@detail.module || "unknown"}</dd>
                  <dt>Current</dt><dd>{@detail.current_function || "unknown"}</dd>
                </dl>

                <.relation_list title="Links" values={@detail.links} />
                <.relation_list title="Monitors" values={@detail.monitors} />
                <.relation_list title="Monitored by" values={@detail.monitored_by} />
              </div>
            <% else %>
              <div id="beam-console-detail-empty" class="beam-console-empty">
                <div class="beam-console-empty-mark" aria-hidden="true">⌁</div>
                <%= if @selected do %>
                  {@selected.label}<br />Details are unavailable or this entity is inventory-only.
                <% else %>
                  Select a process, application, or node to inspect it.
                <% end %>
              </div>
            <% end %>
          </aside>
        </div>
      </div>
      """
    end

    attr(:title, :string, required: true)
    attr(:values, :list, required: true)

    defp relation_list(assigns) do
      ~H"""
      <section :if={@values != []} class="beam-console-relation">
        <h4>{@title}</h4>
        <ul>
          <li :for={value <- @values}>{value}</li>
        </ul>
      </section>
      """
    end

    defp load_snapshot(socket, nil) do
      socket
      |> assign(:loading?, true)
      |> assign(:snapshot, nil)
      |> assign(:applications, [])
      |> assign(:nodes, [])
      |> assign(:process_count, 0)
      |> assign(:coverage_warnings, [])
      |> stream(:processes, [], reset: true)
    end

    defp load_snapshot(socket, %Snapshot{} = snapshot) do
      processes = BeamConsole.search(snapshot, socket.assigns.query, @process_limit)
      graph_focus_id = stable_graph_focus(snapshot, socket.assigns.graph_focus_id)

      socket
      |> assign(:loading?, false)
      |> assign(:snapshot, snapshot)
      |> assign(:applications, snapshot.applications |> Map.values() |> Enum.sort_by(& &1.name))
      |> assign(:nodes, snapshot.nodes |> Map.values() |> Enum.sort_by(&{&1.kind, &1.name}))
      |> assign(:process_count, length(processes))
      |> assign(:graph_focus_id, graph_focus_id)
      |> assign(:coverage_warnings, snapshot.coverage.warnings)
      |> stream(:processes, processes, reset: true)
    end

    defp load_selection(socket, nil) do
      socket
      |> assign(:selected, nil)
      |> assign(:detail, nil)
    end

    defp load_selection(%{assigns: %{snapshot: nil}} = socket, _selected_id) do
      socket
      |> assign(:selected, nil)
      |> assign(:detail, nil)
    end

    defp load_selection(socket, selected_id) do
      snapshot = socket.assigns.snapshot

      case Map.get(snapshot.index, selected_id) do
        {:process, _pid} ->
          process = Map.get(snapshot.processes, selected_id)

          detail =
            case BeamConsole.detail(snapshot, selected_id) do
              {:ok, value} -> value
              {:error, _reason} -> nil
            end

          socket
          |> assign(:selected, process)
          |> assign(:detail, detail)

        {:application, _application} ->
          application = Map.get(snapshot.applications, selected_id)

          socket
          |> assign(:selected, %{label: Atom.to_string(application.name)})
          |> assign(:detail, nil)

        {:node, _node_name} ->
          runtime_node = Map.get(snapshot.nodes, selected_id)

          socket
          |> assign(:selected, %{label: runtime_node.name})
          |> assign(:detail, nil)

        _other ->
          socket
          |> assign(:selected, %{label: "Unknown entity"})
          |> assign(:detail, nil)
      end
    end

    defp push_graph(%{assigns: %{snapshot: nil}} = socket) do
      socket
    end

    defp push_graph(socket) do
      payload =
        Graph.payload(
          socket.assigns.snapshot,
          socket.assigns.selected_id,
          socket.assigns.graph_focus_id
        )

      push_event(socket, "beam_console_graph", payload)
    end

    defp stable_graph_focus(snapshot, focus_id) do
      case Map.get(snapshot.index, focus_id) do
        {:application, _application} -> focus_id
        _other -> Graph.default_focus_id(snapshot)
      end
    end

    defp console_path(socket, query, selected_id) do
      params =
        %{}
        |> maybe_put("q", String.trim(query))
        |> maybe_put("entity", selected_id)

      suffix = if map_size(params) == 0, do: "", else: "?" <> URI.encode_query(params)
      String.trim_trailing(socket.assigns.prefix, "/") <> suffix
    end

    defp maybe_put(params, _key, nil) do
      params
    end

    defp maybe_put(params, _key, "") do
      params
    end

    defp maybe_put(params, key, value) do
      Map.put(params, key, value)
    end

    defp format_bytes(nil) do
      "—"
    end

    defp format_bytes(bytes) when bytes < 1_024 do
      "#{bytes} B"
    end

    defp format_bytes(bytes) do
      "#{Float.round(bytes / 1_024, 1)} KB"
    end

    defp format_integer(nil) do
      "—"
    end

    defp format_integer(value) do
      Integer.to_string(value)
    end
  end
end
