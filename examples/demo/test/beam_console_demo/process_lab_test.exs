defmodule BeamConsoleDemo.ProcessLabTest do
  use ExUnit.Case

  alias BeamConsoleDemo.ProcessLab
  alias BeamConsoleDemo.ProcessLab.RelationshipWatcher

  @churn_supervisor BeamConsoleDemo.ProcessLab.ChurnSupervisor
  @payments_supervisor BeamConsoleDemo.ProcessLab.PaymentsSupervisor
  @processor BeamConsoleDemo.ProcessLab.PaymentProcessor
  @watcher BeamConsoleDemo.ProcessLab.RelationshipWatcher

  setup do
    Enum.each(DynamicSupervisor.which_children(@churn_supervisor), fn
      {_id, pid, _type, _modules} when is_pid(pid) ->
        DynamicSupervisor.terminate_child(@churn_supervisor, pid)

      _child ->
        :ok
    end)

    :ok
  end

  test "exposes registered supervised processes and a monitor relationship" do
    processor = Process.whereis(@processor)
    watcher = Process.whereis(@watcher)

    assert is_pid(processor)
    assert is_pid(watcher)
    assert RelationshipWatcher.monitored_pid() == processor
    assert {:monitors, monitors} = Process.info(watcher, :monitors)
    assert {:process, processor} in monitors
  end

  test "starts and stops a bounded dynamic child" do
    assert {:ok, pid} = ProcessLab.start_dynamic_child()
    reference = Process.monitor(pid)

    assert ProcessLab.snapshot().dynamic_children == 1
    assert :ok = ProcessLab.stop_dynamic_child()
    assert_receive {:DOWN, ^reference, :process, ^pid, :shutdown}
    assert ProcessLab.snapshot().dynamic_children == 0
  end

  test "a killed processor is replaced by its supervisor" do
    original = Process.whereis(@processor)
    reference = Process.monitor(original)

    assert :ok = ProcessLab.restart_processor()
    assert_receive {:DOWN, ^reference, :process, ^original, :killed}

    children = Supervisor.which_children(@payments_supervisor)
    {_id, replacement, :worker, _modules} = Enum.find(children, &(elem(&1, 0) == @processor))

    assert is_pid(replacement)
    assert replacement != original
  end

  test "mailbox work and short tasks are bounded public actions" do
    assert :ok = ProcessLab.grow_mailbox(50)
    assert :ok = ProcessLab.spawn_short_tasks(5)
    assert_raise FunctionClauseError, fn -> ProcessLab.grow_mailbox(501) end
    assert_raise FunctionClauseError, fn -> ProcessLab.spawn_short_tasks(51) end
  end
end
