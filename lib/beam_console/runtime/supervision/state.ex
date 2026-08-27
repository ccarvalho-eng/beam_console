defmodule BeamConsole.Runtime.Supervision.State do
  @moduledoc """
  Carries immutable accumulation state through one bounded supervision traversal.

  Keeping traversal state named and typed makes each limit and partial-result
  transition explicit.
  """

  alias BeamConsole.Lifecycle.Observation
  alias BeamConsole.SupervisionEdge

  defstruct edges: %{},
            attribution: %{},
            observations: [],
            visited: %{},
            partial: 0,
            children: 0,
            reached_limit?: false

  @type t :: %__MODULE__{
          edges: %{String.t() => SupervisionEdge.t()},
          attribution: %{String.t() => atom()},
          observations: [Observation.t()],
          visited: %{pid() => true},
          partial: non_neg_integer(),
          children: non_neg_integer(),
          reached_limit?: boolean()
        }
end
