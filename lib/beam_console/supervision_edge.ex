defmodule BeamConsole.SupervisionEdge do
  @moduledoc false

  @enforce_keys [:id, :parent_id, :child_id, :label, :state]
  defstruct [:id, :parent_id, :child_id, :label, :state, :child_type]

  @type t :: %__MODULE__{}
end
