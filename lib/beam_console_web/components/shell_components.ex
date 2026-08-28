if Code.ensure_loaded?(Phoenix.Component) do
  defmodule BeamConsoleWeb.Components.ShellComponents do
    @moduledoc "Renders the BeamConsole header, navigation, and browser-owned display controls."

    use Phoenix.Component

    attr(:page_title, :string, required: true)
    attr(:status_label, :string, required: true)
    attr(:status_state, :atom, required: true)
    attr(:filter_form, :map, required: true)
    attr(:tab, :atom, required: true)
    attr(:tab_paths, :map, required: true)
    attr(:recording_paused?, :boolean, required: true)
    attr(:recording_control_available?, :boolean, required: true)
    attr(:refresh_pending?, :boolean, default: false)

    @doc "Renders the dashboard header with tabs, recording, refresh, focus, and theme controls."
    @spec header(map()) :: Phoenix.LiveView.Rendered.t()
    def header(assigns) do
      ~H"""
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
            <h1 class="beam-console-title">{@page_title}</h1>
          </div>
        </div>

        <nav class="beam-console-tabs" aria-label="Dashboard views">
          <.link
            :for={{label, tab} <- tabs()}
            id={"beam-console-tab-#{tab}"}
            class={["beam-console-tab", @tab == tab && "is-active"]}
            patch={Map.fetch!(@tab_paths, tab)}
            aria-current={if(@tab == tab, do: "page")}
          >
            {label}
          </.link>
        </nav>

        <div class="beam-console-actions">
          <button
            type="button"
            class="beam-console-icon-button beam-console-panel-toggle"
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
            type="button"
            class="beam-console-icon-button beam-console-panel-toggle"
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

          <span class={["beam-console-status", "is-#{@status_state}"]} aria-hidden="true">
            {@status_label}
          </span>
          <span
            id="beam-console-status-announcement"
            class="beam-console-visually-hidden"
            role="status"
            aria-live="polite"
            aria-atomic="true"
          >
            {status_announcement(
              @status_state,
              @recording_paused?,
              @recording_control_available?
            )}
          </span>

          <.form
            for={@filter_form}
            id="beam-console-search"
            class={[
              "beam-console-search-form",
              @tab not in [:process_map, :lifecycle] && "is-placeholder"
            ]}
            phx-change="search"
            aria-hidden={@tab not in [:process_map, :lifecycle]}
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
              placeholder={if(@tab == :lifecycle, do: "Search events", else: "Search processes")}
              phx-debounce="250"
              autocomplete="off"
              disabled={@tab not in [:process_map, :lifecycle]}
            />
          </.form>

          <button
            id="beam-console-recorder-control"
            class={["beam-console-icon-button", not @recording_paused? && "is-recording"]}
            phx-click="toggle_recording"
            disabled={not @recording_control_available?}
            aria-label={recording_control_label(@recording_paused?, @recording_control_available?)}
            data-tooltip={recording_control_label(@recording_paused?, @recording_control_available?)}
          >
            <svg
              :if={not @recording_paused?}
              viewBox="0 0 24 24"
              fill="none"
              aria-hidden="true"
            >
              <rect x="7" y="6" width="3" height="12" rx="1" />
              <rect x="14" y="6" width="3" height="12" rx="1" />
            </svg>
            <svg
              :if={@recording_paused?}
              viewBox="0 0 24 24"
              fill="none"
              aria-hidden="true"
            >
              <path d="m8 5 11 7-11 7V5Z" />
            </svg>
          </button>

          <button
            id="beam-console-refresh"
            class={["beam-console-icon-button", @refresh_pending? && "is-pending"]}
            phx-click="refresh"
            aria-label="Refresh runtime sample"
            data-tooltip="Refresh sample"
            aria-busy={if(@refresh_pending?, do: "true", else: "false")}
          >
            <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
              <path d="M16.023 9.348h4.992v-.001M2.985 19.644v-4.992m0 0h4.992m-4.993 0 3.181 3.183a8.25 8.25 0 0 0 13.803-3.7M4.031 9.865a8.25 8.25 0 0 1 13.803-3.7l3.181 3.182m0-4.991v4.99" />
            </svg>
          </button>

          <button
            id="beam-console-focus-mode"
            type="button"
            class="beam-console-icon-button"
            data-beam-console-focus-toggle
            aria-label="Enter focus mode"
            aria-keyshortcuts="F"
            aria-pressed="false"
            data-tooltip="Focus mode (F)"
          >
            <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
              <path d="M9 4H4v5M15 4h5v5M20 15v5h-5M4 15v5h5" />
            </svg>
          </button>

          <div id="beam-console-theme-switcher" class="beam-console-theme-switcher" aria-label="Theme">
            <.theme_button mode="system" label="Use system theme">
              <rect x="3" y="4" width="18" height="13" rx="2" />
              <path d="M8 21h8M12 17v4" />
            </.theme_button>
            <.theme_button mode="light" label="Use light theme">
              <circle cx="12" cy="12" r="3.5" />
              <path d="M12 2v2M12 20v2M4.93 4.93l1.42 1.42M17.65 17.65l1.42 1.42M2 12h2M20 12h2M4.93 19.07l1.42-1.42M17.65 6.35l1.42-1.42" />
            </.theme_button>
            <.theme_button mode="dark" label="Use dark theme">
              <path d="M20 15.2A8.2 8.2 0 0 1 8.8 4a8.2 8.2 0 1 0 11.2 11.2Z" />
            </.theme_button>
          </div>
        </div>
      </header>
      """
    end

    attr(:mode, :string, required: true)
    attr(:label, :string, required: true)
    slot(:inner_block, required: true)

    @doc "Renders one option in the system/light/dark theme control."
    @spec theme_button(map()) :: Phoenix.LiveView.Rendered.t()
    def theme_button(assigns) do
      ~H"""
      <button
        type="button"
        class="beam-console-theme-button"
        data-beam-console-theme={@mode}
        aria-label={@label}
        title={@label}
        aria-pressed="false"
      >
        <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
          {render_slot(@inner_block)}
        </svg>
      </button>
      """
    end

    defp tabs do
      [
        {"Process Map", :process_map},
        {"Lifecycle", :lifecycle},
        {"Activity", :activity},
        {"Runtime", :runtime}
      ]
    end

    defp recording_control_label(_paused?, false) do
      "Recording control unavailable"
    end

    defp recording_control_label(true, true) do
      "Resume recording"
    end

    defp recording_control_label(false, true) do
      "Pause recording"
    end

    defp status_announcement(status_state, paused?, available?) do
      runtime = runtime_status_announcement(status_state)
      recording = recording_status_announcement(paused?, available?)
      "#{runtime}. #{recording}"
    end

    defp runtime_status_announcement(:live) do
      "Runtime sampling is live"
    end

    defp runtime_status_announcement(:loading) do
      "Runtime sampling is starting"
    end

    defp runtime_status_announcement(:stale) do
      "Runtime sampling is stale"
    end

    defp recording_status_announcement(_paused?, false) do
      "Lifecycle recording control is unavailable"
    end

    defp recording_status_announcement(true, true) do
      "Lifecycle recording is paused"
    end

    defp recording_status_announcement(false, true) do
      "Lifecycle recording is active"
    end
  end
end
