if Code.ensure_loaded?(Phoenix.LiveViewTest) do
  defmodule BeamConsoleWeb.Components.InspectorComponentsTest do
    use ExUnit.Case, async: true

    import Phoenix.LiveViewTest

    alias BeamConsole.ProcessDetail
    alias BeamConsole.ProcessDetail.Diagnostics
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

    test "renders safe scheduling and memory diagnostics" do
      detail = %ProcessDetail{
        id: "process-1",
        pid_text: "<0.1.0>",
        label: "Worker",
        diagnostics: %Diagnostics{
          initial_call: "Elixir.Example.Worker.init/1",
          trap_exit: true,
          priority: :normal,
          group_leader: %ProcessRelation{
            id: "process-2",
            label: "<0.2.0>",
            kind: :process
          },
          heap_size: 610,
          total_heap_size: 987,
          stack_size: 12,
          minor_gcs: 4,
          fullsweep_after: 65_535
        }
      }

      html =
        render_component(&InspectorComponents.inspector/1,
          selected: %{id: detail.id, kind: :process, label: detail.label},
          detail: detail
        )

      assert html =~ "Scheduling and memory"
      assert html =~ "Elixir.Example.Worker.init/1"
      assert html =~ "Trap exits"
      assert html =~ "987 words"
      assert html =~ "65,535"
      assert html =~ ~s(phx-value-id="process-2")
    end
  end
end
