defmodule BeamConsoleWeb.Console.Params do
  @moduledoc """
  Normalizes bounded URL state for every BeamConsole dashboard tab.

  Client strings are matched against fixed allowlists and are never converted
  into atoms.
  """

  @tabs [:process_map, :lifecycle, :activity, :runtime]
  @kinds ~w(all terminated replacement_observed recording_started reset gap)
  @windows ~w(1m 5m 15m)
  @edges ~w(supervision relationships)

  defstruct tab: :process_map,
            query: "",
            selected_id: nil,
            kind: "all",
            window: "5m",
            edges: "supervision"

  @type tab :: :process_map | :lifecycle | :activity | :runtime
  @type t :: %__MODULE__{
          tab: tab(),
          query: String.t(),
          selected_id: String.t() | nil,
          kind: String.t(),
          window: String.t(),
          edges: String.t()
        }

  @doc "Returns safe URL state for a trusted router live action."
  @spec normalize(map(), atom()) :: t()
  def normalize(params, live_action) when is_map(params) do
    tab = if live_action in @tabs, do: live_action, else: :process_map

    %__MODULE__{
      tab: tab,
      query: bounded_string(params["q"], 120, ""),
      selected_id: optional_string(params["entity"], 160),
      kind: allowed(params["kind"], @kinds, "all"),
      window: allowed(params["window"], @windows, "5m"),
      edges: allowed(params["edges"], @edges, "supervision")
    }
  end

  @doc "Returns only URL parameters relevant to the normalized active tab."
  @spec query_params(t()) :: map()
  def query_params(%__MODULE__{} = params) do
    %{}
    |> maybe_put("entity", params.selected_id)
    |> tab_params(params)
  end

  @doc "Returns the normalized chart window in milliseconds."
  @spec window_ms(t()) :: pos_integer()
  def window_ms(%__MODULE__{window: "1m"}) do
    60_000
  end

  def window_ms(%__MODULE__{window: "15m"}) do
    15 * 60_000
  end

  def window_ms(%__MODULE__{}) do
    5 * 60_000
  end

  defp tab_params(result, %__MODULE__{tab: :process_map} = params) do
    result
    |> maybe_put("q", blank_to_nil(params.query))
    |> maybe_put("edges", non_default(params.edges, "supervision"))
  end

  defp tab_params(result, %__MODULE__{tab: :lifecycle} = params) do
    result
    |> maybe_put("q", blank_to_nil(params.query))
    |> maybe_put("kind", non_default(params.kind, "all"))
  end

  defp tab_params(result, %__MODULE__{} = params) do
    maybe_put(result, "window", non_default(params.window, "5m"))
  end

  defp bounded_string(value, limit, _default) when is_binary(value) do
    String.slice(value, 0, limit)
  end

  defp bounded_string(_value, _limit, default) do
    default
  end

  defp optional_string(value, limit) when is_binary(value) do
    case value |> String.trim() |> String.slice(0, limit) do
      "" -> nil
      bounded -> bounded
    end
  end

  defp optional_string(_value, _limit) do
    nil
  end

  defp allowed(value, values, default) when is_binary(value) do
    if value in values, do: value, else: default
  end

  defp allowed(_value, _values, default) do
    default
  end

  defp blank_to_nil(value) do
    if String.trim(value) == "", do: nil, else: String.trim(value)
  end

  defp non_default(value, value) do
    nil
  end

  defp non_default(value, _default) do
    value
  end

  defp maybe_put(result, _key, nil) do
    result
  end

  defp maybe_put(result, key, value) do
    Map.put(result, key, value)
  end
end
