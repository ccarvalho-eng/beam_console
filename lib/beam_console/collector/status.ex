defmodule BeamConsole.Collector.Status do
  @moduledoc """
  Describes bounded collector health without exposing raw runtime failures.

  A stale status means BeamConsole is preserving the last successful snapshot
  because a newer scan failed or timed out.
  """

  alias BeamConsole.ReasonSummary

  defstruct sequence: 0,
            sampled_at: nil,
            stale?: false,
            scanning?: false,
            subscriber_count: 0,
            last_error: nil,
            failed_at: nil

  @type t :: %__MODULE__{
          sequence: non_neg_integer(),
          sampled_at: DateTime.t() | nil,
          stale?: boolean(),
          scanning?: boolean(),
          subscriber_count: non_neg_integer(),
          last_error: ReasonSummary.t() | nil,
          failed_at: DateTime.t() | nil
        }
end
