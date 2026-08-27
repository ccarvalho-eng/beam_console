defmodule BeamConsole.Coverage do
  @moduledoc false

  defstruct total_pids: 0,
            inspected_pids: 0,
            vanished_pids: 0,
            process_limit_reached?: false,
            traversal_limit_reached?: false,
            partial_supervisors: 0,
            duration_ms: 0,
            warnings: []

  @type t :: %__MODULE__{}
end
