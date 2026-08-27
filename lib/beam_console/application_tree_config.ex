defmodule BeamConsole.ApplicationTreeConfig do
  @moduledoc "Validates deterministic application-category configuration."

  @categories [:host, :dependencies, :otp, :tooling, :unattributed]
  @default_labels %{
    host: "Host applications",
    dependencies: "Dependencies",
    otp: "Erlang / OTP",
    tooling: "Tooling",
    unattributed: "Unattributed processes"
  }
  @keys [
    :host_applications,
    :category_order,
    :category_labels,
    :application_categories,
    :classify_application
  ]

  defstruct host_applications: [],
            category_order: @categories,
            category_labels: @default_labels,
            application_categories: %{},
            classify_application: nil

  @type category :: :host | :dependencies | :otp | :tooling | :unattributed
  @type classifier :: {module(), atom(), [term()]} | nil
  @type t :: %__MODULE__{
          host_applications: [atom()],
          category_order: [category()],
          category_labels: %{category() => String.t()},
          application_categories: %{atom() => category()},
          classify_application: classifier()
        }

  @spec load(keyword()) :: t()
  @doc "Loads `:beam_console, :application_tree` configuration and applies overrides."
  def load(overrides \\ []) do
    configured = Application.get_env(:beam_console, :application_tree, [])

    if Keyword.keyword?(configured) and Keyword.keyword?(overrides) do
      configured
      |> Keyword.merge(overrides)
      |> new!()
    else
      raise ArgumentError, "application tree configuration must be a keyword list"
    end
  end

  @spec new!(keyword()) :: t()
  @doc "Builds validated application-tree configuration or raises `ArgumentError`."
  def new!(options \\ []) do
    unknown = Keyword.keys(options) -- @keys

    if unknown != [] do
      raise ArgumentError, "unknown application tree configuration: #{inspect(unknown)}"
    end

    config = struct!(__MODULE__, options)
    validate!(config)
  end

  @spec categories() :: [category()]
  @doc "Returns the supported deterministic category identifiers."
  def categories do
    @categories
  end

  defp validate!(config) do
    with :ok <- validate_atom_list(config.host_applications, :host_applications),
         :ok <- validate_order(config.category_order),
         :ok <- validate_labels(config.category_labels),
         :ok <- validate_mappings(config.application_categories),
         :ok <- validate_classifier(config.classify_application) do
      %{config | category_labels: Map.merge(@default_labels, config.category_labels)}
    else
      {:error, message} ->
        raise ArgumentError, "invalid application tree configuration: #{message}"
    end
  end

  defp validate_atom_list(values, _field) when is_list(values) do
    if Enum.all?(values, &is_atom/1), do: :ok, else: {:error, "host applications must be atoms"}
  end

  defp validate_atom_list(_values, _field) do
    {:error, "host applications must be a list"}
  end

  defp validate_order(values) when is_list(values) do
    if Enum.sort(values) == Enum.sort(@categories) and length(values) == length(Enum.uniq(values)) do
      :ok
    else
      {:error, "category order must contain every supported category exactly once"}
    end
  end

  defp validate_order(_values) do
    {:error, "category order must be a list"}
  end

  defp validate_labels(labels) when is_map(labels) do
    valid? =
      Enum.all?(labels, fn {category, label} ->
        category in @categories and is_binary(label) and byte_size(label) > 0 and
          byte_size(label) <= 48
      end)

    if valid?,
      do: :ok,
      else: {:error, "category labels must be bounded strings for known categories"}
  end

  defp validate_labels(_labels) do
    {:error, "category labels must be a map"}
  end

  defp validate_mappings(mappings) when is_map(mappings) do
    if Enum.all?(mappings, fn {application, category} ->
         is_atom(application) and category in @categories
       end) do
      :ok
    else
      {:error, "application mappings must use atom names and known categories"}
    end
  end

  defp validate_mappings(_mappings) do
    {:error, "application mappings must be a map"}
  end

  defp validate_classifier(nil) do
    :ok
  end

  defp validate_classifier({module, function, arguments})
       when is_atom(module) and is_atom(function) and is_list(arguments) do
    :ok
  end

  defp validate_classifier(_classifier) do
    {:error, "classifier must be an MFA tuple"}
  end
end
