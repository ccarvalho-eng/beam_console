defmodule BeamConsole.Snapshot do
  @moduledoc """
  Represents one immutable, versioned sample of the visible BEAM topology.

  Entity maps are keyed by opaque BeamConsole IDs, while `index` retains the
  private lookup information needed for server-side selection.
  """

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

  @type private_index_value ::
          {:application, atom()} | {:node, String.t()} | {:process, pid()}

  @type t :: %__MODULE__{
          sequence: non_neg_integer(),
          sampled_at: DateTime.t(),
          local_node_id: String.t(),
          nodes: %{String.t() => BeamConsole.NodeInfo.t()},
          applications: %{String.t() => BeamConsole.ApplicationInfo.t()},
          processes: %{String.t() => BeamConsole.ProcessInfo.t()},
          edges: %{String.t() => BeamConsole.SupervisionEdge.t()},
          index: %{String.t() => private_index_value()},
          coverage: Coverage.t(),
          stale?: boolean()
        }
end
