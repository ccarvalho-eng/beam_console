defmodule BeamConsole.ProcessDetail do
  @moduledoc """
  Contains the allowlisted details returned for a selected local process.

  Messages, dictionaries, stacktraces, arbitrary state, and encoded Erlang
  terms are intentionally excluded.
  """

  alias BeamConsole.ProcessRelation
  alias BeamConsole.ProcessDetail.Diagnostics

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
    :diagnostics,
    links: [],
    monitors: [],
    monitored_by: [],
    relationship_counts: %{links: 0, monitors: 0, monitored_by: 0},
    relationship_omitted: %{links: 0, monitors: 0, monitored_by: 0}
  ]

  @type relationship_counts :: %{
          links: non_neg_integer(),
          monitors: non_neg_integer(),
          monitored_by: non_neg_integer()
        }

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
          diagnostics: Diagnostics.t() | nil,
          links: [ProcessRelation.t()],
          monitors: [ProcessRelation.t()],
          monitored_by: [ProcessRelation.t()],
          relationship_counts: relationship_counts(),
          relationship_omitted: relationship_counts()
        }
end
