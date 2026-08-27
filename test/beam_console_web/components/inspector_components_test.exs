if Code.ensure_loaded?(Phoenix.LiveViewTest) do
  defmodule BeamConsoleWeb.Components.InspectorComponentsTest do
    use ExUnit.Case, async: true

    import Phoenix.LiveViewTest

    alias BeamConsole.ProcessDetail
    alias BeamConsole.ProcessRelation
    alias BeamConsoleWeb.Components.InspectorComponents

    test "makes bounded relationship omissions visible" do
      detail = %ProcessDetail{
        id: "process-1",
        pid_text: "<0.1.0>",
        label: "Worker",
        links: [%ProcessRelation{label: "<0.2.0>", kind: :process}],
        relationship_counts: %{links: 5, monitors: 0, monitored_by: 0},
        relationship_omitted: %{links: 4, monitors: 0, monitored_by: 0}
      }

      html =
        render_component(&InspectorComponents.inspector/1,
          selected: %{id: detail.id, kind: :process, label: detail.label},
          detail: detail
        )

      assert html =~ "4 additional relationships omitted by the inspection limit."
    end

    test "renders only available relationship targets as buttons" do
      detail = %ProcessDetail{
        id: "process-1",
        pid_text: "<0.1.0>",
        label: "Worker",
        links: [
          %ProcessRelation{id: "process-2", label: "Available", kind: :process},
          %ProcessRelation{label: "Unavailable", kind: :process}
        ]
      }

      html =
        render_component(&InspectorComponents.inspector/1,
          selected: %{id: detail.id, kind: :process, label: detail.label},
          detail: detail
        )

      assert html =~ ~s(phx-value-id="process-2")
      assert html =~ ~r/<span>\s*Unavailable\s*<\/span>/
      refute html =~ ~s(phx-value-id="Unavailable")
    end
  end
end
