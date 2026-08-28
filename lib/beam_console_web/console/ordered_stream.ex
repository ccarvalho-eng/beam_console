defmodule BeamConsoleWeb.Console.OrderedStream do
  @moduledoc """
  Tracks ordered stream identifiers so stable orders retain DOM identity.

  Ordered rows only need positional reinsertion when their identifier order
  changes. Value-only updates can then preserve focus and pointer continuity.
  """

  @type item :: %{required(:id) => String.t()}

  @doc "Returns ordered identifiers for stream items."
  @spec ids([item()]) :: [String.t()]
  def ids(items) when is_list(items) do
    Enum.map(items, & &1.id)
  end

  @doc "Returns whether the current ordered identifiers differ from the previous order."
  @spec reordered?([String.t()], [String.t()]) :: boolean()
  def reordered?(previous_ids, current_ids)
      when is_list(previous_ids) and is_list(current_ids) do
    previous_ids != current_ids
  end
end
