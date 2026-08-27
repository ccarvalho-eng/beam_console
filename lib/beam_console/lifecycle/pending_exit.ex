defmodule BeamConsole.Lifecycle.PendingExit do
  @moduledoc """
  Holds short-lived private evidence for a stable child slot awaiting replacement.

  The value is capped by the watch limit, expires after the configured
  correlation window, and is never exposed to a browser because it contains a
  supervisor PID.
  """

  @enforce_keys [
    :slot_id,
    :supervisor_pid,
    :entity_id,
    :sequence,
    :segment,
    :monotonic_ms,
    :coverage
  ]
  defstruct slot_id: "",
            supervisor_pid: nil,
            entity_id: "",
            sequence: 0,
            segment: 0,
            monotonic_ms: 0,
            coverage: :complete,
            transition_observed?: false,
            transition_state: nil,
            ambiguity_observed?: false

  @type t :: %__MODULE__{
          slot_id: String.t(),
          supervisor_pid: pid(),
          entity_id: String.t(),
          sequence: non_neg_integer(),
          segment: non_neg_integer(),
          monotonic_ms: integer(),
          coverage: :complete | :partial | :truncated,
          transition_observed?: boolean(),
          transition_state: :restarting | :undefined | nil,
          ambiguity_observed?: boolean()
        }
end
