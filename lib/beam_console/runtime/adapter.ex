defmodule BeamConsole.Runtime.Adapter do
  @moduledoc false

  alias BeamConsole.Snapshot

  @callback snapshot(keyword()) :: {:ok, Snapshot.t()} | {:error, term()}
end
