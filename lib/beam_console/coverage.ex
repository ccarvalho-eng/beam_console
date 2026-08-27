defmodule BeamConsole.Coverage do
  @moduledoc """
  Records how complete and expensive a runtime snapshot was.

  Limits and vanished processes are represented explicitly so callers can
  distinguish a complete snapshot from a bounded or partial one.
  """

  defstruct total_pids: 0,
            inspected_pids: 0,
            vanished_pids: 0,
            process_limit_reached?: false,
            traversal_limit_reached?: false,
            partial_supervisors: 0,
            duration_ms: 0,
            warnings: []

  @type t :: %__MODULE__{
          total_pids: non_neg_integer(),
          inspected_pids: non_neg_integer(),
          vanished_pids: non_neg_integer(),
          process_limit_reached?: boolean(),
          traversal_limit_reached?: boolean(),
          partial_supervisors: non_neg_integer(),
          duration_ms: non_neg_integer(),
          warnings: [String.t()]
        }
end
