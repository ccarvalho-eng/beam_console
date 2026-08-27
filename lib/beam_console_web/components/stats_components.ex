if Code.ensure_loaded?(Phoenix.Component) do
  defmodule BeamConsoleWeb.Components.StatsComponents do
    @moduledoc "Renders accessible Activity and Runtime summaries with client-owned SVG charts."

    use Phoenix.Component

    attr(:streams, :map, required: true)
    attr(:summary, :map, required: true)
    attr(:has_samples?, :boolean, default: false)

    @doc "Renders aggregate activity rates, ranked process movers, and three bounded charts."
    @spec activity(map()) :: Phoenix.LiveView.Rendered.t()
    def activity(assigns) do
      ~H"""
      <main class="beam-console-main beam-console-tab-main">
        <section class="beam-console-tab-stage" aria-label="Process activity">
          <div class="beam-console-graph-toolbar">
            <div>
              <span class="beam-console-kicker">Activity</span><strong>Work and pressure between samples</strong>
            </div>
          </div>

          <div class="beam-console-recorder-summary">
            <div>
              <span>Reductions / sec</span><strong>{format_number(@summary.reductions_per_second)}</strong>
            </div>
            <div><span>Mailbox change</span><strong>{signed(@summary.mailbox_delta)}</strong></div>
            <div><span>Memory change</span><strong>{signed_bytes(@summary.memory_delta)}</strong></div>
            <div><span>Omitted</span><strong>{@summary.omitted}</strong></div>
          </div>

          <div class="beam-console-tab-scroll">
            <.chart_grid
              :if={@has_samples?}
              ids={["activity-reductions", "activity-mailbox", "activity-memory"]}
              hook_id="beam-console-activity-charts"
            />

            <div :if={!@has_samples?} class="beam-console-empty">
              <div class="beam-console-empty-mark" aria-hidden="true">···</div>
              Two successful samples are needed before activity can be compared.
            </div>

            <section class="beam-console-movers" aria-label="Top process movers">
              <h2>Top movers</h2>
              <div id="beam-console-mover-list" phx-update="stream">
                <button
                  :for={{dom_id, mover} <- @streams.top_movers}
                  id={dom_id}
                  phx-click="select_entity"
                  phx-value-id={mover.entity_id}
                  class="beam-console-mover-row"
                >
                  <span><strong>{mover.label}</strong><small>{metric_label(mover.metric)}</small></span>
                  <b>{metric_value(mover.metric, mover.value)}</b>
                </button>
              </div>
            </section>
          </div>
        </section>
      </main>
      """
    end

    attr(:summary, :map, required: true)
    attr(:has_samples?, :boolean, default: false)

    @doc "Renders node-wide runtime inventory, memory, scheduler, and collector charts."
    @spec runtime(map()) :: Phoenix.LiveView.Rendered.t()
    def runtime(assigns) do
      ~H"""
      <main class="beam-console-main beam-console-tab-main">
        <section class="beam-console-tab-stage" aria-label="BEAM runtime statistics">
          <div class="beam-console-graph-toolbar">
            <div>
              <span class="beam-console-kicker">Runtime</span><strong>Node-wide BEAM health</strong>
            </div>
          </div>

          <div class="beam-console-recorder-summary">
            <div><span>Processes</span><strong>{@summary.process_count}</strong></div>
            <div><span>Supervisors</span><strong>{@summary.supervisor_count}</strong></div>
            <div><span>ETS tables</span><strong>{@summary.ets_count}</strong></div>
            <div><span>Run queue</span><strong>{@summary.run_queue || "—"}</strong></div>
          </div>

          <div class="beam-console-tab-scroll">
            <div :if={@summary.collector_partial?} class="beam-console-warning">
              The latest runtime sample is partial; chart gaps are preserved.
            </div>
            <.chart_grid
              :if={@has_samples?}
              ids={["runtime-memory", "runtime-run-queue", "runtime-counts", "runtime-scan"]}
              hook_id="beam-console-runtime-charts"
            />

            <div :if={!@has_samples?} class="beam-console-empty">
              <div class="beam-console-empty-mark" aria-hidden="true">···</div>
              Waiting for the first retained runtime sample.
            </div>
          </div>
        </section>
      </main>
      """
    end

    attr(:ids, :list, required: true)
    attr(:hook_id, :string, required: true)

    defp chart_grid(assigns) do
      ~H"""
      <div
        id={@hook_id}
        class="beam-console-chart-grid"
        phx-hook="BeamConsoleCharts"
        phx-update="ignore"
      >
        <figure :for={id <- @ids} class="beam-console-chart-card" data-chart-id={id}>
          <figcaption><strong data-chart-title></strong><span data-chart-value></span></figcaption>
          <svg
            viewBox="0 0 640 180"
            preserveAspectRatio="none"
            role="img"
            aria-label="History chart"
          ></svg>
          <div class="beam-console-chart-legend" data-chart-legend></div>
        </figure>
      </div>
      """
    end

    defp format_number(value) when is_float(value) do
      value |> Float.round(1) |> :erlang.float_to_binary(decimals: 1)
    end

    defp format_number(value) do
      to_string(value || 0)
    end

    defp signed(value) when is_number(value) and value > 0 do
      "+#{format_number(value)}"
    end

    defp signed(value) do
      format_number(value)
    end

    defp signed_bytes(value) when is_number(value) and value > 0 do
      "+#{format_bytes(value)}"
    end

    defp signed_bytes(value) do
      format_bytes(value)
    end

    defp format_bytes(value) when is_number(value) and abs(value) >= 1_048_576 do
      "#{Float.round(value / 1_048_576, 1)} MB"
    end

    defp format_bytes(value) when is_number(value) and abs(value) >= 1_024 do
      "#{Float.round(value / 1_024, 1)} KB"
    end

    defp format_bytes(value) when is_number(value) do
      "#{round(value)} B"
    end

    defp format_bytes(_value) do
      "—"
    end

    defp metric_label(:reductions_per_second) do
      "Reductions / second"
    end

    defp metric_label(:mailbox_delta) do
      "Mailbox change"
    end

    defp metric_label(:memory_delta) do
      "Memory change"
    end

    defp metric_value(:memory_delta, value) do
      signed_bytes(value)
    end

    defp metric_value(_metric, value) do
      signed(value)
    end
  end
end
