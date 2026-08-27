defmodule BeamConsole.Lifecycle.Watch do
  @moduledoc """
  Stores ephemeral metadata for one actively monitored supervised process.

  Watches may contain local PIDs and monitor references, but they are never
  retained in recorder history or returned through the public API.
  """

  @enforce_keys [
    :pid,
    :monitor_ref,
    :entity_id,
    :slot_id,
    :slot_kind,
    :supervisor_pid,
    :last_sequence
  ]
  defstruct pid: nil,
            monitor_ref: nil,
            entity_id: "",
            slot_id: "",
            slot_kind: :stable,
            supervisor_pid: nil,
            child_type: nil,
            modules: [],
            last_sequence: 0,
            coverage: :complete,
            complete_omissions: 0

  @type t :: %__MODULE__{
          pid: pid(),
          monitor_ref: reference(),
          entity_id: String.t(),
          slot_id: String.t(),
          slot_kind: :stable | :dynamic,
          supervisor_pid: pid(),
          child_type: :supervisor | :worker | nil,
          modules: [module()],
          last_sequence: non_neg_integer(),
          coverage: :complete | :partial | :truncated,
          complete_omissions: non_neg_integer()
        }
end
