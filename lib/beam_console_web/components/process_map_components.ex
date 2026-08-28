if Code.ensure_loaded?(Phoenix.Component) do
  defmodule BeamConsoleWeb.Components.ProcessMapComponents do
    @moduledoc "Renders the bounded process explorer and client-owned topology surface."

    use Phoenix.Component

    attr(:streams, :map, required: true)
    attr(:process_count, :integer, required: true)
    attr(:process_matching_count, :integer, required: true)
    attr(:process_omitted_count, :integer, required: true)
    attr(:selected_id, :string, default: nil)
    attr(:loading?, :boolean, default: false)
    attr(:edge_preset, :string, default: "supervision")

    @doc "Renders topology plus a streamed, explicitly capped process list."
    @spec process_map(map()) :: Phoenix.LiveView.Rendered.t()
    def process_map(assigns) do
      assigns =
        assigns
        |> assign(:connections_label, connections_label(assigns.edge_preset))
        |> assign(:topology_label, topology_label(assigns.edge_preset))

      ~H"""
      <main class="beam-console-main">
        <section class="beam-console-graph-stage" aria-label={@topology_label}>
          <div class="beam-console-graph-toolbar">
            <div>
              <span class="beam-console-kicker">Topology</span>
              <strong>Live {@connections_label} · positions preserved</strong>
            </div>
            <div class="beam-console-graph-controls">
              <div class="beam-console-edge-toggle" role="group" aria-label="Process map connections">
                <button
                  type="button"
                  class={@edge_preset == "supervision" && "is-active"}
                  phx-click="set_edges"
                  phx-value-edges="supervision"
                  aria-pressed={if(@edge_preset == "supervision", do: "true", else: "false")}
                >
                  Supervision
                </button>
                <button
                  type="button"
                  class={@edge_preset == "relationships" && "is-active"}
                  phx-click="set_edges"
                  phx-value-edges="relationships"
                  aria-pressed={if(@edge_preset == "relationships", do: "true", else: "false")}
                >
                  Links + monitors
                </button>
              </div>
              <div class="beam-console-legend" aria-label="Graph legend">
                <span data-graph-omitted aria-live="polite"></span>
                <span><i class="is-app"></i>Application</span>
                <span><i></i>Process</span>
              </div>
            </div>
          </div>
          <div
            id="beam-console-graph"
            class="beam-console-graph"
            phx-hook="BeamConsoleGraph"
            phx-update="ignore"
            role="img"
            aria-label="Interactive runtime process graph; use the process list for keyboard navigation"
          >
          </div>
        </section>

        <section class="beam-console-processes" aria-label="Process explorer">
          <div class="beam-console-panel-heading beam-console-process-heading">
            <div class="beam-console-heading-line">
              <h2>Processes</h2>
              <span class="beam-console-heading-count">
                {@process_count} / {@process_matching_count} shown
              </span>
            </div>
            <p>
              Latest bounded runtime sample
              <span :if={@process_omitted_count > 0}>· {@process_omitted_count} omitted</span>
            </p>
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
              aria-pressed={if(@selected_id == process.id, do: "true", else: "false")}
            >
              <span class="beam-console-process-label"><i aria-hidden="true"></i>{process.label}</span>
              <span class="beam-console-process-meta">{format_bytes(process.memory)}</span>
              <span class="beam-console-process-meta">{process.message_queue_len || 0}</span>
              <span class="beam-console-process-status">{process.status || "unknown"}</span>
            </button>
          </div>
        </section>
      </main>
      """
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

    defp connections_label("relationships") do
      "links and monitors"
    end

    defp connections_label(_preset) do
      "supervision"
    end

    defp topology_label("relationships") do
      "Process relationship topology"
    end

    defp topology_label(_preset) do
      "Supervision topology"
    end
  end
end
