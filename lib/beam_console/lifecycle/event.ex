defmodule BeamConsole.Lifecycle.Event do
  @moduledoc """
  Describes one safe, retained observation in the process lifecycle timeline.

  Events distinguish their evidence source and certainty. They contain opaque
  entity IDs and bounded display data, never PIDs or raw exit terms.
  """

  alias BeamConsole.ReasonSummary

  @enforce_keys [
    :id,
    :kind,
    :sequence,
    :segment,
    :observed_at_ms,
    :monotonic_ms,
    :evidence,
    :certainty
  ]
  defstruct id: "",
            kind: :observed_start,
            sequence: 0,
            segment: 0,
            observed_at_ms: 0,
            monotonic_ms: 0,
            entity_id: nil,
            related_entity_id: nil,
            label: nil,
            node_id: nil,
            application: nil,
            evidence: :snapshot_diff,
            certainty: :sampled,
            reason: nil

  @type kind ::
          :recording_started
          | :reset
          | :gap
          | :observed_start
          | :observed_stop
          | :terminated
          | :replacement_observed
          | :topology_added
          | :topology_removed
          | :mailbox_growth
          | :connection_lost
  @type evidence :: :monitor | :slot_reconciliation | :snapshot_diff | :recorder | :connection
  @type certainty :: :direct | :strong | :sampled | :missed | :partial | :ambiguous
  @type t :: %__MODULE__{
          id: String.t(),
          kind: kind(),
          sequence: non_neg_integer(),
          segment: non_neg_integer(),
          observed_at_ms: integer(),
          monotonic_ms: integer(),
          entity_id: String.t() | nil,
          related_entity_id: String.t() | nil,
          label: String.t() | nil,
          node_id: String.t() | nil,
          application: String.t() | nil,
          evidence: evidence(),
          certainty: certainty(),
          reason: ReasonSummary.t() | nil
        }
end
