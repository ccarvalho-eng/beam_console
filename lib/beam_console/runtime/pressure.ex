defmodule BeamConsole.Runtime.Pressure do
  @moduledoc """
  Stores low-overhead, node-wide runtime pressure measurements.

  Values are fixed-shape scalars collected from public ERTS APIs. The struct
  excludes scheduler-wall-time data, allocator details, port and socket
  identities, paths, and other runtime terms that would add cost or expose host
  details.
  """

  defstruct uptime_ms: nil,
            port_count: nil,
            port_limit: nil,
            process_limit: nil,
            scheduler_total: nil,
            scheduler_online: nil,
            dirty_cpu_scheduler_total: nil,
            dirty_cpu_scheduler_online: nil,
            dirty_io_scheduler_total: nil,
            run_queue_total: nil,
            run_queue_cpu: nil,
            run_queue_io: nil,
            io_input_bytes: nil,
            io_output_bytes: nil

  @type measurement :: non_neg_integer() | nil
  @type run_queues :: %{
          total: non_neg_integer(),
          cpu: non_neg_integer(),
          io: non_neg_integer()
        }
  @type t :: %__MODULE__{
          uptime_ms: measurement(),
          port_count: measurement(),
          port_limit: measurement(),
          process_limit: measurement(),
          scheduler_total: measurement(),
          scheduler_online: measurement(),
          dirty_cpu_scheduler_total: measurement(),
          dirty_cpu_scheduler_online: measurement(),
          dirty_io_scheduler_total: measurement(),
          run_queue_total: measurement(),
          run_queue_cpu: measurement(),
          run_queue_io: measurement(),
          io_input_bytes: measurement(),
          io_output_bytes: measurement()
        }

  @doc """
  Partitions configured, dirty CPU, and dirty I/O run-queue lengths.

  ERTS returns one normal queue per configured scheduler followed by one shared
  dirty CPU queue and one shared dirty I/O queue.

  ## Examples

      iex> BeamConsole.Runtime.Pressure.partition_run_queues([1, 2, 3, 4], 2)
      {:ok, %{total: 10, cpu: 6, io: 4}}
  """
  @spec partition_run_queues([non_neg_integer()], pos_integer()) ::
          {:ok, run_queues()} | :error
  def partition_run_queues(lengths, scheduler_total)
      when is_list(lengths) and is_integer(scheduler_total) and scheduler_total > 0 do
    with true <- length(lengths) == scheduler_total + 2,
         true <- Enum.all?(lengths, &(is_integer(&1) and &1 >= 0)),
         {normal_queues, [dirty_cpu_queue, dirty_io_queue]} <-
           Enum.split(lengths, scheduler_total) do
      cpu = Enum.sum(normal_queues) + dirty_cpu_queue
      {:ok, %{total: cpu + dirty_io_queue, cpu: cpu, io: dirty_io_queue}}
    else
      _other -> :error
    end
  end

  def partition_run_queues(_lengths, _scheduler_total) do
    :error
  end
end
