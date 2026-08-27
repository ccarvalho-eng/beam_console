defmodule BeamConsole.Runtime.ProcessSelectorTest do
  use ExUnit.Case, async: true

  alias BeamConsole.Runtime.ProcessSelector

  test "selects a deterministic bounded subset in one input pass" do
    processes = Enum.map(1..250, fn _index -> waiting_process() end)
    on_exit(fn -> Enum.each(processes, &send(&1, :stop)) end)

    selected = ProcessSelector.select(processes, 25)

    assert length(selected) == 25
    assert selected == ProcessSelector.select(Enum.reverse(processes), 25)
    assert Enum.all?(selected, &(&1 in processes))
    assert ProcessSelector.select(processes, 0) == []
  end

  defp waiting_process do
    spawn(fn ->
      receive do
        :stop -> :ok
      end
    end)
  end
end
