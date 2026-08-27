if Code.ensure_loaded?(Phoenix.Component) do
  defmodule BeamConsoleWeb.Components.LifecycleComponents do
    @moduledoc "Renders recorder controls, coverage, and the bounded lifecycle event stream."

    use Phoenix.Component

    attr(:streams, :map, required: true)
    attr(:recorder_status, :map, required: true)
    attr(:recorder_label, :string, required: true)
    attr(:lifecycle_query, :map, required: true)
    attr(:selected_id, :string, default: nil)

    @spec lifecycle(map()) :: Phoenix.LiveView.Rendered.t()
    @doc "Renders the newest bounded lifecycle observations with evidence language."
    def lifecycle(assigns) do
      ~H"""
      <main class="beam-console-main beam-console-tab-main">
        <section class="beam-console-tab-stage" aria-label="Process lifecycle recorder">
          <div class="beam-console-graph-toolbar">
            <div>
              <span class="beam-console-kicker">Process Flight Recorder</span>
              <strong>{@recorder_label} · local supervised processes</strong>
            </div>
            <span class={["beam-console-recording-badge", "is-#{@recorder_status.activity}"]}>
              {@recorder_label}
            </span>
          </div>

          <div class="beam-console-lifecycle-controls">
            <div class="beam-console-recorder-summary">
              <div><span>Watched</span><strong>{@recorder_status.watched}</strong></div>
              <div><span>Eligible</span><strong>{@recorder_status.eligible}</strong></div>
              <div>
                <span>Events retained</span><strong>{@recorder_status.history.event_count}</strong>
              </div>
              <div>
                <span>Omitted</span><strong>{@recorder_status.omitted + @lifecycle_query.omitted}</strong>
              </div>
            </div>

            <div :if={@recorder_status.activity == :paused} class="beam-console-warning">
              Recording is paused. Retained history remains available until it expires.
            </div>
            <div :if={@recorder_status.deferred > 0} class="beam-console-warning">
              {@recorder_status.deferred} eligible process watches are deferred by the reconciliation budget.
            </div>
          </div>

          <div class="beam-console-lifecycle-scroll">
            <div
              id="beam-console-lifecycle-list"
              class="beam-console-lifecycle-list"
              phx-update="stream"
            >
              <button
                :for={{dom_id, event} <- @streams.lifecycle_events}
                id={dom_id}
                class={[
                  "beam-console-lifecycle-row",
                  event.entity_id == @selected_id && "is-selected"
                ]}
                phx-click={if(event.entity_id, do: "select_entity")}
                phx-value-id={event.entity_id}
                disabled={is_nil(event.entity_id)}
              >
                <span class={"beam-console-event-kind is-#{event.kind}"}>{event.kind_label}</span>
                <span class="beam-console-event-copy">
                  <strong>{event.label}</strong>
                  <small>{event.evidence} · {event.certainty}<span :if={event.reason}> · {event.reason}</span></small>
                </span>
                <time>{event.observed_at}</time>
              </button>
            </div>

            <div :if={@lifecycle_query.items == []} class="beam-console-empty">
              <div class="beam-console-empty-mark" aria-hidden="true">···</div>
              No lifecycle observations match this view yet.
            </div>
          </div>
        </section>
      </main>
      """
    end
  end
end
