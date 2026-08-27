defmodule BeamConsoleWeb.Console.Paths do
  @moduledoc "Builds mount-prefix-aware URLs for the BeamConsole dashboard tabs."

  alias BeamConsoleWeb.Console.Params

  @segments %{
    process_map: "",
    lifecycle: "/lifecycle",
    activity: "/activity",
    runtime: "/runtime"
  }

  @spec path(String.t(), Params.tab(), Params.t() | map()) :: String.t()
  @doc "Builds a tab path with normalized, relevant query parameters."
  def path(prefix, tab, params \\ %{}) when is_binary(prefix) and is_map(params) do
    normalized =
      case params do
        %Params{} = value -> %{value | tab: tab}
        value -> Params.normalize(value, tab)
      end

    base = String.trim_trailing(prefix, "/") <> Map.fetch!(@segments, tab)
    query = normalized |> Params.query_params() |> URI.encode_query()

    if query == "", do: base, else: base <> "?" <> query
  end
end
