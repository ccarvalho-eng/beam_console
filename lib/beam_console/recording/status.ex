defmodule BeamConsole.Recording.Status do
  @moduledoc "Describes the authoritative operator recording control state."

  @enforce_keys [:paused?, :revision]
  defstruct paused?: false, revision: 0

  @type t :: %__MODULE__{
          paused?: boolean(),
          revision: non_neg_integer()
        }
end
