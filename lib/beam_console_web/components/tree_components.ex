if Code.ensure_loaded?(Phoenix.Component) do
  defmodule BeamConsoleWeb.Components.TreeComponents do
    @moduledoc "Renders the collapsible node and categorized application folder tree."

    use Phoenix.Component

    attr(:nodes, :list, required: true)
    attr(:categories, :list, required: true)
    attr(:application_count, :integer, required: true)
    attr(:selected_id, :string, default: nil)
    attr(:coverage_warnings, :list, default: [])

    @doc "Renders nodes and application categories as stable native disclosure branches."
    @spec runtime_tree(map()) :: Phoenix.LiveView.Rendered.t()
    def runtime_tree(assigns) do
      ~H"""
      <aside class="beam-console-sidebar" aria-label="Runtime hierarchy">
        <div class="beam-console-panel-heading">
          <div class="beam-console-heading-line">
            <h2>Runtime</h2>
            <span class="beam-console-heading-count">{@application_count} apps</span>
          </div>
          <p>Nodes and categorized applications</p>
        </div>

        <div :for={warning <- @coverage_warnings} class="beam-console-warning">{warning}</div>

        <ul id="beam-console-runtime-tree" class="beam-console-list" phx-hook="BeamConsoleTree">
          <li :for={runtime_node <- @nodes}>
            <details id={"tree-#{runtime_node.id}"} class="beam-console-tree-branch" open>
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
                <li :for={category <- @categories}>
                  <details
                    id={"tree-#{runtime_node.id}-#{category.id}"}
                    class="beam-console-tree-branch"
                    open={category.category != :otp}
                  >
                    <summary class="beam-console-link beam-console-tree-summary beam-console-category-summary">
                      <span class="beam-console-link-label">
                        <span class="beam-console-tree-caret" aria-hidden="true"></span>
                        <span aria-hidden="true">-</span>
                        {category.label}
                      </span>
                      <span class="beam-console-count">{category.count}</span>
                    </summary>
                    <ul>
                      <li :for={application <- category.applications}>
                        <button
                          id={"select-#{application.id}"}
                          class={[
                            "beam-console-link",
                            @selected_id == application.id && "is-selected"
                          ]}
                          phx-click="select_entity"
                          phx-value-id={application.id}
                        >
                          <span class="beam-console-link-label">{application.name}</span>
                          <span class="beam-console-count">app</span>
                        </button>
                      </li>
                    </ul>
                  </details>
                </li>
              </ul>
            </details>
          </li>
        </ul>
      </aside>
      """
    end
  end
end
