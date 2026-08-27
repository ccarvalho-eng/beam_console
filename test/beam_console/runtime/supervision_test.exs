defmodule BeamConsole.Runtime.SupervisionTest do
  use ExUnit.Case, async: false

  alias BeamConsole.Runtime.Supervision

  test "keeps distinct edges for DynamicSupervisor children with undefined child keys" do
    supervisor = start_supervised!({DynamicSupervisor, strategy: :one_for_one})

    assert {:ok, first_child} =
             DynamicSupervisor.start_child(supervisor, {Agent, fn -> :first end})

    assert {:ok, second_child} =
             DynamicSupervisor.start_child(supervisor, {Agent, fn -> :second end})

    assert {edges, attribution, 0, false} =
             Supervision.collect([{:sample, supervisor}], node(), [])

    assert map_size(edges) == 2
    assert map_size(attribution) == 2

    assert MapSet.new(Enum.map(edges, fn {_id, edge} -> edge.child_id end)) ==
             MapSet.new([
               BeamConsole.EntityId.build(:process, {node(), first_child}),
               BeamConsole.EntityId.build(:process, {node(), second_child})
             ])
  end

  test "never retains more edges than the configured child limit" do
    supervisor = start_supervised!({DynamicSupervisor, strategy: :one_for_one})

    assert {:ok, _first_child} =
             DynamicSupervisor.start_child(supervisor, {Agent, fn -> :first end})

    assert {:ok, _second_child} =
             DynamicSupervisor.start_child(supervisor, {Agent, fn -> :second end})

    assert {edges, attribution, 0, true} =
             Supervision.collect([{:sample, supervisor}], node(), children_limit: 1)

    assert map_size(edges) == 1
    assert map_size(attribution) == 1
  end
end
