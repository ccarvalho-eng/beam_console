defmodule BeamConsole.NodeInfo do
  @moduledoc false

  @enforce_keys [:id, :name, :kind, :inspectable?]
  defstruct [:id, :name, :kind, :inspectable?]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          kind: :local | :connected,
          inspectable?: boolean()
        }
end
