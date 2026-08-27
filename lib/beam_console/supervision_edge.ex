defmodule BeamConsole.SupervisionEdge do
  @moduledoc """
  Describes an observed parent-child relationship in an OTP supervision tree.

  A child ID can be absent when the supervisor reports a child specification
  without a currently running process.
  """

  @enforce_keys [:id, :parent_id, :child_id, :label, :state]
  defstruct [:id, :parent_id, :child_id, :label, :state, :child_type]

  @type t :: %__MODULE__{
          id: String.t(),
          parent_id: String.t(),
          child_id: String.t() | nil,
          label: String.t(),
          state: :running | :restarting | :undefined | :missing,
          child_type: :supervisor | :worker | nil
        }
end
