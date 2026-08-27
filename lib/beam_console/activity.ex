defmodule BeamConsole.Activity do
  @moduledoc "Computes bounded process-activity deltas between two transient snapshots."

  alias BeamConsole.Activity.Sample
  alias BeamConsole.ProcessInfo
  alias BeamConsole.Snapshot

  @mover_limit 25

  @doc "Builds aggregate activity rates and ranked top movers without retaining either snapshot."
  @spec sample(Snapshot.t() | nil, Snapshot.t(), integer()) :: Sample.t()
  def sample(nil, %Snapshot{} = current, monotonic_ms) do
    empty_sample(current, monotonic_ms)
  end

  def sample(%Snapshot{stale?: true}, %Snapshot{} = current, monotonic_ms) do
    empty_sample(current, monotonic_ms)
  end

  def sample(%Snapshot{} = previous, %Snapshot{} = current, monotonic_ms) do
    elapsed_ms = elapsed_ms(previous.monotonic_ms, current.monotonic_ms || monotonic_ms)

    if is_nil(elapsed_ms) do
      empty_sample(current, monotonic_ms)
    else
      compare_samples(previous, current, monotonic_ms, elapsed_ms)
    end
  end

  defp compare_samples(previous, current, monotonic_ms, elapsed_ms) do
    movers =
      current.processes
      |> Map.values()
      |> Enum.flat_map(fn process -> process_movers(process, previous, elapsed_ms) end)
      |> Enum.sort_by(fn mover -> {-abs(mover.value), mover.entity_id, mover.metric} end)

    %Sample{
      sequence: current.sequence,
      sampled_at_ms: DateTime.to_unix(current.sampled_at, :millisecond),
      monotonic_ms: monotonic_ms,
      aggregates: aggregate(movers),
      top_movers: Enum.take(movers, @mover_limit),
      omitted: max(length(movers) - @mover_limit, 0)
    }
  end

  defp elapsed_ms(previous, current)
       when is_integer(previous) and is_integer(current) and current > previous do
    current - previous
  end

  defp elapsed_ms(_previous, _current) do
    nil
  end

  defp empty_sample(current, monotonic_ms) do
    %Sample{
      sequence: current.sequence,
      sampled_at_ms: DateTime.to_unix(current.sampled_at, :millisecond),
      monotonic_ms: monotonic_ms,
      aggregates: %{
        reductions_per_second: 0.0,
        mailbox_delta: 0,
        memory_delta: 0
      }
    }
  end

  defp process_movers(%ProcessInfo{} = current, previous, elapsed_ms) do
    case Map.get(previous.processes, current.id) do
      %ProcessInfo{} = prior ->
        []
        |> maybe_mover(
          current,
          :reductions_per_second,
          reduction_rate(prior, current, elapsed_ms)
        )
        |> maybe_mover(
          current,
          :mailbox_delta,
          delta(prior.message_queue_len, current.message_queue_len)
        )
        |> maybe_mover(current, :memory_delta, delta(prior.memory, current.memory))

      nil ->
        []
    end
  end

  defp reduction_rate(%{reductions: previous}, %{reductions: current}, elapsed_ms)
       when is_integer(previous) and is_integer(current) and current >= previous do
    (current - previous) * 1_000 / elapsed_ms
  end

  defp reduction_rate(_previous, _current, _elapsed_ms) do
    nil
  end

  defp delta(previous, current) when is_integer(previous) and is_integer(current) do
    current - previous
  end

  defp delta(_previous, _current) do
    nil
  end

  defp maybe_mover(result, _process, _metric, nil) do
    result
  end

  defp maybe_mover(result, _process, _metric, value) when value == 0 do
    result
  end

  defp maybe_mover(result, process, metric, value) do
    [
      %{
        entity_id: process.id,
        metric: metric,
        value: value,
        label: process.label
      }
      | result
    ]
  end

  defp aggregate(movers) do
    Enum.reduce(
      movers,
      %{reductions_per_second: 0.0, mailbox_delta: 0, memory_delta: 0},
      fn mover, result -> Map.update!(result, mover.metric, &(&1 + mover.value)) end
    )
  end
end
