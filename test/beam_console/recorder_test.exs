defmodule BeamConsole.RecorderTest do
  use ExUnit.Case, async: false

  alias BeamConsole.Lifecycle.Recorder, as: LifecycleRecorder
  alias BeamConsole.Recorder
  alias BeamConsole.Recorder.Config

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
end
