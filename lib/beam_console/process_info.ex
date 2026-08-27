defmodule BeamConsole.ProcessInfo do
  @moduledoc """
  Contains the bounded metadata collected for one process in a snapshot.

  `attribution` distinguishes application ownership inferred from OTP metadata
  from ownership confirmed through supervision traversal.
  """

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

  @type attribution ::
          :unknown | :supervision_only | :otp_only | :otp_and_supervision | :conflict | nil
  @type t :: %__MODULE__{
          id: String.t(),
          node_id: String.t(),
          pid: pid(),
          pid_text: String.t(),
          label: String.t(),
          registered_name: String.t() | nil,
          module: String.t() | nil,
          application: atom() | nil,
          supervision_application: atom() | nil,
          attribution: attribution(),
          memory: non_neg_integer() | nil,
          reductions: non_neg_integer() | nil,
          message_queue_len: non_neg_integer() | nil,
          status: atom() | nil
        }
end
