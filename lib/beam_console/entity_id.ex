defmodule BeamConsole.EntityId do
  @moduledoc false

  @prefixes %{application: "app", edge: "edge", node: "node", process: "proc"}

  @spec build(atom(), term()) :: String.t()
  def build(kind, identity) when is_map_key(@prefixes, kind) do
    digest =
      identity
      |> :erlang.term_to_binary([:deterministic])
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.url_encode64(padding: false)

    Map.fetch!(@prefixes, kind) <> "_" <> binary_part(digest, 0, 22)
  end

  @spec label(term(), non_neg_integer()) :: String.t()
  def label(value, limit \\ 96)

  def label(value, limit) when is_binary(value) do
    truncate(value, limit)
  end

  def label(value, limit) when is_atom(value) do
    value
    |> Atom.to_string()
    |> truncate(limit)
  end

  def label(value, _limit) when is_integer(value) do
    Integer.to_string(value)
  end

  def label(value, limit) when is_pid(value) do
    value
    |> :erlang.pid_to_list()
    |> List.to_string()
    |> truncate(limit)
  end

  def label(_value, _limit) do
    "opaque child"
  end

  defp truncate(value, limit) when byte_size(value) <= limit do
    value
  end

  defp truncate(value, limit) do
    binary_part(value, 0, limit) <> "…"
  end
end
