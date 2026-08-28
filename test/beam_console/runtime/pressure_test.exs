defmodule BeamConsole.Runtime.PressureTest do
  use ExUnit.Case, async: true

  doctest BeamConsole.Runtime.Pressure

  alias BeamConsole.Runtime.Pressure

  test "partitions by configured schedulers when only a subset is online" do
    lengths = [1, 2, 3, 4, 5, 6]

    assert {:ok, queues} = Pressure.partition_run_queues(lengths, 4)
    assert queues == %{total: 21, cpu: 15, io: 6}
  end

  test "rejects malformed or negative queue snapshots" do
    assert Pressure.partition_run_queues([1, 2, 3], 2) == :error
    assert Pressure.partition_run_queues([1, -1, 2, 3], 2) == :error
    assert Pressure.partition_run_queues(:unavailable, 2) == :error
  end
end
