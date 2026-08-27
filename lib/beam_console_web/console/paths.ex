defmodule BeamConsoleWeb.Console.Paths do
  @moduledoc "Builds mount-prefix-aware URLs for the BeamConsole dashboard tabs."

  alias BeamConsoleWeb.Console.Params

  @segments %{
    process_map: "",
    lifecycle: "/lifecycle",
    activity: "/activity",
    runtime: "/runtime"
  }

  @doc "Builds a tab path with normalized, relevant query parameters."
  @spec path(String.t(), Params.tab(), Params.t() | map()) :: String.t()
  def path(prefix, tab, params \\ %{}) when is_binary(prefix) and is_map(params) do
    normalized =
      case params do
        %Params{} = value -> %{value | tab: tab}
        value -> Params.normalize(value, tab)
      end

    base =
      prefix
      |> String.trim_trailing("/")
      |> Kernel.<>(Map.fetch!(@segments, tab))
      |> normalize_root()

    query = normalized |> Params.query_params() |> URI.encode_query()

    if query == "", do: base, else: base <> "?" <> query
  end

  defp normalize_root("") do
    "/"
  end

  defp normalize_root(path) do
    path
  end
end
