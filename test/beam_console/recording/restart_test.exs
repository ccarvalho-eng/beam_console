defmodule BeamConsole.Recording.RestartTest do
  use ExUnit.Case, async: false

  alias BeamConsole.Recording
  alias BeamConsole.Recording.Control

  setup do
    Recording.resume()
    on_exit(&Recording.resume/0)
    :ok
  end

  test "a control crash restarts and reconnects both runtime consumers" do
    old_control = Process.whereis(Control)
    old_recorder = Process.whereis(BeamConsole.Lifecycle.Recorder)
    old_collector = Process.whereis(BeamConsole.Collector)

    references =
      Enum.map([old_control, old_recorder, old_collector], fn process ->
        {process, Process.monitor(process)}
      end)

    Process.exit(old_control, :kill)

    Enum.each(references, fn {process, reference} ->
      assert_receive {:DOWN, ^reference, :process, ^process, _reason}, 2_000
    end)

    assert eventually(fn -> replacement?(Control, old_control) end)
    assert eventually(fn -> replacement?(BeamConsole.Lifecycle.Recorder, old_recorder) end)
    assert eventually(fn -> replacement?(BeamConsole.Collector, old_collector) end)

    Recording.pause()

    assert eventually(fn ->
             BeamConsole.Recorder.status().paused? and
               :sys.get_state(BeamConsole.Collector).recording_paused?
           end)

    Recording.resume()

    assert eventually(fn ->
             not BeamConsole.Recorder.status().paused? and
               not :sys.get_state(BeamConsole.Collector).recording_paused?
           end)
  end

  test "a task-supervisor crash preserves authoritative pause intent" do
    Recording.pause()

    control = Process.whereis(Control)
    old_task_supervisor = Process.whereis(BeamConsole.TaskSupervisor)
    old_recorder = Process.whereis(BeamConsole.Lifecycle.Recorder)
    old_collector = Process.whereis(BeamConsole.Collector)
    reference = Process.monitor(old_task_supervisor)

    Process.exit(old_task_supervisor, :kill)
    assert_receive {:DOWN, ^reference, :process, ^old_task_supervisor, _reason}, 2_000

    assert Process.whereis(Control) == control
    assert eventually(fn -> replacement?(BeamConsole.TaskSupervisor, old_task_supervisor) end)
    assert eventually(fn -> replacement?(BeamConsole.Lifecycle.Recorder, old_recorder) end)
    assert eventually(fn -> replacement?(BeamConsole.Collector, old_collector) end)

    assert Recording.status().paused?

    assert eventually(fn ->
             BeamConsole.Recorder.status().paused? and
               :sys.get_state(BeamConsole.Collector).recording_paused?
           end)
  end

  defp replacement?(name, previous) do
    case Process.whereis(name) do
      process when is_pid(process) -> process != previous and Process.alive?(process)
      nil -> false
    end
  end

  defp eventually(function, attempts \\ 80)

  defp eventually(function, 0) do
    function.()
  end

  defp eventually(function, attempts) do
    if function.() do
      true
    else
      Process.sleep(25)
      eventually(function, attempts - 1)
    end
  end
end
