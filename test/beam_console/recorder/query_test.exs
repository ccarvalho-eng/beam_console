defmodule BeamConsole.Recorder.QueryTest do
  use ExUnit.Case, async: true

  alias BeamConsole.Recorder.Config
  alias BeamConsole.Recorder.Frame
  alias BeamConsole.Recorder.History
  alias BeamConsole.Recorder.Query

  test "frames are newest first and honor the bounded time window" do
    config = Config.new!(frame_limit: 3)
    history = History.new(config)

    history =
      Enum.reduce(1..4, history, fn sequence, result ->
        frame = %Frame{
          sequence: sequence,
          sampled_at_ms: sequence * 1_000,
          monotonic_ms: sequence * 1_000
        }

        {:ok, result} = History.append(result, frame, [], [], now_ms: sequence * 1_000)
        result
      end)

    {_history, query} = Query.frames(history, since_ms: 3_000, now_ms: 4_000)

    assert Enum.map(query.items, & &1.sequence) == [4, 3]
    assert query.dropped == 1
  end
end
