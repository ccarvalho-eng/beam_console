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

  @spec sanitize(term(), keyword()) :: t()
  @doc """
  Returns a categorized structural summary under a byte limit.

  ## Examples

      iex> BeamConsole.ReasonSummary.sanitize(:normal)
      %BeamConsole.ReasonSummary{category: :normal, text: "normal"}

      iex> summary = BeamConsole.ReasonSummary.sanitize({:badmatch, "secret"})
      iex> {summary.category, summary.text}
      {:error, "{badmatch, binary(6 bytes)}"}
  """
  def sanitize(reason, options \\ []) do
    max_bytes = positive_option(options, :max_bytes, 160)
    max_depth = positive_option(options, :max_depth, 3)
    max_items = positive_option(options, :max_items, 5)

    %__MODULE__{
      category: category(reason),
      text: reason |> render(0, max_depth, max_items) |> truncate(max_bytes)
    }
  end

  defp category(:normal), do: :normal
  defp category(:shutdown), do: :shutdown
  defp category({:shutdown, _detail}), do: :shutdown
  defp category(:killed), do: :killed
  defp category(:noproc), do: :missing
  defp category(:noconnection), do: :connection
  defp category(_reason), do: :error

  defp render(:normal, _depth, _max_depth, _max_items), do: "normal"
  defp render(:shutdown, _depth, _max_depth, _max_items), do: "shutdown"
  defp render({:shutdown, _detail}, _depth, _max_depth, _max_items), do: "shutdown"

  defp render(value, _depth, _max_depth, _max_items) when is_binary(value) do
    "binary(#{byte_size(value)} bytes)"
  end

  defp render(value, _depth, _max_depth, _max_items) when is_atom(value) do
    Atom.to_string(value)
  end

  defp render(value, _depth, _max_depth, _max_items) when is_integer(value) do
    Integer.to_string(value)
  end

  defp render(value, _depth, _max_depth, _max_items) when is_float(value) do
    Float.to_string(value)
  end

  defp render(%{__struct__: module}, _depth, _max_depth, _max_items) when is_atom(module) do
    "#{inspect(module)} exception"
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
    "list(#{bounded_length(value)} items)"
  end

  defp render(value, _depth, _max_depth, _max_items) when is_pid(value), do: "pid"
  defp render(value, _depth, _max_depth, _max_items) when is_reference(value), do: "reference"
  defp render(value, _depth, _max_depth, _max_items) when is_port(value), do: "port"
  defp render(value, _depth, _max_depth, _max_items) when is_function(value), do: "function"
  defp render(_value, _depth, _max_depth, _max_items), do: "opaque"

  defp positive_option(options, key, default) do
    case Keyword.get(options, key, default) do
      value when is_integer(value) and value > 0 -> value
      _other -> default
    end
  end

  defp bounded_length(value) do
    case Enum.count_until(value, 10_001) do
      10_001 -> "more than 10000"
      length -> Integer.to_string(length)
    end
  end

  defp truncate(value, max_bytes) when byte_size(value) <= max_bytes do
    value
  end

  defp truncate(value, max_bytes) do
    allowance = max(max_bytes - byte_size("…"), 0)

    value
    |> String.graphemes()
    |> Enum.reduce_while("", fn grapheme, result ->
      if byte_size(result) + byte_size(grapheme) <= allowance do
        {:cont, result <> grapheme}
      else
        {:halt, result}
      end
    end)
    |> Kernel.<>("…")
  end
end
