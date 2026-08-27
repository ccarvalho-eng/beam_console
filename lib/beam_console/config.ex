defmodule BeamConsole.Config do
  @moduledoc false

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
  def defaults do
    @defaults
  end

  @spec get(keyword(), atom()) :: term()
  def get(options, key) do
    Keyword.get(options, key, Keyword.fetch!(@defaults, key))
  end
end
