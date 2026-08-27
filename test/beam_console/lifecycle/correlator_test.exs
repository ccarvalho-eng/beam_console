defmodule BeamConsole.Lifecycle.CorrelatorTest do
  use ExUnit.Case, async: true

  alias BeamConsole.EntityId
  alias BeamConsole.Lifecycle.Correlator
  alias BeamConsole.Lifecycle.Observation
  alias BeamConsole.Lifecycle.PendingExit

  test "emits strong evidence for a consecutive complete stable-slot replacement" do
    pending = pending_exit()

    assert {:replacement, event} =
             Correlator.correlate(pending, [observation(self(), 2)], context())

    assert event.kind == :replacement_observed
    assert event.evidence == :slot_reconciliation
    assert event.certainty == :strong
    assert event.related_entity_id == pending.entity_id
    assert event.entity_id == EntityId.build(:process, {node(), self()})
    assert event.details.certainty_cap == nil
    assert event.details.elapsed_ms == 100
  end

  test "records a restarting transition and caps later replacement evidence" do
    pending = pending_exit()
    restarting = observation(nil, 2, child_state: :restarting)

    assert {:pending, pending} =
             Correlator.correlate(pending, [restarting], context())

    assert pending.transition_observed?
    assert pending.transition_state == :restarting

    assert {:replacement, event} =
             Correlator.correlate(
               pending,
               [observation(self(), 3)],
               context(sequence: 3, monotonic_ms: 1_200)
             )

    assert event.certainty == :medium
    assert event.details.certainty_cap == :transitional_slot_state
  end

  test "caps incomplete and delayed observations at medium evidence" do
    pending = pending_exit()
    truncated = observation(self(), 2, coverage: :truncated)

    assert {:replacement, truncated_event} =
             Correlator.correlate(pending, [truncated], context())

    assert truncated_event.certainty == :medium
    assert truncated_event.details.certainty_cap == :replacement_observation_incomplete

    assert {:replacement, delayed_event} =
             Correlator.correlate(
               pending,
               [observation(self(), 3)],
               context(sequence: 3)
             )

    assert delayed_event.certainty == :medium
    assert delayed_event.details.certainty_cap == :nonconsecutive_observation
  end

  test "discards correlation across segment boundaries" do
    assert {:discard, :segment_changed} =
             Correlator.correlate(
               pending_exit(),
               [observation(self(), 2)],
               context(segment: 1)
             )
  end

  test "does not match another supervisor or a dynamic slot" do
    pending = pending_exit()
    other_supervisor = waiting_process()

    other_parent = observation(self(), 2, supervisor_pid: other_supervisor)
    dynamic = observation(self(), 2, slot_kind: :dynamic)

    assert {:pending, ^pending} = Correlator.correlate(pending, [other_parent], context())
    assert {:pending, ^pending} = Correlator.correlate(pending, [dynamic], context())

    send(other_supervisor, :stop)
  end

  test "keeps ambiguity explicit and never chooses a winner" do
    pending = pending_exit()
    first = waiting_process()
    second = waiting_process()

    observations = [observation(first, 2), observation(second, 2)]

    assert {:pending, ambiguous} =
             Correlator.correlate(pending, observations, context())

    assert ambiguous.ambiguity_observed?

    assert {:pending, still_ambiguous} =
             Correlator.correlate(
               ambiguous,
               [observation(first, 3)],
               context(sequence: 3, monotonic_ms: 1_200)
             )

    assert still_ambiguous.ambiguity_observed?

    send(first, :stop)
    send(second, :stop)
  end

  test "uses an inclusive correlation-window boundary" do
    pending = pending_exit(monotonic_ms: 100)
    candidate = observation(self(), 2)

    assert {:replacement, _event} =
             Correlator.correlate(
               pending,
               [candidate],
               context(monotonic_ms: 1_100, pending_slot_ms: 1_000)
             )

    assert {:discard, :expired} =
             Correlator.correlate(
               pending,
               [candidate],
               context(monotonic_ms: 1_101, pending_slot_ms: 1_000)
             )
  end

  test "does not treat the same process as its own replacement" do
    entity_id = EntityId.build(:process, {node(), self()})
    pending = pending_exit(entity_id: entity_id)

    assert {:pending, ^pending} =
             Correlator.correlate(pending, [observation(self(), 2)], context())
  end

  defp pending_exit(overrides \\ []) do
    defaults = [
      slot_id: "slot-stable",
      supervisor_pid: self(),
      entity_id: "proc-old",
      sequence: 1,
      segment: 0,
      monotonic_ms: 1_000,
      coverage: :complete
    ]

    defaults
    |> Keyword.merge(overrides)
    |> then(&struct!(PendingExit, &1))
  end

  defp observation(pid, sequence, overrides \\ []) do
    defaults = [
      slot_id: "slot-stable",
      slot_kind: :stable,
      supervisor_pid: self(),
      child_pid: pid,
      child_state: if(is_pid(pid), do: :running, else: :undefined),
      child_type: :worker,
      modules: [__MODULE__],
      sequence: sequence,
      coverage: :complete
    ]

    defaults
    |> Keyword.merge(overrides)
    |> then(&struct!(Observation, &1))
  end

  defp context(overrides \\ []) do
    [
      sequence: 2,
      segment: 0,
      monotonic_ms: 1_100,
      sampled_at_ms: 1_700_000_001_100,
      coverage: :complete,
      pending_slot_ms: 1_000
    ]
    |> Keyword.merge(overrides)
  end

  defp waiting_process do
    pid =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :kill)
      end
    end)

    pid
  end
end
