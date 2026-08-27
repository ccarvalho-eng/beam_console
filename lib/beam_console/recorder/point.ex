defmodule BeamConsole.Recorder.Point do
  @moduledoc """
  Stores one scalar process-series measurement in bounded recorder history.

  Points use opaque entity IDs and explicit segment metadata so renderers can
  preserve gaps without retaining PIDs or process structs.
  """

  @enforce_keys [:entity_id, :sampled_at_ms, :monotonic_ms, :value]
  defstruct entity_id: "",
            sampled_at_ms: 0,
            monotonic_ms: 0,
            segment: 0,
            value: 0

  @type t :: %__MODULE__{
          entity_id: String.t(),
          sampled_at_ms: integer(),
          monotonic_ms: integer(),
          segment: non_neg_integer(),
          value: number() | nil
        }
end
