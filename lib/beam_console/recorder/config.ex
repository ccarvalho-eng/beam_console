defmodule BeamConsole.Recorder.Config do
  @moduledoc """
  Validates the hard resource limits used by the in-memory flight recorder.

  Defaults keep recording bounded independently of browser count. The
  `:subscribers` mode activates recording only while the console has at least
  one subscriber; `:always` is an explicit higher-overhead choice.
  """

  @positive_fields [
    :retention_ms,
    :event_limit,
    :frame_limit,
    :watch_limit,
    :reconciliation_limit,
    :pending_slot_ms,
    :chart_points_limit,
    :timeline_limit,
    :byte_limit
  ]

  defstruct retention_ms: 15 * 60 * 1_000,
            event_limit: 1_000,
            frame_limit: 450,
            watch_limit: 5_000,
            reconciliation_limit: 500,
            pending_slot_ms: 30_000,
            chart_points_limit: 240,
            timeline_limit: 500,
            byte_limit: 8 * 1_024 * 1_024,
            mode: :subscribers

  @type mode :: :subscribers | :always
  @type t :: %__MODULE__{
          retention_ms: pos_integer(),
          event_limit: pos_integer(),
          frame_limit: pos_integer(),
          watch_limit: pos_integer(),
          reconciliation_limit: pos_integer(),
          pending_slot_ms: pos_integer(),
          chart_points_limit: pos_integer(),
          timeline_limit: pos_integer(),
          byte_limit: pos_integer(),
          mode: mode()
        }

  @type validation_error ::
          {:invalid_options, term()}
          | {:unknown_options, [atom()]}
          | {atom(), :must_be_positive}
          | {:mode, :must_be_subscribers_or_always}
          | {:reconciliation_limit, :exceeds_watch_limit}
          | {:timeline_limit, :exceeds_event_limit}

  @doc "Returns the recorder's conservative default limits."
  @spec defaults() :: t()
  def defaults do
    %__MODULE__{}
  end

  @doc """
  Builds recorder configuration from validated keyword overrides.

  Unknown fields and internally inconsistent limits return structured errors.
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, validation_error()}
  def new(options \\ []) do
    with :ok <- validate_keyword(options),
         :ok <- validate_known_options(options) do
      config = struct!(__MODULE__, options)

      with :ok <- validate_positive_fields(config),
           :ok <- validate_mode(config),
           :ok <- validate_relationships(config) do
        {:ok, config}
      end
    end
  end

  @doc "Builds recorder configuration and raises `ArgumentError` when it is invalid."
  @spec new!(keyword()) :: t()
  def new!(options \\ []) do
    case new(options) do
      {:ok, config} ->
        config

      {:error, reason} ->
        raise ArgumentError, "invalid recorder configuration: #{inspect(reason)}"
    end
  end

  @doc """
  Loads `:beam_console, :recorder` application configuration and applies overrides.

  Runtime overrides take precedence over application configuration.
  """
  @spec load(keyword()) :: t()
  def load(overrides \\ []) do
    configured = Application.get_env(:beam_console, :recorder, [])

    if Keyword.keyword?(configured) and Keyword.keyword?(overrides) do
      configured
      |> Keyword.merge(overrides)
      |> new!()
    else
      raise ArgumentError, "recorder configuration must be a keyword list"
    end
  end

  defp validate_keyword(options) do
    if Keyword.keyword?(options), do: :ok, else: {:error, {:invalid_options, options}}
  end

  defp validate_known_options(options) do
    unknown = Keyword.keys(options) -- Map.keys(defaults())
    if unknown == [], do: :ok, else: {:error, {:unknown_options, Enum.uniq(unknown)}}
  end

  defp validate_positive_fields(config) do
    Enum.find_value(@positive_fields, :ok, fn field ->
      value = Map.fetch!(config, field)
      if is_integer(value) and value > 0, do: false, else: {:error, {field, :must_be_positive}}
    end)
  end

  defp validate_mode(%__MODULE__{mode: mode}) when mode in [:subscribers, :always] do
    :ok
  end

  defp validate_mode(_config) do
    {:error, {:mode, :must_be_subscribers_or_always}}
  end

  defp validate_relationships(config) do
    cond do
      config.reconciliation_limit > config.watch_limit ->
        {:error, {:reconciliation_limit, :exceeds_watch_limit}}

      config.timeline_limit > config.event_limit ->
        {:error, {:timeline_limit, :exceeds_event_limit}}

      true ->
        :ok
    end
  end
end
