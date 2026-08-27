defmodule BeamConsole.Runtime.Sample do
  @moduledoc """
  Stores allowlisted node-wide measurements for the recorder's Runtime view.

  The normalized value is Phoenix-independent and intentionally excludes raw
  runtime terms, process identifiers, and host paths.
  """

  @enforce_keys [:sequence, :sampled_at_ms, :monotonic_ms]
  defstruct sequence: 0,
            segment: 0,
            sampled_at_ms: 0,
            monotonic_ms: 0,
            process_count: 0,
            supervisor_count: 0,
            application_count: 0,
            ets_count: 0,
            node_count: 1,
            memory_total: nil,
            memory_processes: nil,
            memory_system: nil,
            memory_atom: nil,
            memory_binary: nil,
            memory_code: nil,
            memory_ets: nil,
            scheduler_count: nil,
            run_queue: nil,
            collector_scan_ms: nil,
            collector_partial?: false,
            recorder_event_count: 0,
            recorder_dropped: 0

  @type t :: %__MODULE__{
          sequence: non_neg_integer(),
          segment: non_neg_integer(),
          sampled_at_ms: integer(),
          monotonic_ms: integer(),
          process_count: non_neg_integer(),
          supervisor_count: non_neg_integer(),
          application_count: non_neg_integer(),
          ets_count: non_neg_integer(),
          node_count: non_neg_integer(),
          memory_total: non_neg_integer() | nil,
          memory_processes: non_neg_integer() | nil,
          memory_system: non_neg_integer() | nil,
          memory_atom: non_neg_integer() | nil,
          memory_binary: non_neg_integer() | nil,
          memory_code: non_neg_integer() | nil,
          memory_ets: non_neg_integer() | nil,
          scheduler_count: pos_integer() | nil,
          run_queue: non_neg_integer() | nil,
          collector_scan_ms: non_neg_integer() | nil,
          collector_partial?: boolean(),
          recorder_event_count: non_neg_integer(),
          recorder_dropped: non_neg_integer()
        }
end
