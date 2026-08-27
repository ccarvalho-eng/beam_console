defmodule BeamConsole.ApplicationInfo do
  @moduledoc false

  @enforce_keys [:id, :name, :node_id]
  defstruct [:id, :name, :node_id, :description, :version, :root_supervisor_id]

  @type t :: %__MODULE__{
          id: String.t(),
          name: atom(),
          node_id: String.t(),
          description: String.t() | nil,
          version: String.t() | nil,
          root_supervisor_id: String.t() | nil
        }
end
