defmodule BeamConsole.ApplicationInfo do
  @moduledoc """
  Describes an OTP application observed in a runtime snapshot.

  `root_supervisor_id` is present when BeamConsole can associate the
  application's master process with a process in the sampled topology.
  """

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
