defmodule BeamConsole.ReasonSummary do
  @moduledoc """
  Converts process exit reasons into bounded, non-sensitive summaries.

  Arbitrary binaries, lists, maps, PIDs, references, functions, and ports are
  described structurally rather than copied. This prevents raw application
  terms or credentials from entering recorder history.
  """

  defstruct category: :error, text: "opaque"

  @type category :: :normal | :shutdown | :killed | :missing | :connection | :error
  @type t :: %__MODULE__{category: category(), text: String.t()}

  @safe_atoms [
    :badarg,
    :badmatch,
    :case_clause,
    :error,
    :function_clause,
    :killed,
    :noconnection,
    :noproc,
    :normal,
    :shutdown,
    :timeout,
    :undef
  ]

  @list_shape_limit 32

  @doc """
  Returns a categorized structural summary under a byte limit.

  ## Examples

      iex> BeamConsole.ReasonSummary.sanitize(:normal)
      %BeamConsole.ReasonSummary{category: :normal, text: "normal"}

      iex> summary = BeamConsole.ReasonSummary.sanitize({:badmatch, "secret"})
      iex> {summary.category, summary.text}
      {:error, "{badmatch, binary(6 bytes)}"}
  """
  @spec sanitize(term(), keyword()) :: t()
  def sanitize(reason, options \\ []) do
    max_bytes = positive_option(options, :max_bytes, 160)
    max_depth = positive_option(options, :max_depth, 3)
    max_items = positive_option(options, :max_items, 5)

    %__MODULE__{
      category: category(reason),
      text: reason |> render(0, max_depth, max_items) |> truncate(max_bytes)
    }
  end

  defp category(:normal) do
    :normal
  end

  defp category(:shutdown) do
    :shutdown
  end

  defp category({:shutdown, _detail}) do
    :shutdown
  end

  defp category(:killed) do
    :killed
  end

  defp category(:noproc) do
    :missing
  end

  defp category(:noconnection) do
    :connection
  end

  defp category(_reason) do
    :error
  end

  defp render(:normal, _depth, _max_depth, _max_items) do
    "normal"
  end

  defp render(:shutdown, _depth, _max_depth, _max_items) do
    "shutdown"
  end

  defp render({:shutdown, _detail}, _depth, _max_depth, _max_items) do
    "shutdown"
  end

  defp render(value, _depth, _max_depth, _max_items) when is_binary(value) do
    "binary(#{byte_size(value)} bytes)"
  end

  defp render(value, _depth, _max_depth, _max_items) when value in @safe_atoms do
    Atom.to_string(value)
  end

  defp render(value, _depth, _max_depth, _max_items) when is_atom(value) do
    "atom"
  end

  defp render(value, _depth, _max_depth, _max_items) when is_integer(value) do
    "integer"
  end

  defp render(value, _depth, _max_depth, _max_items) when is_float(value) do
    "float"
  end

  defp render(%{__struct__: module}, _depth, _max_depth, _max_items) when is_atom(module) do
    "exception"
  end

  defp render(value, depth, max_depth, max_items) when is_tuple(value) do
    if depth >= max_depth do
      "tuple(#{tuple_size(value)})"
    else
      values = value |> Tuple.to_list() |> Enum.take(max_items)
      rendered = Enum.map_join(values, ", ", &render(&1, depth + 1, max_depth, max_items))
      suffix = if tuple_size(value) > max_items, do: ", …", else: ""
      "{" <> rendered <> suffix <> "}"
    end
  end

  defp render(value, _depth, _max_depth, _max_items) when is_map(value) do
    "map(#{map_size(value)} entries)"
  end

  defp render(value, _depth, _max_depth, _max_items) when is_list(value) do
    list_summary(value)
  end

  defp render(value, _depth, _max_depth, _max_items) when is_pid(value) do
    "pid"
  end

  defp render(value, _depth, _max_depth, _max_items) when is_reference(value) do
    "reference"
  end

  defp render(value, _depth, _max_depth, _max_items) when is_port(value) do
    "port"
  end

  defp render(value, _depth, _max_depth, _max_items) when is_function(value) do
    "function"
  end

  defp render(_value, _depth, _max_depth, _max_items) do
    "opaque"
  end

  defp positive_option(options, key, default) do
    case Keyword.get(options, key, default) do
      value when is_integer(value) and value > 0 -> value
      _other -> default
    end
  end

  defp list_summary(value) do
    case bounded_list_shape(value, 0) do
      {:proper, length} -> "list(#{length} items)"
      {:improper, length} -> "improper_list(#{length} heads)"
      :truncated -> "list(more than #{@list_shape_limit} items)"
    end
  end

  defp bounded_list_shape([], length) do
    {:proper, length}
  end

  defp bounded_list_shape([_head | _tail], @list_shape_limit) do
    :truncated
  end

  defp bounded_list_shape([_head | tail], length) do
    bounded_list_shape(tail, length + 1)
  end

  defp bounded_list_shape(_tail, length) do
    {:improper, length}
  end

  defp truncate(value, max_bytes) when byte_size(value) <= max_bytes do
    value
  end

  defp truncate(value, max_bytes) do
    suffix = truncation_suffix(max_bytes)
    allowance = max_bytes - byte_size(suffix)

    value
    |> String.graphemes()
    |> Enum.reduce_while("", fn grapheme, result ->
      if byte_size(result) + byte_size(grapheme) <= allowance do
        {:cont, result <> grapheme}
      else
        {:halt, result}
      end
    end)
    |> Kernel.<>(suffix)
  end

  defp truncation_suffix(max_bytes) when max_bytes < 3 do
    String.duplicate(".", max_bytes)
  end

  defp truncation_suffix(_max_bytes) do
    "…"
  end
end
