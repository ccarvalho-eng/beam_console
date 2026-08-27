defmodule BeamConsole.Runtime.Adapter do
  @moduledoc """
  Defines the bounded snapshot contract used by the shared collector.

  Adapters must return normalized BeamConsole structs and must not expose raw
  runtime terms to the web client.
  """

  alias BeamConsole.Snapshot

  @doc "Collects one immutable runtime snapshot using the supplied limits."
  @callback snapshot(keyword()) :: {:ok, Snapshot.t()} | {:error, term()}
end
