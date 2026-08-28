defmodule BeamConsole.Lifecycle.Recorder.State do
  @moduledoc """
  Carries bounded lifecycle-recorder state across mailbox transitions.

  PID-bearing watch and pending-exit maps remain private. Public status and
  queries are derived into safe scalar and retained-event values.
  """

  alias BeamConsole.Lifecycle.PendingExit
  alias BeamConsole.Lifecycle.Watch
  alias BeamConsole.Recorder.Config
  alias BeamConsole.Recorder.History

  defstruct config: nil,
            history: nil,
            recording_control: nil,
            recording_revision: 0,
            refresh_requester: nil,
            refresh_timeout: 250,
            refresh_request: nil,
            refresh_pending?: false,
            missed_reconciliations: 0,
            monotonic_clock: nil,
            system_clock: nil,
            demanded?: false,
            paused?: false,
            active?: false,
            recording_started_at_ms: nil,
            recording_started_monotonic_ms: nil,
            start_event_pending?: false,
            reset_pending?: false,
            source_epoch: nil,
            watches_by_pid: %{},
            watches_by_ref: %{},
            pending_exits: %{},
            pending_events: [],
            flush_scheduled?: false,
            reconcile_scheduled?: false,
            eligible: 0,
            omitted: 0,
            deferred: 0

  @type clock :: (-> integer())
  @type refresh_requester :: (-> term()) | nil
  @type refresh_request :: %{
          pid: pid(),
          monitor_ref: reference(),
          timeout_ref: reference(),
          outcome: :ok | :error | nil,
          timed_out?: boolean(),
          cancelled?: boolean()
        }

  @type t :: %__MODULE__{
          config: Config.t(),
          history: History.t(),
          recording_control: GenServer.server() | nil,
          recording_revision: non_neg_integer(),
          refresh_requester: refresh_requester(),
          refresh_timeout: pos_integer(),
          refresh_request: refresh_request() | nil,
          refresh_pending?: boolean(),
          missed_reconciliations: non_neg_integer(),
          monotonic_clock: clock(),
          system_clock: clock(),
          demanded?: boolean(),
          paused?: boolean(),
          active?: boolean(),
          recording_started_at_ms: integer() | nil,
          recording_started_monotonic_ms: integer() | nil,
          start_event_pending?: boolean(),
          reset_pending?: boolean(),
          source_epoch: String.t() | nil,
          watches_by_pid: %{pid() => Watch.t()},
          watches_by_ref: %{reference() => pid()},
          pending_exits: %{String.t() => PendingExit.t()},
          pending_events: [BeamConsole.Lifecycle.Event.t()],
          flush_scheduled?: boolean(),
          reconcile_scheduled?: boolean(),
          eligible: non_neg_integer(),
          omitted: non_neg_integer(),
          deferred: non_neg_integer()
        }
end
