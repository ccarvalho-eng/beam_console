defmodule BeamConsolePlainHostTest do
  use ExUnit.Case, async: false

  test "runs the complete collector protocol without Phoenix dependencies" do
    assert %BeamConsole.Collector.Status{} = BeamConsole.status()
    assert {:ok, _snapshot} = BeamConsole.subscribe()
    assert :ok = BeamConsole.refresh()
    assert_receive {:beam_console_snapshot, sequence}, 2_000
    assert %BeamConsole.Snapshot{sequence: ^sequence} = BeamConsole.latest_snapshot()
    assert %BeamConsole.Recorder.Status{} = BeamConsole.Recorder.status()
    assert %BeamConsole.Recorder.Query{} = BeamConsole.Recorder.events()
    assert :ok = BeamConsole.acknowledge(sequence)
    assert :ok = BeamConsole.unsubscribe()
    refute Code.ensure_loaded?(BeamConsoleWeb.ConsoleLive)
  end

  test "declares the OTP applications required by the core runtime" do
    applications = Application.spec(:beam_console, :applications)

    assert :crypto in applications
    assert :logger in applications
  end
end
