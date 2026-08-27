defmodule BeamConsoleWeb.Console.LifecyclePresenter do
  @moduledoc "Builds bounded lifecycle timeline rows and recorder status labels."

  alias BeamConsole.Lifecycle.Event
  alias BeamConsole.Recorder.Query
  alias BeamConsole.Recorder.Status
  alias BeamConsoleWeb.Console.Params

  @kind_atoms %{
    "terminated" => [:terminated],
    "replacement_observed" => [:replacement_observed],
    "recording_started" => [:recording_started],
    "reset" => [:reset],
    "gap" => [:gap]
  }

  @type row :: %{
          id: String.t(),
          kind: atom(),
          kind_label: String.t(),
          label: String.t(),
          entity_id: String.t() | nil,
          observed_at: String.t(),
          evidence: String.t(),
          certainty: String.t(),
          reason: String.t() | nil
        }

  @doc "Returns bounded recorder query options for normalized lifecycle URL state."
  @spec query_options(Params.t()) :: keyword()
  def query_options(%Params{} = params) do
    since_ms = System.system_time(:millisecond) - Params.window_ms(params)

    [limit: 250, since_ms: since_ms]
    |> maybe_put_kinds(Map.get(@kind_atoms, params.kind))
  end

  @doc "Converts a bounded recorder query into newest-first scalar timeline rows."
  @spec rows(Query.t(), String.t()) :: [row()]
  def rows(%Query{} = query, search_query \\ "") do
    normalized = search_query |> String.trim() |> String.downcase()

    query.items
    |> Enum.filter(&match_search?(&1, normalized))
    |> Enum.map(&row/1)
  end

  @doc "Counts view omissions plus lifecycle changes represented by retained gap events."
  @spec omitted_count(Query.t()) :: non_neg_integer()
  def omitted_count(%Query{} = query) do
    query.omitted + query.dropped + Enum.reduce(query.items, 0, &add_gap_omissions/2)
  end

  @doc "Returns concise operator-facing recorder activity text."
  @spec activity_label(Status.t()) :: String.t()
  def activity_label(%Status{activity: :recording}) do
    "Recording"
  end

  def activity_label(%Status{activity: :paused}) do
    "Paused"
  end

  def activity_label(%Status{}) do
    "Inactive"
  end

  defp row(%Event{} = event) do
    %{
      id: event.id,
      kind: event.kind,
      kind_label: event.kind |> Atom.to_string() |> String.replace("_", " "),
      label: event.label || "Runtime event observed",
      entity_id: event.entity_id,
      observed_at: format_time(event.observed_at_ms),
      evidence: event.evidence |> Atom.to_string() |> String.replace("_", " "),
      certainty: Atom.to_string(event.certainty),
      reason: event.reason && event.reason.text
    }
  end

  defp add_gap_omissions(%Event{kind: :gap, details: %{omitted: omitted}}, total)
       when is_integer(omitted) and omitted > 0 do
    total + omitted
  end

  defp add_gap_omissions(_event, total) do
    total
  end

  defp match_search?(_event, "") do
    true
  end

  defp match_search?(event, query) do
    [event.label, event.application, event.reason && event.reason.text]
    |> Enum.reject(&is_nil/1)
    |> Enum.any?(&String.contains?(String.downcase(to_string(&1)), query))
  end

  defp format_time(milliseconds) do
    case DateTime.from_unix(milliseconds, :millisecond) do
      {:ok, datetime} -> Calendar.strftime(datetime, "%H:%M:%S")
      {:error, _reason} -> "unknown time"
    end
  end

  defp maybe_put_kinds(options, nil) do
    options
  end

  defp maybe_put_kinds(options, kinds) do
    Keyword.put(options, :kinds, kinds)
  end
end
