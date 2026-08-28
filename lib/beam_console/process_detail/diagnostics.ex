defmodule BeamConsole.ProcessDetail.Diagnostics do
  @moduledoc """
  Contains bounded, read-only scheduling and memory diagnostics for a process.

  The struct intentionally excludes mailbox contents, process dictionaries,
  stacktraces, and arbitrary process state.
  """

  alias BeamConsole.ProcessRelation

  defstruct [
    :initial_call,
    :trap_exit,
    :priority,
    :group_leader,
    :total_heap_size,
    :heap_size,
    :stack_size,
    :minor_gcs,
    :fullsweep_after
  ]

  @type priority :: :low | :normal | :high | :max
  @type t :: %__MODULE__{
          initial_call: String.t() | nil,
          trap_exit: boolean() | nil,
          priority: priority() | nil,
          group_leader: ProcessRelation.t() | nil,
          total_heap_size: non_neg_integer() | nil,
          heap_size: non_neg_integer() | nil,
          stack_size: non_neg_integer() | nil,
          minor_gcs: non_neg_integer() | nil,
          fullsweep_after: non_neg_integer() | nil
        }
end
