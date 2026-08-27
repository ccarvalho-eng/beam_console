defmodule BeamConsole.Snapshot do
  @moduledoc """
  Represents one immutable, versioned sample of the visible BEAM topology.

  Entity maps are keyed by opaque BeamConsole IDs, while `index` retains the
  private lookup information needed for server-side selection.
  """

  alias BeamConsole.Coverage
  alias BeamConsole.Lifecycle.Observation

  @enforce_keys [:sequence, :sampled_at, :local_node_id]
  defstruct sequence: 0,
            sampled_at: nil,
            monotonic_ms: nil,
            local_node_id: nil,
            nodes: %{},
            applications: %{},
            processes: %{},
            edges: %{},
            index: %{},
            lifecycle_observations: [],
            runtime_sample: nil,
            coverage: %Coverage{},
            collector_epoch: nil,
            stale?: false

  @type private_index_value ::
          {:application, atom()} | {:node, String.t()} | {:process, pid()}

  @type t :: %__MODULE__{
          sequence: non_neg_integer(),
          sampled_at: DateTime.t(),
          monotonic_ms: integer() | nil,
          local_node_id: String.t(),
          nodes: %{String.t() => BeamConsole.NodeInfo.t()},
          applications: %{String.t() => BeamConsole.ApplicationInfo.t()},
          processes: %{String.t() => BeamConsole.ProcessInfo.t()},
          edges: %{String.t() => BeamConsole.SupervisionEdge.t()},
          index: %{String.t() => private_index_value()},
          lifecycle_observations: [Observation.t()],
          runtime_sample: BeamConsole.Runtime.Sample.t() | nil,
          coverage: Coverage.t(),
          collector_epoch: String.t() | nil,
          stale?: boolean()
        }
end
