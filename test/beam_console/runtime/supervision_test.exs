defmodule BeamConsole.Runtime.SupervisionTest do
  use ExUnit.Case, async: false

  alias BeamConsole.Lifecycle.Observation
  alias BeamConsole.Runtime.Supervision

  defmodule StableSupervisor do
    use Supervisor

    def start_link(_options) do
      Supervisor.start_link(__MODULE__, [])
    end

    @impl true
    def init(_options) do
      child = %{
        id: :stable_agent,
        start: {Agent, :start_link, [fn -> :ready end]}
      }

      Supervisor.init([child], strategy: :one_for_one)
    end
  end

  test "keeps a stable opaque slot across normal supervisor transitions" do
    supervisor = start_supervised!(StableSupervisor)

    assert {_edges, _attribution, [running], 0, false} =
             Supervision.collect([{:sample, supervisor}], node(), sequence: 7)

    assert %Observation{
             slot_kind: :stable,
             supervisor_pid: ^supervisor,
             child_pid: first_child,
             child_state: :running,
             child_type: :worker,
             modules: [Agent],
             sequence: 7,
             coverage: :complete
           } = running

    assert is_pid(first_child)
    assert String.starts_with?(running.slot_id, "slot_")
    assert :ok = Supervisor.terminate_child(supervisor, :stable_agent)

    assert {_edges, _attribution, [stopped], 0, false} =
             Supervision.collect([{:sample, supervisor}], node(), sequence: 8)

    assert stopped.slot_id == running.slot_id
    assert stopped.child_pid == nil
    assert stopped.child_state == :undefined
    assert stopped.slot_kind == :stable

    assert {:ok, replacement} = Supervisor.restart_child(supervisor, :stable_agent)

    assert {_edges, _attribution, [restarted], 0, false} =
             Supervision.collect([{:sample, supervisor}], node(), sequence: 9)

    assert restarted.slot_id == running.slot_id
    assert restarted.child_pid == replacement
    assert restarted.child_pid != first_child
    assert restarted.child_state == :running
  end

  test "keeps distinct edges for DynamicSupervisor children with undefined child keys" do
    supervisor = start_supervised!({DynamicSupervisor, strategy: :one_for_one})

    assert {:ok, first_child} =
             DynamicSupervisor.start_child(supervisor, {Agent, fn -> :first end})

    assert {:ok, second_child} =
             DynamicSupervisor.start_child(supervisor, {Agent, fn -> :second end})

    assert {edges, attribution, observations, 0, false} =
             Supervision.collect([{:sample, supervisor}], node(), [])

    assert map_size(edges) == 2
    assert map_size(attribution) == 2

    assert MapSet.new(Enum.map(edges, fn {_id, edge} -> edge.child_id end)) ==
             MapSet.new([
               BeamConsole.EntityId.build(:process, {node(), first_child}),
               BeamConsole.EntityId.build(:process, {node(), second_child})
             ])

    assert Enum.all?(observations, &(&1.slot_kind == :dynamic))
    assert Enum.all?(observations, &(&1.child_state == :running))
    assert MapSet.size(MapSet.new(observations, & &1.slot_id)) == 2
  end

  test "never retains more edges than the configured child limit" do
    supervisor = start_supervised!({DynamicSupervisor, strategy: :one_for_one})

    assert {:ok, _first_child} =
             DynamicSupervisor.start_child(supervisor, {Agent, fn -> :first end})

    assert {:ok, _second_child} =
             DynamicSupervisor.start_child(supervisor, {Agent, fn -> :second end})

    assert {edges, attribution, observations, 0, true} =
             Supervision.collect([{:sample, supervisor}], node(), children_limit: 1)

    assert map_size(edges) == 1
    assert map_size(attribution) == 1
    assert [%Observation{coverage: :truncated}] = observations
  end

  test "does not observe children of its own probe task supervisor" do
    task_supervisor = Process.whereis(BeamConsole.TaskSupervisor)

    assert {_edges, _attribution, observations, 0, false} =
             Supervision.collect([{:beam_console, task_supervisor}], node(), [])

    assert observations == []
  end
end
