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

          <div class="beam-console-recorder-summary beam-console-runtime-summary">
            <div>
              <span>Processes</span>
              <strong>{format_integer(@summary.process_count)}</strong>
              <small :if={@summary.inspected_process_count < @summary.process_count}>
                {format_integer(@summary.inspected_process_count)} inspected by the bounded collector
              </small>
              <small :if={@summary.process_limit}>
                {capacity(@summary.process_limit, @summary.process_utilization)}
              </small>
            </div>
            <div><span>Supervisors</span><strong>{@summary.supervisor_count}</strong></div>
            <div
              id="beam-console-atom-usage"
              role="group"
              aria-labelledby="beam-console-atom-label"
              aria-describedby="beam-console-atom-description"
            >
              <span id="beam-console-atom-label">Atoms</span>
              <strong>{format_optional_number(@summary.atom_count)}</strong>
              <small id="beam-console-atom-description">
                {atom_capacity(@summary.atom_limit, @summary.atom_utilization)}. Atoms persist for the VM lifetime.
              </small>
            </div>
            <div>
              <span>Ports</span>
              <strong>{capacity_count(@summary.port_count, @summary.port_limit)}</strong>
              <small>{capacity_usage(@summary.port_utilization)}</small>
            </div>
            <div>
              <span>Schedulers</span>
              <strong>{scheduler_capacity(@summary.scheduler_online, @summary.scheduler_total)}</strong>
              <small>
                {dirty_schedulers(
                  @summary.dirty_cpu_scheduler_online,
                  @summary.dirty_cpu_scheduler_total,
                  @summary.dirty_io_scheduler_total
                )}
              </small>
            </div>
            <div><span>ETS tables</span><strong>{@summary.ets_count}</strong></div>
            <div>
              <span>Run queue</span><strong>{format_optional_number(@summary.run_queue)}</strong>
              <small>{run_queue_split(@summary.run_queue_cpu, @summary.run_queue_io)}</small>
            </div>
            <div>
              <span>I/O throughput</span>
              <strong>
                {io_throughput(@summary.io_input_per_second, @summary.io_output_per_second)}
              </strong>
              <small>input · output per second</small>
            </div>
            <div><span>Uptime</span><strong>{format_uptime(@summary.uptime_ms)}</strong></div>
          </div>

          <div class="beam-console-tab-scroll">
            <div :if={@summary.collector_partial?} class="beam-console-warning">
              The latest runtime sample is partial; chart gaps are preserved.
            </div>
            <.chart_grid
              :if={@has_samples?}
              ids={[
                "runtime-memory",
                "runtime-run-queue",
                "runtime-io",
                "runtime-counts",
                "runtime-scan",
                "runtime-atoms"
              ]}
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

    defp format_optional_number(nil) do
      "—"
    end

    defp format_optional_number(value) do
      format_integer(value)
    end

    defp atom_capacity(limit, utilization)
         when is_integer(limit) and is_number(utilization) do
      "of #{format_integer(limit)} · #{format_percentage(utilization)} used"
    end

    defp atom_capacity(_limit, _utilization) do
      "Limit unavailable"
    end

    defp capacity(limit, utilization) when is_integer(limit) do
      "of #{format_integer(limit)} · #{capacity_usage(utilization)}"
    end

    defp capacity(_limit, _utilization) do
      "Limit unavailable"
    end

    defp capacity_count(count, limit) when is_integer(count) and is_integer(limit) do
      "#{format_integer(count)} of #{format_integer(limit)}"
    end

    defp capacity_count(_count, _limit) do
      "—"
    end

    defp capacity_usage(utilization) when is_number(utilization) do
      "#{format_percentage(utilization)} used"
    end

    defp capacity_usage(_utilization) do
      "Usage unavailable"
    end

    defp scheduler_capacity(online, total) when is_integer(online) and is_integer(total) do
      "#{format_integer(online)} of #{format_integer(total)} online"
    end

    defp scheduler_capacity(_online, _total) do
      "—"
    end

    defp dirty_schedulers(cpu_online, cpu_total, io_total)
         when is_integer(cpu_online) and is_integer(cpu_total) and is_integer(io_total) do
      "Dirty CPU #{cpu_online}/#{cpu_total} · Dirty I/O #{io_total}"
    end

    defp dirty_schedulers(_cpu_online, _cpu_total, _io_total) do
      "Dirty scheduler topology unavailable"
    end

    defp run_queue_split(cpu, io) when is_integer(cpu) and is_integer(io) do
      "CPU #{format_integer(cpu)} · I/O #{format_integer(io)}"
    end

    defp run_queue_split(_cpu, _io) do
      "Queue split unavailable"
    end

    defp io_throughput(input, output) do
      "In #{format_rate(input)} · Out #{format_rate(output)}"
    end

    defp format_rate(nil) do
      "—"
    end

    defp format_rate(value) do
      "#{format_bytes(value)}/s"
    end

    defp format_uptime(milliseconds) when is_integer(milliseconds) and milliseconds >= 0 do
      total_minutes = div(milliseconds, 60_000)
      days = div(total_minutes, 1_440)
      hours = total_minutes |> rem(1_440) |> div(60)
      minutes = rem(total_minutes, 60)

      cond do
        days > 0 -> "#{days}d #{hours}h #{minutes}m"
        hours > 0 -> "#{hours}h #{minutes}m"
        total_minutes > 0 -> "#{minutes}m"
        true -> "#{div(milliseconds, 1_000)}s"
      end
    end

    defp format_uptime(_milliseconds) do
      "—"
    end

    defp format_percentage(value) do
      value
      |> Float.round(2)
      |> :erlang.float_to_binary(decimals: 2)
      |> Kernel.<>("%")
    end

    defp format_integer(value) when is_integer(value) and value >= 0 do
      value
      |> Integer.to_string()
      |> String.reverse()
      |> String.graphemes()
      |> Enum.chunk_every(3)
      |> Enum.map_join(",", &Enum.join/1)
      |> String.reverse()
    end

    defp format_integer(value) do
      to_string(value)
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
