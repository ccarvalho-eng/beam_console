defmodule BeamConsole.ProcessDetail do
  @moduledoc false

  @enforce_keys [:id, :pid_text, :label]
  defstruct [
    :id,
    :pid_text,
    :label,
    :registered_name,
    :module,
    :current_function,
    :application,
    :memory,
    :reductions,
    :message_queue_len,
    :status,
    :last_seen_at,
    links: [],
    monitors: [],
    monitored_by: []
  ]

  @type t :: %__MODULE__{}
end
