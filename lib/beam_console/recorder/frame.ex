defmodule BeamConsole.Recorder.Frame do
  @moduledoc """
  Stores one compact aggregate recorder sample without retaining a runtime snapshot.

  Frames contain only scalar counts, timestamps, sequence metadata, and an
  explicit coverage state suitable for bounded in-memory history.
  """

  alias BeamConsole.Coverage
  alias BeamConsole.Snapshot

  @enforce_keys [:sequence, :sampled_at_ms, :monotonic_ms]
  defstruct sequence: 0,
            segment: 0,
            sampled_at_ms: 0,
            monotonic_ms: 0,
            process_count: 0,
            supervisor_count: 0,
            application_count: 0,
            ets_count: 0,
            coverage: :complete

  @type coverage :: :complete | :partial | :truncated
  @type t :: %__MODULE__{
          sequence: non_neg_integer(),
          segment: non_neg_integer(),
          sampled_at_ms: integer(),
          monotonic_ms: integer(),
          process_count: non_neg_integer(),
          supervisor_count: non_neg_integer(),
          application_count: non_neg_integer(),
          ets_count: non_neg_integer(),
          coverage: coverage()
        }

  @spec from_snapshot(Snapshot.t(), integer()) :: t()
  @doc "Builds a PID-free aggregate frame from one completed runtime snapshot."
  def from_snapshot(%Snapshot{} = snapshot, monotonic_ms) when is_integer(monotonic_ms) do
    %__MODULE__{
      sequence: snapshot.sequence,
      sampled_at_ms: DateTime.to_unix(snapshot.sampled_at, :millisecond),
      monotonic_ms: monotonic_ms,
      process_count: map_size(snapshot.processes),
      supervisor_count: supervisor_count(snapshot),
      application_count: map_size(snapshot.applications),
      coverage: coverage_state(snapshot.coverage)
    }
  end

  defp supervisor_count(snapshot) do
    child_supervisors =
      snapshot.edges
      |> Map.values()
      |> Enum.filter(&(&1.child_type == :supervisor and is_binary(&1.child_id)))
      |> Enum.map(& &1.child_id)

    root_supervisors =
      snapshot.applications
      |> Map.values()
      |> Enum.map(& &1.root_supervisor_id)
      |> Enum.reject(&is_nil/1)

    child_supervisors
    |> Kernel.++(root_supervisors)
    |> MapSet.new()
    |> MapSet.size()
  end

  defp coverage_state(%Coverage{traversal_limit_reached?: true}) do
    :truncated
  end

  defp coverage_state(%Coverage{process_limit_reached?: true}) do
    :truncated
  end

  defp coverage_state(%Coverage{partial_supervisors: count}) when count > 0 do
    :partial
  end

  defp coverage_state(%Coverage{}) do
    :complete
  end
end
