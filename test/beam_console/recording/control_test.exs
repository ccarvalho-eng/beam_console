defmodule BeamConsole.Recording.ControlTest do
  use ExUnit.Case, async: true

  alias BeamConsole.Recording
  alias BeamConsole.Recording.Control
  alias BeamConsole.Recording.Status

  test "stores an idempotent operator pause and broadcasts revisions to registered consumers" do
    control = start_control()

    assert %Status{paused?: false, revision: 0} = Control.register(:collector, control)
    assert %Status{paused?: true, revision: 1} = Control.pause(control)
    assert_receive {Control, %Status{paused?: true, revision: 1}}

    assert %Status{paused?: true, revision: 1} = Control.pause(control)
    refute_receive {Control, %Status{revision: 2}}

    assert %Status{paused?: false, revision: 2} = Control.resume(control)
    assert_receive {Control, %Status{paused?: false, revision: 2}}
  end

  test "a replacement consumer receives the current authoritative state" do
    control = start_control()
    owner = self()

    first = register_consumer(control, owner)
    assert_receive {:registered, ^first, %Status{paused?: false}}

    assert %Status{paused?: true} = Control.pause(control)
    assert_receive {:control_status, ^first, %Status{paused?: true}}

    Process.exit(first, :kill)

    replacement = register_consumer(control, owner)
    assert_receive {:registered, ^replacement, %Status{paused?: true}}
  end

  test "subscribers receive transitions without occupying a runtime-service role" do
    control = start_control()

    assert %Status{paused?: false} = Control.subscribe(control)
    assert %Status{paused?: true, revision: 1} = Control.pause(control)
    assert_receive {Control, %Status{paused?: true, revision: 1}}
  end

  test "the public facade delegates bounded control transitions" do
    control = start_control()

    assert %Status{paused?: true} = Recording.pause(control, 100)
    assert %Status{paused?: true} = Recording.status(control, 100)
    assert %Status{paused?: false} = Recording.resume(control, 100)
  end

  defp start_control do
    name = Module.concat(__MODULE__, "Control#{System.unique_integer([:positive])}")

    start_supervised!(Supervisor.child_spec({Control, name: name}, id: name))
  end

  defp register_consumer(control, owner) do
    spawn(fn ->
      control_monitor = Process.monitor(control)
      status = Control.register(:collector, control)
      send(owner, {:registered, self(), status})
      relay_control_status(owner, control_monitor)
    end)
  end

  defp relay_control_status(owner, control_monitor) do
    receive do
      {Control, %Status{} = status} ->
        send(owner, {:control_status, self(), status})
        relay_control_status(owner, control_monitor)

      {:DOWN, ^control_monitor, :process, _control, _reason} ->
        :ok
    end
  end
end
