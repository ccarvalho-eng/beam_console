defmodule BeamConsole.Recorder.ConfigTest do
  use ExUnit.Case, async: false

  alias BeamConsole.Recorder.Config

  test "exposes conservative bounded defaults" do
    config = Config.defaults()

    assert config.retention_ms == 900_000
    assert config.event_limit == 1_000
    assert config.frame_limit == 450
    assert config.watch_limit == 5_000
    assert config.total_points_limit == 14_400
    assert config.byte_limit == 8 * 1_024 * 1_024
    assert config.mode == :subscribers
  end

  test "accepts valid overrides" do
    assert {:ok, config} =
             Config.new(
               event_limit: 20,
               timeline_limit: 10,
               points_per_series: 30,
               chart_points_limit: 15,
               mode: :always
             )

    assert config.event_limit == 20
    assert config.timeline_limit == 10
    assert config.mode == :always
  end

  test "default constructors and application loader return validated configuration" do
    previous = Application.get_env(:beam_console, :recorder)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:beam_console, :recorder)
      else
        Application.put_env(:beam_console, :recorder, previous)
      end
    end)

    assert {:ok, %Config{}} = Config.new()
    assert %Config{} = Config.new!()

    Application.put_env(:beam_console, :recorder, event_limit: 20, timeline_limit: 20)
    assert Config.load(event_limit: 10, timeline_limit: 10).event_limit == 10
    assert BeamConsole.Config.recorder(timeline_limit: 5).timeline_limit == 5

    Application.put_env(:beam_console, :recorder, %{event_limit: 20})

    assert_raise ArgumentError, ~r/keyword list/, fn ->
      Config.load()
    end
  end

  test "rejects unknown, non-positive, and invalid mode values" do
    assert {:error, {:invalid_options, %{}}} = Config.new(%{})
    assert {:error, {:unknown_options, [:unknown]}} = Config.new(unknown: 1)
    assert {:error, {:event_limit, :must_be_positive}} = Config.new(event_limit: 0)
    assert {:error, {:retention_ms, :must_be_positive}} = Config.new(retention_ms: -1)
    assert {:error, {:mode, :must_be_subscribers_or_always}} = Config.new(mode: :sometimes)
  end

  test "rejects internally inconsistent limits" do
    assert {:error, {:reconciliation_limit, :exceeds_watch_limit}} =
             Config.new(watch_limit: 10, reconciliation_limit: 11)

    assert {:error, {:chart_points_limit, :exceeds_points_per_series}} =
             Config.new(points_per_series: 10, chart_points_limit: 11)

    assert {:error, {:timeline_limit, :exceeds_event_limit}} =
             Config.new(event_limit: 10, timeline_limit: 11)
  end

  test "raising constructor includes the invalid field" do
    assert_raise ArgumentError, ~r/event_limit/, fn ->
      Config.new!(event_limit: 0)
    end
  end
end
