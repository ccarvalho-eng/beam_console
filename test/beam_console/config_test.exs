defmodule BeamConsole.ConfigTest do
  use ExUnit.Case, async: false

  alias BeamConsole.Config

  setup do
    previous = Application.get_env(:beam_console, :collector)

    on_exit(fn ->
      if previous do
        Application.put_env(:beam_console, :collector, previous)
      else
        Application.delete_env(:beam_console, :collector)
      end
    end)
  end

  test "loads validated collector settings from application configuration" do
    Application.put_env(:beam_console, :collector, interval: 5_000, process_limit: 4_000)

    config = Config.collector(scan_timeout: 900)

    assert config[:interval] == 5_000
    assert config[:scan_timeout] == 900
    assert config[:process_limit] == 4_000
  end

  test "rejects unknown and invalid collector settings" do
    Application.put_env(:beam_console, :collector, unknown_limit: 1)

    assert_raise ArgumentError, ~r/unknown collector configuration/, fn ->
      Config.collector()
    end

    Application.put_env(:beam_console, :collector, interval: 0)

    assert_raise ArgumentError, ~r/interval must be a positive integer/, fn ->
      Config.collector()
    end
  end
end
