defmodule BeamConsole.EntityId do
  @moduledoc """
  Builds stable, opaque identifiers and bounded labels for runtime entities.

  IDs are safe to place in URLs and browser DOM attributes. They deliberately
  avoid accepting encoded Erlang terms back from clients.
  """

  @prefixes %{application: "app", edge: "edge", node: "node", process: "proc"}

  @spec build(atom(), term()) :: String.t()
  @doc """
  Builds a deterministic, kind-prefixed identifier from an Erlang term.

  ## Examples

      iex> id = BeamConsole.EntityId.build(:application, :logger)
      iex> String.starts_with?(id, "app_")
      true
      iex> id == BeamConsole.EntityId.build(:application, :logger)
      true
  """
  def build(kind, identity) when is_map_key(@prefixes, kind) do
    digest =
      identity
      |> :erlang.term_to_binary([:deterministic])
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.url_encode64(padding: false)

    Map.fetch!(@prefixes, kind) <> "_" <> binary_part(digest, 0, 22)
  end

  @spec label(term(), non_neg_integer()) :: String.t()
  @doc """
  Converts a safe runtime value into a bounded display label.

  Values outside the allowlisted scalar types are rendered as opaque children.

  ## Examples

      iex> BeamConsole.EntityId.label(:worker)
      "worker"
      iex> BeamConsole.EntityId.label("abcdefgh", 4)
      "abcd…"
      iex> BeamConsole.EntityId.label({:private, :term})
      "opaque child"
  """
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
