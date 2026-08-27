defmodule BeamConsole.Recorder.FrameTest do
  use ExUnit.Case, async: true

  alias BeamConsole.Coverage
  alias BeamConsole.Recorder.Frame
  alias BeamConsole.Snapshot

  test "retains vanished-process coverage as partial history" do
    snapshot = %Snapshot{
      sequence: 1,
      sampled_at: DateTime.utc_now(),
      local_node_id: "local-node",
      coverage: %Coverage{vanished_pids: 1}
    }

    assert Frame.from_snapshot(snapshot, 10).coverage == :partial
  end
end
