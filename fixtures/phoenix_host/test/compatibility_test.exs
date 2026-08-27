defmodule BeamConsolePhoenixHost.CompatibilityTest do
  use ExUnit.Case, async: true

  test "compiles the complete embedded console route set" do
    paths = Enum.map(BeamConsolePhoenixHost.Router.__routes__(), & &1.path)

    assert "/beam" in paths
    assert "/beam/lifecycle" in paths
    assert "/beam/activity" in paths
    assert "/beam/runtime" in paths
    assert "/beam/assets/support/:digest" in paths
  end
end
