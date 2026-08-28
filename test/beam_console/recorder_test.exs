defmodule BeamConsole.RecorderTest do
  use ExUnit.Case, async: false

  alias BeamConsole.Lifecycle.Recorder, as: LifecycleRecorder
  alias BeamConsole.Recorder
  alias BeamConsole.Recorder.Config
  alias BeamConsole.Recording.Control

  test "public facade exposes recording status and controls" do
    name = Module.concat(__MODULE__, "Recorder#{System.unique_integer([:positive])}")

    recorder =
      start_supervised!(
        Supervisor.child_spec(
          {LifecycleRecorder, name: name, config: Config.new!(), collector: nil},
          id: name
        )
      )

    LifecycleRecorder.activate(recorder)

    assert Recorder.status(recorder).activity == :recording
    assert Recorder.pause(recorder).activity == :paused
    assert Recorder.resume(recorder).activity == :recording
    assert Recorder.events([], recorder).items == []
  end

  test "public recorder controls update the configured authority" do
    control = start_supervised!({Control, name: nil})

    recorder =
      start_supervised!(
        Supervisor.child_spec(
          {LifecycleRecorder,
           name: nil,
           config: Config.new!(mode: :always),
           collector: nil,
           recording_control: control},
          id: System.unique_integer([:positive])
        )
      )

    assert Recorder.pause(recorder).activity == :paused
    assert Control.status(control).paused?
    assert Recorder.resume(recorder).activity == :recording
    refute Control.status(control).paused?
  end

  test "rejects malformed query options without terminating the recorder" do
    recorder =
      start_supervised!({LifecycleRecorder, name: nil, config: Config.new!(), collector: nil})

    assert {:error, {:invalid_query_options, :kinds}} =
             Recorder.events([kinds: :terminated], recorder)

    assert {:error, {:invalid_query_options, :now_ms}} =
             Recorder.events([now_ms: "invalid"], recorder)

    assert {:error, {:invalid_query_options, {:unknown, [:size_estimator]}}} =
             Recorder.events(
               [size_estimator: fn _item -> raise "must not run" end],
               recorder
             )

    assert %BeamConsole.Recorder.Status{} = Recorder.status(recorder)
  end
end
