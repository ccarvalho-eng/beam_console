defmodule BeamConsole.ApplicationInfo do
  @moduledoc """
  Describes an OTP application observed in a runtime snapshot.

  `root_supervisor_id` is present when BeamConsole can associate the
  application's master process with a process in the sampled topology.
  """

  @enforce_keys [:id, :name, :node_id]
  defstruct [
    :id,
    :name,
    :node_id,
    :description,
    :version,
    :root_supervisor_id,
    required_applications: [],
    origin: :unknown
  ]

  @type origin :: :otp | :external | :unknown

  @type t :: %__MODULE__{
          id: String.t(),
          name: atom(),
          node_id: String.t(),
          description: String.t() | nil,
          version: String.t() | nil,
          root_supervisor_id: String.t() | nil,
          required_applications: [atom()],
          origin: origin()
        }
end
