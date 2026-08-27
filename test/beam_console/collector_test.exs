defmodule BeamConsole.CollectorTest do
  use ExUnit.Case, async: false

  alias BeamConsole.Collector
  alias BeamConsole.Coverage
  alias BeamConsole.Snapshot

  defmodule FakeRuntime do
    @behaviour BeamConsole.Runtime.Adapter

    @impl true
    def snapshot(options) do
      owner = Application.fetch_env!(:beam_console, :fake_runtime_owner)
      send(owner, {:scan_started, Keyword.fetch!(options, :sequence), self()})

      receive do
        :release ->
          sequence = Keyword.fetch!(options, :sequence)

          {:ok,
           %Snapshot{
             sequence: sequence,
             sampled_at: DateTime.utc_now(),
             local_node_id: "node",
             coverage: %Coverage{}
           }}
      end
    end
  end

  setup do
    Application.put_env(:beam_console, :fake_runtime_owner, self())
    on_exit(fn -> Application.delete_env(:beam_console, :fake_runtime_owner) end)

    name = Module.concat(__MODULE__, "Collector#{System.unique_integer([:positive])}")

    collector =
      start_supervised!(
        {Collector,
         name: name,
         runtime: FakeRuntime,
         interval: 60_000,
         scan_timeout: 2_000,
         task_supervisor: BeamConsole.TaskSupervisor}
      )

    %{collector: collector}
  end

  test "coalesces refreshes into one follow-up scan", %{collector: collector} do
    assert {:ok, nil} = Collector.subscribe(collector)
    assert_receive {:scan_started, 1, scanner}

    Collector.refresh(collector)
    Collector.refresh(collector)
    refute_receive {:scan_started, 2, _pid}

    send(scanner, :release)
    assert_receive {:beam_console_snapshot, 1, _diff}
    assert_receive {:scan_started, 2, next_scanner}
    send(next_scanner, :release)
    assert_receive {:beam_console_snapshot, 2, _diff}
  end

  test "remains idle until a subscriber arrives", %{collector: collector} do
    refute_receive {:scan_started, _sequence, _pid}
    assert {:ok, nil} = Collector.subscribe(collector)
    assert_receive {:scan_started, 1, scanner}
    send(scanner, :release)
  end
end
