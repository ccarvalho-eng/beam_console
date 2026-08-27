defmodule BeamConsole.Lifecycle.Recorder do
  @moduledoc """
  Monitors a bounded set of local supervised processes and records safe exits.

  Recording is lazy by default: the first console subscriber activates watches
  and the last subscriber removes them. In `:always` mode the recorder remains
  active for the application lifetime. Snapshot observations are consumed from
  the collector's existing supervision traversal; this process never calls a
  supervisor or retains a runtime snapshot.
  """

  use GenServer

  alias BeamConsole.EntityId
  alias BeamConsole.Lifecycle.Correlator
  alias BeamConsole.Lifecycle.Event
  alias BeamConsole.Lifecycle.Observation
  alias BeamConsole.Lifecycle.PendingExit
  alias BeamConsole.Lifecycle.Recorder.State
  alias BeamConsole.Lifecycle.Watch
  alias BeamConsole.ReasonSummary
  alias BeamConsole.Recorder.Config
  alias BeamConsole.Recorder.Frame
  alias BeamConsole.Recorder.History
  alias BeamConsole.Recorder.Query
  alias BeamConsole.Recorder.Status

  @type status :: Status.t()

  @spec start_link(keyword()) :: GenServer.on_start()
  @doc "Starts a lifecycle recorder with optional name, limits, clocks, and collector overrides."
  def start_link(options \\ []) do
    name = Keyword.get(options, :name, __MODULE__)
    GenServer.start_link(__MODULE__, options, name: name)
  end

  @spec activate(GenServer.server()) :: :ok
  @doc "Activates lazy recording when the first console subscriber connects."
  def activate(server \\ __MODULE__) do
    GenServer.cast(server, :activate)
  end

  @spec deactivate(GenServer.server()) :: :ok
  @doc "Deactivates lazy recording and removes its process monitors."
  def deactivate(server \\ __MODULE__) do
    GenServer.cast(server, :deactivate)
  end

  @spec pause(GenServer.server()) :: Status.t()
  @doc "Pauses recording until an operator explicitly resumes it."
  def pause(server \\ __MODULE__) do
    GenServer.call(server, :pause)
  end

  @spec resume(GenServer.server()) :: Status.t()
  @doc "Resumes recording when subscriber or always-on demand is present."
  def resume(server \\ __MODULE__) do
    GenServer.call(server, :resume)
  end

  @spec observe(Frame.t(), [Observation.t()], keyword(), GenServer.server()) :: :ok
  @doc "Reconciles one bounded private observation batch from a completed collector frame."
  def observe(frame, observations, options \\ [], server \\ __MODULE__)
      when is_list(observations) and is_list(options) do
    GenServer.cast(server, {:observe, frame, observations, options})
  end

  @spec status(GenServer.server()) :: status()
  @doc "Returns PID-free recorder activity, coverage, and bounded-history statistics."
  def status(server \\ __MODULE__) do
    GenServer.call(server, :status)
  end

  @spec events(keyword(), GenServer.server()) :: Query.t()
  @doc "Returns a newest-first bounded lifecycle-event window with omission metadata."
  def events(options \\ [], server \\ __MODULE__) do
    GenServer.call(server, {:events, options})
  end

  @spec samples(keyword(), GenServer.server()) :: Query.t()
  @doc "Returns newest aggregate recorder frames under the configured history cap."
  def samples(options \\ [], server \\ __MODULE__) do
    GenServer.call(server, {:samples, options})
  end

  @impl true
  def init(options) do
    config = recorder_config(Keyword.get(options, :config))
    monotonic_clock = Keyword.get(options, :monotonic_clock, &monotonic_ms/0)
    system_clock = Keyword.get(options, :system_clock, &system_ms/0)

    state = %State{
      config: config,
      history: History.new(config),
      collector: Keyword.get(options, :collector, BeamConsole.Collector),
      monotonic_clock: monotonic_clock,
      system_clock: system_clock,
      demanded?: config.mode == :always
    }

    {:ok, if(config.mode == :always, do: start_recording(state), else: state)}
  end

  @impl true
  def handle_call(:status, _from, state) do
    state = state |> flush_pending_events() |> prune_history()
    {:reply, status_from_state(state), state}
  end

  def handle_call(:pause, _from, state) do
    state = state |> flush_pending_events() |> Map.put(:paused?, true) |> stop_recording()
    {:reply, status_from_state(state), state}
  end

  def handle_call(:resume, _from, state) do
    state = %{state | paused?: false}
    state = if state.demanded?, do: start_recording(state), else: state
    maybe_request_refresh(state)
    {:reply, status_from_state(state), state}
  end

  def handle_call({:events, options}, _from, state) do
    state = flush_pending_events(state)
    {history, result} = Query.events(state.history, options)
    {:reply, result, %{state | history: history}}
  end

  def handle_call({:samples, options}, _from, state) do
    state = flush_pending_events(state)
    {history, result} = Query.frames(state.history, options)
    {:reply, result, %{state | history: history}}
  end

  @impl true
  def handle_cast(:activate, %State{paused?: true} = state) do
    {:noreply, %{state | demanded?: true}}
  end

  def handle_cast(:activate, %State{active?: true} = state) do
    {:noreply, %{state | demanded?: true}}
  end

  def handle_cast(:activate, state) do
    {:noreply, state |> Map.put(:demanded?, true) |> start_recording()}
  end

  def handle_cast(:deactivate, %State{config: %Config{mode: :always}} = state) do
    {:noreply, %{state | demanded?: true}}
  end

  def handle_cast(:deactivate, state) do
    {:noreply, state |> Map.put(:demanded?, false) |> stop_recording()}
  end

  def handle_cast({:observe, _frame, _observations, _options}, %State{active?: false} = state) do
    {:noreply, state}
  end

  def handle_cast({:observe, %Frame{} = frame, observations, options}, state) do
    state = prune_pending_exits(state, frame.monotonic_ms)
    source_epoch = Keyword.get(options, :source_epoch)

    reset? =
      state.reset_pending? or
        Keyword.get(options, :reset?, false) or
        source_changed?(state.source_epoch, source_epoch)

    events = recording_started_events(state, frame)

    case History.append(
           state.history,
           frame,
           events,
           [],
           reset?: reset?,
           now_ms: frame.monotonic_ms
         ) do
      {:stale, history} ->
        {:noreply, %{state | history: history}}

      {:ok, history} ->
        state = %{
          state
          | history: history,
            start_event_pending?: false,
            reset_pending?: false,
            source_epoch: source_epoch || state.source_epoch
        }

        state = correlate_pending_exits(state, frame, observations)
        {:noreply, reconcile(state, frame, observations)}
    end
  end

  @impl true
  def handle_info({:DOWN, reference, :process, _pid, reason}, state) do
    case Map.pop(state.watches_by_ref, reference) do
      {nil, _watches_by_ref} ->
        {:noreply, state}

      {pid, watches_by_ref} ->
        {watch, watches_by_pid} = Map.pop!(state.watches_by_pid, pid)
        now_ms = state.monotonic_clock.()
        event = termination_event(state, watch, reason, now_ms)

        state = %{
          state
          | watches_by_pid: watches_by_pid,
            watches_by_ref: watches_by_ref,
            pending_events: [event | state.pending_events]
        }

        state = maybe_store_pending_exit(state, watch, now_ms)
        {:noreply, schedule_deferred_work(state)}
    end
  end

  def handle_info(:flush_lifecycle_events, state) do
    {:noreply, flush_pending_events(%{state | flush_scheduled?: false})}
  end

  def handle_info(:reconcile_after_down, state) do
    if state.active? and state.collector do
      BeamConsole.Collector.refresh(state.collector)
    end

    {:noreply, %{state | reconcile_scheduled?: false}}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp recorder_config(nil) do
    Config.load()
  end

  defp recorder_config(%Config{} = config) do
    config
  end

  defp recorder_config(options) when is_list(options) do
    Config.load(options)
  end

  defp source_changed?(nil, _source_epoch) do
    false
  end

  defp source_changed?(_source_epoch, nil) do
    false
  end

  defp source_changed?(source_epoch, next_source_epoch) do
    source_epoch != next_source_epoch
  end

  defp correlate_pending_exits(state, frame, observations) do
    context = [
      sequence: frame.sequence,
      segment: state.history.segment,
      monotonic_ms: frame.monotonic_ms,
      sampled_at_ms: frame.sampled_at_ms,
      coverage: frame.coverage,
      pending_slot_ms: state.config.pending_slot_ms
    ]

    {pending_exits, events} =
      state.pending_exits
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.reduce({%{}, []}, fn {slot_id, pending}, {pending_result, event_result} ->
        case Correlator.correlate(pending, observations, context) do
          {:replacement, event} ->
            {pending_result, [event | event_result]}

          {:pending, next_pending} ->
            {Map.put(pending_result, slot_id, next_pending), event_result}

          {:discard, _reason} ->
            {pending_result, event_result}
        end
      end)

    events = Enum.reverse(events)
    history = History.append_events(state.history, events, now_ms: frame.monotonic_ms)
    %{state | pending_exits: pending_exits, history: history}
  end

  defp start_recording(state) do
    if state.active? or state.paused? do
      state
    else
      %{
        state
        | active?: true,
          recording_started_at_ms: state.system_clock.(),
          recording_started_monotonic_ms: state.monotonic_clock.(),
          start_event_pending?: true,
          reset_pending?: not is_nil(state.history.last_sequence)
      }
    end
  end

  defp stop_recording(%State{active?: false} = state) do
    state
  end

  defp stop_recording(state) do
    Enum.each(state.watches_by_pid, fn {_pid, watch} ->
      Process.demonitor(watch.monitor_ref, [:flush])
    end)

    %{
      state
      | active?: false,
        recording_started_at_ms: nil,
        recording_started_monotonic_ms: nil,
        start_event_pending?: false,
        watches_by_pid: %{},
        watches_by_ref: %{},
        pending_exits: %{},
        eligible: 0,
        omitted: 0,
        deferred: 0
    }
  end

  defp reconcile(state, frame, observations) do
    observations = eligible_observations(observations, state.watches_by_pid)
    observation_by_pid = Map.new(observations, &{&1.child_pid, &1})
    complete? = frame.coverage == :complete

    watches_by_pid =
      Map.new(state.watches_by_pid, fn {pid, watch} ->
        case Map.get(observation_by_pid, pid) do
          %Observation{} = observation ->
            {pid, update_watch(watch, observation)}

          nil when complete? ->
            {pid, %{watch | complete_omissions: watch.complete_omissions + 1}}

          nil ->
            {pid, watch}
        end
      end)

    state = %{state | watches_by_pid: watches_by_pid}
    {state, changes} = remove_omitted_watches(state)
    state = add_new_watches(state, observations, frame.sequence, changes)
    update_coverage(state, observations)
  end

  defp eligible_observations(observations, existing_watches) do
    observations
    |> Enum.filter(&eligible_observation?/1)
    |> Enum.sort_by(fn observation ->
      existing_rank = if Map.has_key?(existing_watches, observation.child_pid), do: 0, else: 1
      slot_rank = if observation.slot_kind == :stable, do: 0, else: 1
      {existing_rank, slot_rank, observation.slot_id}
    end)
    |> Enum.uniq_by(& &1.child_pid)
  end

  defp eligible_observation?(%Observation{child_pid: pid, child_state: :running})
       when is_pid(pid) do
    node(pid) == node()
  end

  defp eligible_observation?(_observation) do
    false
  end

  defp update_watch(watch, observation) do
    %{
      watch
      | slot_id: observation.slot_id,
        slot_kind: observation.slot_kind,
        supervisor_pid: observation.supervisor_pid,
        child_type: observation.child_type,
        modules: observation.modules,
        last_sequence: observation.sequence,
        coverage: observation.coverage,
        complete_omissions: 0
    }
  end

  defp remove_omitted_watches(state) do
    removals =
      state.watches_by_pid
      |> Map.values()
      |> Enum.filter(&(&1.complete_omissions >= 2 and Process.alive?(&1.pid)))
      |> Enum.sort_by(& &1.entity_id)
      |> Enum.take(state.config.reconciliation_limit)

    state = Enum.reduce(removals, state, &remove_watch/2)
    {state, length(removals)}
  end

  defp remove_watch(watch, state) do
    Process.demonitor(watch.monitor_ref, [:flush])

    %{
      state
      | watches_by_pid: Map.delete(state.watches_by_pid, watch.pid),
        watches_by_ref: Map.delete(state.watches_by_ref, watch.monitor_ref)
    }
  end

  defp add_new_watches(state, observations, sequence, changes) do
    change_capacity = max(state.config.reconciliation_limit - changes, 0)
    watch_capacity = max(state.config.watch_limit - map_size(state.watches_by_pid), 0)
    additions = min(change_capacity, watch_capacity)

    observations
    |> Enum.reject(&Map.has_key?(state.watches_by_pid, &1.child_pid))
    |> Enum.take(additions)
    |> Enum.reduce(state, fn observation, result ->
      add_watch(result, observation, sequence)
    end)
  end

  defp add_watch(state, observation, sequence) do
    pid = observation.child_pid
    reference = Process.monitor(pid)

    watch = %Watch{
      pid: pid,
      monitor_ref: reference,
      entity_id: EntityId.build(:process, {node(pid), pid}),
      slot_id: observation.slot_id,
      slot_kind: observation.slot_kind,
      supervisor_pid: observation.supervisor_pid,
      child_type: observation.child_type,
      modules: observation.modules,
      last_sequence: sequence,
      coverage: observation.coverage
    }

    %{
      state
      | watches_by_pid: Map.put(state.watches_by_pid, pid, watch),
        watches_by_ref: Map.put(state.watches_by_ref, reference, pid)
    }
  end

  defp update_coverage(state, observations) do
    eligible = length(observations)

    unwatched =
      Enum.count(observations, fn observation ->
        not Map.has_key?(state.watches_by_pid, observation.child_pid)
      end)

    omitted = min(unwatched, max(eligible - state.config.watch_limit, 0))

    %{
      state
      | eligible: eligible,
        omitted: omitted,
        deferred: max(unwatched - omitted, 0)
    }
  end

  defp recording_started_events(%State{start_event_pending?: false}, _frame) do
    []
  end

  defp recording_started_events(state, frame) do
    [
      %Event{
        id:
          EntityId.build(
            :event,
            {:recording_started, state.recording_started_at_ms, frame.sequence}
          ),
        kind: :recording_started,
        sequence: frame.sequence,
        segment: state.history.segment,
        observed_at_ms: state.recording_started_at_ms,
        monotonic_ms: state.recording_started_monotonic_ms,
        label: "Recording started",
        evidence: :recorder,
        certainty: :direct
      }
    ]
  end

  defp termination_event(state, watch, reason, monotonic_ms) do
    summary = ReasonSummary.sanitize(reason)
    missed? = summary.category == :missing

    %Event{
      id: EntityId.build(:event, {:terminated, watch.entity_id, monotonic_ms}),
      kind: if(summary.category == :connection, do: :connection_lost, else: :terminated),
      sequence: watch.last_sequence,
      segment: state.history.segment,
      observed_at_ms: state.system_clock.(),
      monotonic_ms: monotonic_ms,
      entity_id: watch.entity_id,
      label: termination_label(watch, missed?),
      node_id: EntityId.build(:node, node(watch.pid)),
      evidence: if(summary.category == :connection, do: :connection, else: :monitor),
      certainty: if(missed?, do: :missed, else: :direct),
      reason: summary
    }
  end

  defp termination_label(_watch, true) do
    "Process disappeared before recording began"
  end

  defp termination_label(watch, false) do
    case List.first(watch.modules) do
      module when is_atom(module) -> EntityId.label(module)
      _other -> "Supervised process terminated"
    end
  end

  defp maybe_store_pending_exit(state, %Watch{slot_kind: :dynamic}, _monotonic_ms) do
    state
  end

  defp maybe_store_pending_exit(state, watch, monotonic_ms) do
    pending = %PendingExit{
      slot_id: watch.slot_id,
      supervisor_pid: watch.supervisor_pid,
      entity_id: watch.entity_id,
      sequence: watch.last_sequence,
      segment: state.history.segment,
      monotonic_ms: monotonic_ms,
      coverage: watch.coverage
    }

    can_store? =
      Map.has_key?(state.pending_exits, watch.slot_id) or
        map_size(state.pending_exits) < state.config.watch_limit

    case Map.get(state.pending_exits, watch.slot_id) do
      %PendingExit{} = existing ->
        ambiguous = %{existing | ambiguity_observed?: true}
        %{state | pending_exits: Map.put(state.pending_exits, watch.slot_id, ambiguous)}

      nil when can_store? ->
        %{state | pending_exits: Map.put(state.pending_exits, watch.slot_id, pending)}

      nil ->
        state
    end
  end

  defp prune_pending_exits(state, now_ms) do
    pending_exits =
      Map.filter(state.pending_exits, fn {_slot_id, pending} ->
        now_ms - pending.monotonic_ms <= state.config.pending_slot_ms
      end)

    %{state | pending_exits: pending_exits}
  end

  defp schedule_deferred_work(state) do
    state
    |> schedule_event_flush()
    |> schedule_reconciliation()
  end

  defp schedule_event_flush(%State{flush_scheduled?: true} = state) do
    state
  end

  defp schedule_event_flush(state) do
    send(self(), :flush_lifecycle_events)
    %{state | flush_scheduled?: true}
  end

  defp schedule_reconciliation(%State{reconcile_scheduled?: true} = state) do
    state
  end

  defp schedule_reconciliation(state) do
    send(self(), :reconcile_after_down)
    %{state | reconcile_scheduled?: true}
  end

  defp flush_pending_events(%State{pending_events: []} = state) do
    state
  end

  defp flush_pending_events(state) do
    events = Enum.reverse(state.pending_events)
    now_ms = state.monotonic_clock.()
    history = History.append_events(state.history, events, now_ms: now_ms)
    %{state | history: history, pending_events: [], flush_scheduled?: false}
  end

  defp prune_history(state) do
    history = History.prune(state.history, state.monotonic_clock.())
    %{state | history: history}
  end

  defp maybe_request_refresh(%State{active?: true, collector: collector})
       when not is_nil(collector) do
    BeamConsole.Collector.refresh(collector)
  end

  defp maybe_request_refresh(_state) do
    :ok
  end

  defp status_from_state(state) do
    %Status{
      activity: activity(state),
      active?: state.active?,
      demanded?: state.demanded?,
      paused?: state.paused?,
      mode: state.config.mode,
      recording_started_at_ms: state.recording_started_at_ms,
      watched: map_size(state.watches_by_pid),
      eligible: state.eligible,
      omitted: state.omitted,
      deferred: state.deferred,
      pending_correlations: map_size(state.pending_exits),
      history: History.stats(state.history)
    }
  end

  defp activity(%State{paused?: true}) do
    :paused
  end

  defp activity(%State{active?: true}) do
    :recording
  end

  defp activity(_state) do
    :inactive
  end

  defp monotonic_ms do
    System.monotonic_time(:millisecond)
  end

  defp system_ms do
    System.system_time(:millisecond)
  end
end
