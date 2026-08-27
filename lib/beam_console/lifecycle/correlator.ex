defmodule BeamConsole.Lifecycle.Correlator do
  @moduledoc """
  Conservatively correlates direct exits with stable-slot replacement observations.

  Correlation requires the same opaque slot and supervisor PID in one recorder
  segment. The configured time window is inclusive: a candidate exactly at the
  boundary may match, while a candidate one millisecond later is discarded.
  Dynamic slots, module-only similarity, and ambiguous targets are never paired.
  """

  alias BeamConsole.EntityId
  alias BeamConsole.Lifecycle.Event
  alias BeamConsole.Lifecycle.Observation
  alias BeamConsole.Lifecycle.PendingExit

  @type discard_reason :: :expired | :segment_changed
  @type result ::
          {:replacement, Event.t()}
          | {:pending, PendingExit.t()}
          | {:discard, discard_reason()}

  @spec correlate(PendingExit.t(), [Observation.t()], keyword()) :: result()
  @doc """
  Evaluates one pending stable-slot exit against a completed observation batch.

  Required context keys are `:sequence`, `:segment`, `:monotonic_ms`,
  `:sampled_at_ms`, `:coverage`, and `:pending_slot_ms`.
  """
  def correlate(%PendingExit{} = pending, observations, context)
      when is_list(observations) and is_list(context) do
    sequence = Keyword.fetch!(context, :sequence)
    segment = Keyword.fetch!(context, :segment)
    monotonic_ms = Keyword.fetch!(context, :monotonic_ms)
    pending_slot_ms = Keyword.fetch!(context, :pending_slot_ms)

    cond do
      segment != pending.segment ->
        {:discard, :segment_changed}

      monotonic_ms - pending.monotonic_ms > pending_slot_ms ->
        {:discard, :expired}

      pending.ambiguity_observed? ->
        {:pending, pending}

      true ->
        pending
        |> matching_observations(observations, sequence)
        |> resolve(pending, context)
    end
  end

  defp matching_observations(pending, observations, sequence) do
    Enum.filter(observations, fn observation ->
      observation.slot_kind == :stable and
        observation.slot_id == pending.slot_id and
        observation.supervisor_pid == pending.supervisor_pid and
        observation.sequence == sequence
    end)
  end

  defp resolve(observations, pending, context) do
    running =
      observations
      |> Enum.filter(&(&1.child_state == :running and is_pid(&1.child_pid)))
      |> Enum.uniq_by(&EntityId.build(:process, {node(&1.child_pid), &1.child_pid}))

    transitions =
      Enum.filter(observations, &(&1.child_state in [:restarting, :undefined]))

    pending = record_transition(pending, transitions)

    case running do
      [] ->
        {:pending, pending}

      [observation] ->
        resolve_candidate(pending, observation, context)

      _multiple ->
        {:pending, %{pending | ambiguity_observed?: true}}
    end
  end

  defp resolve_candidate(pending, observation, context) do
    entity_id = EntityId.build(:process, {node(observation.child_pid), observation.child_pid})

    if entity_id == pending.entity_id do
      {:pending, pending}
    else
      certainty = certainty(pending, observation, context)
      {:replacement, replacement_event(pending, observation, entity_id, certainty, context)}
    end
  end

  defp certainty(pending, observation, context) do
    cap_reason = certainty_cap_reason(pending, observation, context)
    {if(is_nil(cap_reason), do: :strong, else: :medium), cap_reason}
  end

  defp certainty_cap_reason(%PendingExit{transition_observed?: true}, _observation, _context) do
    :transitional_slot_state
  end

  defp certainty_cap_reason(%PendingExit{coverage: coverage}, _observation, _context)
       when coverage != :complete do
    :exit_observation_incomplete
  end

  defp certainty_cap_reason(_pending, %Observation{coverage: coverage}, _context)
       when coverage != :complete do
    :replacement_observation_incomplete
  end

  defp certainty_cap_reason(pending, _observation, context) do
    coverage = Keyword.fetch!(context, :coverage)
    sequence = Keyword.fetch!(context, :sequence)

    cond do
      coverage != :complete -> :snapshot_incomplete
      sequence != pending.sequence + 1 -> :nonconsecutive_observation
      true -> nil
    end
  end

  defp replacement_event(pending, observation, entity_id, {certainty, cap_reason}, context) do
    sequence = Keyword.fetch!(context, :sequence)
    segment = Keyword.fetch!(context, :segment)
    monotonic_ms = Keyword.fetch!(context, :monotonic_ms)

    %Event{
      id:
        EntityId.build(
          :event,
          {:replacement_observed, pending.slot_id, pending.entity_id, entity_id, sequence}
        ),
      kind: :replacement_observed,
      sequence: sequence,
      segment: segment,
      observed_at_ms: Keyword.fetch!(context, :sampled_at_ms),
      monotonic_ms: monotonic_ms,
      entity_id: entity_id,
      related_entity_id: pending.entity_id,
      label: "Replacement observed",
      node_id: EntityId.build(:node, node(observation.child_pid)),
      evidence: :slot_reconciliation,
      certainty: certainty,
      details: %{
        slot_id: pending.slot_id,
        previous_sequence: pending.sequence,
        current_sequence: sequence,
        elapsed_ms: monotonic_ms - pending.monotonic_ms,
        previous_coverage: pending.coverage,
        current_coverage: Keyword.fetch!(context, :coverage),
        transition_state: pending.transition_state,
        certainty_cap: cap_reason
      }
    }
  end

  defp record_transition(pending, []) do
    pending
  end

  defp record_transition(pending, transitions) do
    transition = Enum.min_by(transitions, &transition_rank(&1.child_state))

    %{
      pending
      | transition_observed?: true,
        transition_state: transition.child_state
    }
  end

  defp transition_rank(:restarting) do
    0
  end

  defp transition_rank(:undefined) do
    1
  end
end
