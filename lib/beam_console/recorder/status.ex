defmodule BeamConsole.Recorder.Status do
  @moduledoc """
  Summarizes flight-recorder control state, coverage, and bounded history usage.

  `:inactive` means there is no current recording demand, `:recording` means
  monitors are active, and `:paused` means an operator has explicitly stopped
  recording while retained history remains available.
  """

  alias BeamConsole.Recorder.Config

  @type activity :: :inactive | :recording | :paused

  defstruct activity: :inactive,
            active?: false,
            demanded?: false,
            paused?: false,
            mode: :subscribers,
            recording_started_at_ms: nil,
            watched: 0,
            eligible: 0,
            omitted: 0,
            deferred: 0,
            pending_correlations: 0,
            history: %{
              frame_count: 0,
              event_count: 0,
              estimated_bytes: 0,
              dropped_events: 0,
              dropped_frames: 0,
              last_sequence: nil,
              segment: 0
            }

  @type t :: %__MODULE__{
          activity: activity(),
          active?: boolean(),
          demanded?: boolean(),
          paused?: boolean(),
          mode: Config.mode(),
          recording_started_at_ms: integer() | nil,
          watched: non_neg_integer(),
          eligible: non_neg_integer(),
          omitted: non_neg_integer(),
          deferred: non_neg_integer(),
          pending_correlations: non_neg_integer(),
          history: map()
        }
end
