defmodule BeamConsole.Snapshot do
  @moduledoc false

  alias BeamConsole.Coverage

  @enforce_keys [:sequence, :sampled_at, :local_node_id]
  defstruct sequence: 0,
            sampled_at: nil,
            local_node_id: nil,
            nodes: %{},
            applications: %{},
            processes: %{},
            edges: %{},
            index: %{},
            coverage: %Coverage{},
            stale?: false

  @type t :: %__MODULE__{}
end
