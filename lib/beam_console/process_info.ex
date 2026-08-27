defmodule BeamConsole.ProcessInfo do
  @moduledoc false

  @enforce_keys [:id, :node_id, :pid, :pid_text, :label]
  defstruct [
    :id,
    :node_id,
    :pid,
    :pid_text,
    :label,
    :registered_name,
    :module,
    :application,
    :supervision_application,
    :attribution,
    :memory,
    :reductions,
    :message_queue_len,
    :status
  ]

  @type t :: %__MODULE__{}
end
