defmodule BeamConsole.Config do
  @moduledoc """
  Resolves and validates bounded collector settings.

  Collector application configuration rejects unknown keys so mistakes do not
  silently weaken runtime limits. Runtime adapters can also read individual
  resolved values through `get/2`.
  """

  alias BeamConsole.Recorder.Config, as: RecorderConfig

  @defaults [
    interval: 2_000,
    scan_timeout: 1_500,
    process_limit: 20_000,
    supervisor_limit: 2_000,
    topology_depth: 32,
    children_limit: 10_000,
    supervisor_timeout: 100,
    detail_timeout: 100,
    diff_limit: 500,
    relationship_limit: 200,
    refresh_cooldown: 250
  ]

  @runtime_keys [
    :process_limit,
    :supervisor_limit,
    :topology_depth,
    :children_limit,
    :supervisor_timeout,
    :detail_timeout,
    :relationship_limit
  ]

  @non_negative_fields [:refresh_cooldown]

  @doc "Returns the default collector limits and sampling intervals."
  @spec defaults() :: keyword()
  def defaults do
    @defaults
  end

  @doc """
  Loads validated `:beam_console, :collector` configuration and applies overrides.

  Runtime overrides take precedence over application configuration.
  """
  @spec collector(keyword()) :: keyword()
  def collector(overrides \\ []) do
    configured = Application.get_env(:beam_console, :collector, [])

    with true <- Keyword.keyword?(configured) and Keyword.keyword?(overrides),
         options <- Keyword.merge(@defaults, configured),
         options <- Keyword.merge(options, overrides),
         :ok <- validate_collector(options) do
      options
    else
      false ->
        raise ArgumentError, "collector configuration must be a keyword list"

      {:error, message} ->
        raise ArgumentError, message
    end
  end

  @doc "Returns the supported collector configuration keys."
  @spec collector_keys() :: [atom()]
  def collector_keys do
    Keyword.keys(@defaults)
  end

  @doc "Returns the collector settings forwarded to the runtime adapter."
  @spec runtime_keys() :: [atom()]
  def runtime_keys do
    @runtime_keys
  end

  @doc "Returns an explicit option value or the corresponding default."
  @spec get(keyword(), atom()) :: term()
  def get(options, key) do
    Keyword.get(options, key, Keyword.fetch!(@defaults, key))
  end

  @doc "Loads validated flight-recorder configuration with optional runtime overrides."
  @spec recorder(keyword()) :: RecorderConfig.t()
  def recorder(overrides \\ []) do
    RecorderConfig.load(overrides)
  end

  defp validate_collector(options) do
    unknown = Keyword.keys(options) -- collector_keys()

    cond do
      unknown != [] ->
        {:error, "unknown collector configuration: #{inspect(Enum.uniq(unknown))}"}

      invalid = Enum.find(@non_negative_fields, &(not non_negative_integer?(options[&1]))) ->
        {:error, "collector #{invalid} must be a non-negative integer"}

      invalid =
          Enum.find(
            collector_keys() -- @non_negative_fields,
            &(not positive_integer?(options[&1]))
          ) ->
        {:error, "collector #{invalid} must be a positive integer"}

      true ->
        :ok
    end
  end

  defp non_negative_integer?(value) do
    is_integer(value) and value >= 0
  end

  defp positive_integer?(value) do
    is_integer(value) and value > 0
  end
end
