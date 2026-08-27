defmodule BeamConsole.NodeInfo do
  @moduledoc """
  Describes the local BEAM node or a connected node visible to it.

  Connected nodes are inventory-only until a runtime adapter explicitly marks
  them as inspectable.
  """

  @enforce_keys [:id, :name, :kind, :inspectable?]
  defstruct [:id, :name, :kind, :inspectable?]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          kind: :local | :connected,
          inspectable?: boolean()
        }
end
