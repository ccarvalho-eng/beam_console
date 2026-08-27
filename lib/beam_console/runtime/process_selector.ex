defmodule BeamConsole.Runtime.ProcessSelector do
  @moduledoc """
  Selects a deterministic bounded subset of local processes.

  The selector avoids sorting an entire large process population. It keeps at
  most `limit` hash-ranked candidates while scanning the input once.
  """

  @doc "Returns at most `limit` PIDs using deterministic bounded-memory ranking."
  @spec select([pid()], non_neg_integer()) :: [pid()]
  def select(_pids, 0) do
    []
  end

  def select(pids, limit) when is_list(pids) and is_integer(limit) and limit > 0 do
    {selected, _size} =
      Enum.reduce(pids, {:gb_sets.empty(), 0}, fn pid, {current, size} ->
        insert_candidate(current, size, pid, limit)
      end)

    selected
    |> :gb_sets.to_list()
    |> Enum.map(&elem(&1, 1))
  end

  defp insert_candidate(selected, size, pid, limit) when size < limit do
    {:gb_sets.add({:erlang.phash2(pid), pid}, selected), size + 1}
  end

  defp insert_candidate(selected, size, pid, _limit) do
    candidate = {:erlang.phash2(pid), pid}
    largest = :gb_sets.largest(selected)

    if candidate < largest do
      selected = :gb_sets.delete(largest, selected)
      {:gb_sets.add(candidate, selected), size}
    else
      {selected, size}
    end
  end
end
