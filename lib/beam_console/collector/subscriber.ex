defmodule BeamConsole.Collector.Subscriber do
  @moduledoc """
  Tracks bounded version delivery state for one monitored collector subscriber.

  A subscriber can have one outstanding notification and one replaceable
  pending sequence regardless of how many snapshots commit while it is stalled.
  """

  @enforce_keys [:monitor_ref]
  defstruct monitor_ref: nil,
            outstanding_sequence: nil,
            pending_sequence: nil,
            last_acked_sequence: 0

  @type t :: %__MODULE__{
          monitor_ref: reference(),
          outstanding_sequence: non_neg_integer() | nil,
          pending_sequence: non_neg_integer() | nil,
          last_acked_sequence: non_neg_integer()
        }
end
