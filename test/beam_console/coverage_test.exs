defmodule BeamConsole.CoverageTest do
  use ExUnit.Case, async: true

  alias BeamConsole.Coverage

  test "classifies vanished processes as partial coverage" do
    coverage = %Coverage{vanished_pids: 2}

    assert Coverage.state(coverage) == :partial
    assert Coverage.warnings(coverage) == ["2 processes vanished during inspection"]
  end

  test "classifies bounded samples as truncated and lists every limitation" do
    coverage = %Coverage{
      process_limit_reached?: true,
      traversal_limit_reached?: true,
      vanished_pids: 1,
      partial_supervisors: 3
    }

    assert Coverage.state(coverage) == :truncated

    assert Coverage.warnings(coverage) == [
             "Process limit reached",
             "Supervision traversal limit reached",
             "1 process vanished during inspection",
             "3 supervision branches were partial"
           ]
  end

  test "classifies fully observed samples as complete" do
    coverage = %Coverage{}

    assert Coverage.state(coverage) == :complete
    assert Coverage.warnings(coverage) == []
  end
end
