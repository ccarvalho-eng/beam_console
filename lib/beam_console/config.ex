defmodule BeamConsole.Config do
  @moduledoc """
  Resolves bounded collector settings from mount or process options.

  Unknown keys raise so configuration mistakes do not silently weaken runtime
  limits.
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
    diff_limit: 500,
    relationship_limit: 200
  ]

  @spec defaults() :: keyword()
  @doc "Returns the default collector limits and sampling intervals."
  def defaults do
    @defaults
  end

  @spec get(keyword(), atom()) :: term()
  @doc "Returns an explicit option value or the corresponding default."
  def get(options, key) do
    Keyword.get(options, key, Keyword.fetch!(@defaults, key))
  end

  @spec recorder(keyword()) :: RecorderConfig.t()
  @doc "Loads validated flight-recorder configuration with optional runtime overrides."
  def recorder(overrides \\ []) do
    RecorderConfig.load(overrides)
  end
end
