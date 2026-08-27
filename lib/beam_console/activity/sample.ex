defmodule BeamConsole.Activity.Sample do
  @moduledoc """
  Stores one bounded process-activity sample for aggregate and top-mover views.

  Activity samples contain scalar deltas and opaque entity IDs rather than
  process structs or historical snapshots.
  """

  @enforce_keys [:sequence, :sampled_at_ms, :monotonic_ms]
  defstruct sequence: 0,
            segment: 0,
            sampled_at_ms: 0,
            monotonic_ms: 0,
            aggregates: %{},
            top_movers: [],
            omitted: 0

  @type metric :: :reductions_per_second | :mailbox_delta | :memory_delta
  @type mover :: %{
          required(:entity_id) => String.t(),
          required(:metric) => metric(),
          required(:value) => number(),
          optional(:label) => String.t()
        }
  @type t :: %__MODULE__{
          sequence: non_neg_integer(),
          segment: non_neg_integer(),
          sampled_at_ms: integer(),
          monotonic_ms: integer(),
          aggregates: %{optional(metric()) => number()},
          top_movers: [mover()],
          omitted: non_neg_integer()
        }
end
