defmodule BeamConsole.Lifecycle.Observation do
  @moduledoc """
  Carries an ephemeral server-side supervision observation to the recorder.

  This is the only lifecycle value that contains actual PIDs. It is used to
  install local monitors and must never be retained in history, encoded for a
  client, or reconstructed from an opaque browser entity ID.
  """

  @enforce_keys [:slot_id, :slot_kind, :supervisor_pid, :child_state, :sequence]
  defstruct slot_id: "",
            slot_kind: :stable,
            supervisor_pid: nil,
            child_pid: nil,
            child_state: :missing,
            child_type: nil,
            modules: [],
            sequence: 0,
            coverage: :complete

  @type slot_kind :: :stable | :dynamic
  @type coverage :: :complete | :partial | :truncated
  @type child_state :: :running | :restarting | :undefined | :missing
  @type t :: %__MODULE__{
          slot_id: String.t(),
          slot_kind: slot_kind(),
          supervisor_pid: pid(),
          child_pid: pid() | nil,
          child_state: child_state(),
          child_type: :supervisor | :worker | nil,
          modules: [module()],
          sequence: non_neg_integer(),
          coverage: coverage()
        }
end
