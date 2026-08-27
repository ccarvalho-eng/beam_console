defmodule BeamConsolePhoenixWithoutLiveView.OptionalWebTest do
  use ExUnit.Case, async: true

  test "keeps the core available without compiling LiveView assets" do
    assert Code.ensure_loaded?(BeamConsole)
    refute Code.ensure_loaded?(BeamConsoleWeb.Assets)
  end
end
