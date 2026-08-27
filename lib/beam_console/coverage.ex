defmodule BeamConsole.Coverage do
  @moduledoc """
  Records how complete and expensive a runtime snapshot was.

  Limits and vanished processes are represented explicitly so callers can
  distinguish a complete snapshot from a bounded or partial one.
  """

  defstruct total_pids: 0,
            inspected_pids: 0,
            vanished_pids: 0,
            process_limit_reached?: false,
            traversal_limit_reached?: false,
            partial_supervisors: 0,
            duration_ms: 0,
            warnings: []

  @type t :: %__MODULE__{
          total_pids: non_neg_integer(),
          inspected_pids: non_neg_integer(),
          vanished_pids: non_neg_integer(),
          process_limit_reached?: boolean(),
          traversal_limit_reached?: boolean(),
          partial_supervisors: non_neg_integer(),
          duration_ms: non_neg_integer(),
          warnings: [String.t()]
        }

  @type state :: :complete | :partial | :truncated

  @doc "Classifies snapshot coverage for recorder history and runtime presentation."
  @spec state(t()) :: state()
  def state(%__MODULE__{traversal_limit_reached?: true}) do
    :truncated
  end

  def state(%__MODULE__{process_limit_reached?: true}) do
    :truncated
  end

  def state(%__MODULE__{vanished_pids: count}) when count > 0 do
    :partial
  end

  def state(%__MODULE__{partial_supervisors: count}) when count > 0 do
    :partial
  end

  def state(%__MODULE__{}) do
    :complete
  end

  @doc "Returns human-readable reasons that a runtime sample has incomplete coverage."
  @spec warnings(t()) :: [String.t()]
  def warnings(%__MODULE__{} = coverage) do
    []
    |> append_warning(coverage.process_limit_reached?, "Process limit reached")
    |> append_warning(coverage.traversal_limit_reached?, "Supervision traversal limit reached")
    |> append_count_warning(
      coverage.vanished_pids,
      "process vanished during inspection",
      "processes vanished during inspection"
    )
    |> append_count_warning(
      coverage.partial_supervisors,
      "supervision branch was partial",
      "supervision branches were partial"
    )
  end

  defp append_warning(warnings, true, warning) do
    warnings ++ [warning]
  end

  defp append_warning(warnings, false, _warning) do
    warnings
  end

  defp append_count_warning(warnings, 1, singular, _plural) do
    warnings ++ ["1 #{singular}"]
  end

  defp append_count_warning(warnings, count, _singular, plural) when count > 1 do
    warnings ++ ["#{count} #{plural}"]
  end

  defp append_count_warning(warnings, _count, _singular, _plural) do
    warnings
  end
end
