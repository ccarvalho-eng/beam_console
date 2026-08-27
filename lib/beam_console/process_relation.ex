defmodule BeamConsole.ProcessRelation do
  @moduledoc "Represents one allowlisted process inspector relationship without retaining a PID."

  @enforce_keys [:label, :kind]
  defstruct [:id, :label, :kind]

  @type kind :: :process | :port | :opaque
  @type t :: %__MODULE__{
          id: String.t() | nil,
          label: String.t(),
          kind: kind()
        }
end
