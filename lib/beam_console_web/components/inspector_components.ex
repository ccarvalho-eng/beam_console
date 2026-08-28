if Code.ensure_loaded?(Phoenix.Component) do
  defmodule BeamConsoleWeb.Components.InspectorComponents do
    @moduledoc "Renders safe, read-only process, application, and node inspection views."

    use Phoenix.Component

    attr(:selected, :map, default: nil)
    attr(:detail, :any, default: nil)

    @doc "Renders the selected entity using only allowlisted bounded metadata."
    @spec inspector(map()) :: Phoenix.LiveView.Rendered.t()
    def inspector(assigns) do
      ~H"""
      <aside
        id="beam-console-inspector-panel"
        class="beam-console-inspector"
        data-beam-console-panel="inspector"
        aria-label="Selected entity details"
        tabindex="-1"
      >
        <div class="beam-console-panel-heading">
          <div class="beam-console-heading-line">
            <h2>Inspector</h2>
            <div class="beam-console-panel-heading-actions">
              <span class="beam-console-heading-count">read only</span>
              <button
                type="button"
                class="beam-console-panel-close"
                data-beam-console-panel-dismiss
                aria-label="Close inspector"
              >
                <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
                  <path d="m7 7 10 10M17 7 7 17" />
                </svg>
              </button>
            </div>
          </div>
          <p>Allowlisted runtime metadata</p>
        </div>

        <%= case @selected do %>
          <% %{kind: :process} -> %>
            <.process_detail selected={@selected} detail={@detail} vanished?={false} />
          <% %{kind: :vanished} -> %>
            <.process_detail selected={@selected} detail={@detail} vanished?={true} />
          <% %{kind: :application} -> %>
            <.application_detail selected={@selected} />
          <% %{kind: :node} -> %>
            <.node_detail selected={@selected} />
          <% %{kind: :unknown} -> %>
            <.empty message="This entity is no longer available in the latest sample." />
          <% _other -> %>
            <.empty message="Select a process, application, or node to inspect it." />
        <% end %>
      </aside>
      """
    end

    attr(:selected, :map, required: true)
    attr(:detail, :any, default: nil)
    attr(:vanished?, :boolean, default: false)

    defp process_detail(assigns) do
      ~H"""
      <%= if @detail do %>
        <div id="beam-console-detail" class="beam-console-detail">
          <div :if={@vanished?} class="beam-console-warning" role="status">
            This process vanished after sample {@selected.last_seen_sequence}. Values below are the
            last allowlisted detail retained by this page.
          </div>
          <div class="beam-console-detail-heading">
            <div>
              <p class="beam-console-kicker">Process</p>
              <h3>{@detail.label}</h3>
              <p class="beam-console-detail-pid">{@detail.pid_text}</p>
            </div>
            <span class="beam-console-detail-status">
              {if(@vanished?, do: "vanished", else: @detail.status || "unknown")}
            </span>
          </div>

          <div class="beam-console-metrics">
            <div><span>Memory</span><strong>{format_bytes(@detail.memory)}</strong></div>
            <div><span>Reductions</span><strong>{format_integer(@detail.reductions)}</strong></div>
            <div><span>Mailbox</span><strong>{@detail.message_queue_len || 0}</strong></div>
          </div>

          <dl class="beam-console-fields">
            <dt>Application</dt><dd>{@detail.application || "unattributed"}</dd>
            <dt>Module</dt><dd>{@detail.module || "unknown"}</dd>
            <dt>Current</dt><dd>{@detail.current_function || "unknown"}</dd>
          </dl>

          <.process_diagnostics diagnostics={@detail.diagnostics} />

          <.relation_list
            title="Links"
            values={@detail.links}
            omitted={@detail.relationship_omitted.links}
          />
          <.relation_list
            title="Monitors"
            values={@detail.monitors}
            omitted={@detail.relationship_omitted.monitors}
          />
          <.relation_list
            title="Monitored by"
            values={@detail.monitored_by}
            omitted={@detail.relationship_omitted.monitored_by}
          />
        </div>
      <% else %>
        <.empty message={@selected.label <> " is no longer available for live inspection."} />
      <% end %>
      """
    end

    attr(:diagnostics, :any, default: nil)

    defp process_diagnostics(assigns) do
      ~H"""
      <section :if={@diagnostics} class="beam-console-diagnostics">
        <h4>Scheduling and memory</h4>
        <dl class="beam-console-fields">
          <dt>Initial call</dt><dd>{@diagnostics.initial_call || "unknown"}</dd>
          <dt>Priority</dt><dd>{@diagnostics.priority || "unknown"}</dd>
          <dt>Trap exits</dt><dd>{format_boolean(@diagnostics.trap_exit)}</dd>
          <dt>Group leader</dt><dd><.relation_value relation={@diagnostics.group_leader} /></dd>
          <dt>Heap</dt><dd>{format_words(@diagnostics.heap_size)}</dd>
          <dt>Total heap</dt><dd>{format_words(@diagnostics.total_heap_size)}</dd>
          <dt>Stack</dt><dd>{format_words(@diagnostics.stack_size)}</dd>
          <dt>Minor GCs</dt><dd>{format_integer(@diagnostics.minor_gcs)}</dd>
          <dt>Fullsweep after</dt><dd>{format_integer(@diagnostics.fullsweep_after)}</dd>
        </dl>
      </section>
      """
    end

    attr(:relation, :any, default: nil)

    defp relation_value(assigns) do
      ~H"""
      <button
        :if={@relation && @relation.id}
        type="button"
        class="beam-console-relation-link"
        phx-click="select_entity"
        phx-value-id={@relation.id}
      >
        {@relation.label}
      </button>
      <span :if={@relation && is_nil(@relation.id)}>{@relation.label}</span>
      <span :if={is_nil(@relation)}>—</span>
      """
    end

    attr(:selected, :map, required: true)

    defp application_detail(assigns) do
      ~H"""
      <div id="beam-console-application-detail" class="beam-console-detail">
        <div class="beam-console-detail-heading">
          <div>
            <p class="beam-console-kicker">Application</p>
            <h3>{@selected.label}</h3>
            <p class="beam-console-detail-pid">version {@selected.version || "unknown"}</p>
          </div>
          <span class="beam-console-detail-status">running</span>
        </div>
        <p class="beam-console-detail-copy">{@selected.description || "No description reported."}</p>
        <dl class="beam-console-fields">
          <dt>Node</dt><dd>{@selected.node_id}</dd>
          <dt>Root supervisor</dt><dd>{@selected.root_supervisor_id || "not attributed"}</dd>
        </dl>
      </div>
      """
    end

    attr(:selected, :map, required: true)

    defp node_detail(assigns) do
      ~H"""
      <div id="beam-console-node-detail" class="beam-console-detail">
        <div class="beam-console-detail-heading">
          <div>
            <p class="beam-console-kicker">Node</p>
            <h3>{@selected.label}</h3>
          </div>
          <span class="beam-console-detail-status">{@selected.node_kind}</span>
        </div>
        <dl class="beam-console-fields">
          <dt>Inspection</dt><dd>{if(@selected.inspectable?, do: "local", else: "inventory only")}</dd>
        </dl>
      </div>
      """
    end

    attr(:message, :string, required: true)

    defp empty(assigns) do
      ~H"""
      <div id="beam-console-detail-empty" class="beam-console-empty">
        <div class="beam-console-empty-mark" aria-hidden="true">⌁</div>
        {@message}
      </div>
      """
    end

    attr(:title, :string, required: true)
    attr(:values, :list, required: true)
    attr(:omitted, :integer, required: true)

    defp relation_list(assigns) do
      ~H"""
      <section :if={@values != [] or @omitted > 0} class="beam-console-relation">
        <h4>{@title}</h4>
        <ul>
          <li :for={relation <- @values}>
            <button
              :if={relation.id}
              type="button"
              class="beam-console-relation-link"
              phx-click="select_entity"
              phx-value-id={relation.id}
            >
              {relation.label}
            </button>
            <span :if={is_nil(relation.id)}>{relation.label}</span>
          </li>
        </ul>
        <p :if={@omitted > 0} class="beam-console-detail-copy">
          {@omitted} additional relationships omitted by the inspection limit.
        </p>
      </section>
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

    defp format_integer(nil) do
      "—"
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

    defp format_words(nil) do
      "—"
    end

    defp format_words(value) do
      "#{format_integer(value)} words"
    end

    defp format_boolean(true) do
      "yes"
    end

    defp format_boolean(false) do
      "no"
    end

    defp format_boolean(nil) do
      "—"
    end
  end
end
