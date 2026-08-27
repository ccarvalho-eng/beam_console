defmodule BeamConsole.ProcessDetail do
  @moduledoc """
  Contains the allowlisted details returned for a selected local process.

  Messages, dictionaries, stacktraces, arbitrary state, and encoded Erlang
  terms are intentionally excluded.
  """

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

  @type relation :: String.t()
  @type t :: %__MODULE__{
          id: String.t(),
          pid_text: String.t(),
          label: String.t(),
          registered_name: String.t() | nil,
          module: String.t() | nil,
          current_function: String.t() | nil,
          application: atom() | nil,
          memory: non_neg_integer() | nil,
          reductions: non_neg_integer() | nil,
          message_queue_len: non_neg_integer() | nil,
          status: atom() | nil,
          last_seen_at: DateTime.t() | nil,
          links: [relation()],
          monitors: [relation()],
          monitored_by: [relation()]
        }
end
