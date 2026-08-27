defmodule BeamConsoleWeb.Console.ParamsTest do
  use ExUnit.Case, async: true

  alias BeamConsoleWeb.Console.Params
  alias BeamConsoleWeb.Console.Paths

  test "normalizes untrusted URL values without atom conversion" do
    params =
      Params.normalize(
        %{
          "q" => String.duplicate("a", 200),
          "kind" => "not-an-event",
          "window" => "forever",
          "edges" => "everything",
          "entity" => " proc_123 "
        },
        :unknown_action
      )

    assert params.tab == :process_map
    assert String.length(params.query) == 120
    assert params.kind == "all"
    assert params.window == "5m"
    assert params.edges == "supervision"
    assert params.selected_id == "proc_123"
  end

  test "builds nested tab paths with only relevant parameters" do
    params = Params.normalize(%{"entity" => "proc_1", "kind" => "terminated"}, :lifecycle)

    assert Paths.path("/dev/beam", :lifecycle, params) ==
             "/dev/beam/lifecycle?entity=proc_1&kind=terminated"

    assert Paths.path("/dev/beam", :activity, params) ==
             "/dev/beam/activity?entity=proc_1"
  end

  test "builds absolute paths for a root console mount" do
    params = Params.normalize(%{"q" => "worker"}, :process_map)

    assert Paths.path("/", :process_map, %{}) == "/"
    assert Paths.path("/", :process_map, params) == "/?q=worker"
    assert Paths.path("/", :lifecycle, params) == "/lifecycle?q=worker"
  end
end
