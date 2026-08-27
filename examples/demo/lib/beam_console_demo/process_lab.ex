defmodule BeamConsoleDemo.ProcessLab do
  @moduledoc false

  alias BeamConsoleDemo.ProcessLab.EphemeralWorker
  alias BeamConsoleDemo.ProcessLab.QueueWorker

  @dynamic_supervisor BeamConsoleDemo.ProcessLab.ChurnSupervisor
  @processor BeamConsoleDemo.ProcessLab.PaymentProcessor
  @queue_worker BeamConsoleDemo.ProcessLab.QueueWorker
  @task_supervisor BeamConsoleDemo.ProcessLab.TaskSupervisor

  def snapshot do
    dynamic_children = DynamicSupervisor.which_children(@dynamic_supervisor)

    %{
      dynamic_children: length(dynamic_children),
      processor: process_summary(Process.whereis(@processor)),
      queue_worker: process_summary(Process.whereis(@queue_worker))
    }
  end

  def start_dynamic_child do
    child_id = System.unique_integer([:positive, :monotonic])
    DynamicSupervisor.start_child(@dynamic_supervisor, {EphemeralWorker, child_id})
  end

  def stop_dynamic_child do
    case DynamicSupervisor.which_children(@dynamic_supervisor) do
      [{_id, pid, _type, _modules} | _rest] when is_pid(pid) ->
        DynamicSupervisor.terminate_child(@dynamic_supervisor, pid)

      _other ->
        {:error, :not_found}
    end
  end

  def restart_processor do
    case Process.whereis(@processor) do
      nil ->
        {:error, :not_found}

      pid ->
        Process.exit(pid, :kill)
        :ok
    end
  end

  def grow_mailbox(count \\ 250) when is_integer(count) and count in 1..500 do
    QueueWorker.enqueue(@queue_worker, count)
  end

  def spawn_short_tasks(count \\ 20) when is_integer(count) and count in 1..50 do
    results =
      Enum.map(1..count, fn task_number ->
        Task.Supervisor.start_child(@task_supervisor, fn ->
          receive do
            :finish -> task_number
          after
            750 -> task_number
          end
        end)
      end)

    if Enum.all?(results, &match?({:ok, _pid}, &1)) do
      :ok
    else
      {:error, :task_start_failed}
    end
  end

  defp process_summary(nil) do
    %{alive?: false, mailbox: 0, pid: "unavailable"}
  end

  defp process_summary(pid) do
    info = Process.info(pid, [:message_queue_len]) || []

    %{
      alive?: Process.alive?(pid),
      mailbox: info[:message_queue_len] || 0,
      pid: inspect(pid)
    }
  end
end
