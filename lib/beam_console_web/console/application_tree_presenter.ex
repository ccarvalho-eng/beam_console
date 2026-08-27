defmodule BeamConsoleWeb.Console.ApplicationTreePresenter do
  @moduledoc "Groups started applications into deterministic folder-tree categories."

  alias BeamConsole.ApplicationInfo
  alias BeamConsole.ApplicationTreeConfig
  alias BeamConsole.Snapshot

  @tooling [:beam_console, :ex_unit, :mix, :phoenix_live_reload]

  @type category_view :: %{
          id: String.t(),
          category: ApplicationTreeConfig.category(),
          label: String.t(),
          count: non_neg_integer(),
          applications: [ApplicationInfo.t()]
        }

  @spec present(Snapshot.t(), ApplicationTreeConfig.t()) :: [category_view()]
  @doc "Returns every configured category with sorted application rows and stable IDs."
  def present(%Snapshot{} = snapshot, %ApplicationTreeConfig{} = config) do
    applications = Map.values(snapshot.applications)
    inferred_hosts = inferred_hosts(applications)

    grouped =
      Enum.group_by(applications, fn application ->
        classify(application, config, inferred_hosts)
      end)

    Enum.map(config.category_order, fn category ->
      category_applications =
        grouped
        |> Map.get(category, [])
        |> Enum.sort_by(& &1.name)

      %{
        id: "application-category-#{category}",
        category: category,
        label: Map.fetch!(config.category_labels, category),
        count: length(category_applications),
        applications: category_applications
      }
    end)
  end

  defp classify(application, config, inferred_hosts) do
    explicit = Map.get(config.application_categories, application.name)
    callback = classify_with_callback(application, config)

    cond do
      explicit -> explicit
      callback -> callback
      application.name in config.host_applications -> :host
      application.name in @tooling -> :tooling
      application.origin == :otp -> :otp
      application.name in inferred_hosts -> :host
      true -> :dependencies
    end
  end

  defp classify_with_callback(_application, %ApplicationTreeConfig{classify_application: nil}) do
    nil
  end

  defp classify_with_callback(application, config) do
    {module, function, arguments} = config.classify_application

    case apply(module, function, [application | arguments]) do
      :default -> nil
      category -> if(category in config.category_order, do: category, else: nil)
    end
  rescue
    _exception -> nil
  catch
    _kind, _reason -> nil
  end

  defp inferred_hosts(applications) do
    non_otp = Enum.reject(applications, &(&1.origin == :otp))

    required =
      non_otp
      |> Enum.flat_map(& &1.required_applications)
      |> MapSet.new()

    non_otp
    |> Enum.reject(&MapSet.member?(required, &1.name))
    |> Enum.map(& &1.name)
  end
end
