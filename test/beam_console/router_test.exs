defmodule BeamConsole.RouterTest do
  use ExUnit.Case, async: true

  defmodule NestedRouter do
    use Phoenix.Router

    import BeamConsole.Router

    scope "/dev" do
      beam_console("/beam", enabled: true, as: :runtime_atlas)
    end
  end

  defmodule DisabledRouter do
    use Phoenix.Router

    import BeamConsole.Router

    beam_console("/beam", enabled: false)
  end

  test "mounts console and package assets below a nested host prefix" do
    paths = Enum.map(NestedRouter.__routes__(), & &1.path)

    assert "/dev/beam" in paths
    assert "/dev/beam/lifecycle" in paths
    assert "/dev/beam/activity" in paths
    assert "/dev/beam/runtime" in paths
    assert "/dev/beam/assets/css/:digest" in paths
    assert "/dev/beam/assets/js/:digest" in paths
    assert "/dev/beam/assets/cytoscape/:digest" in paths
  end

  test "omits every route when explicitly disabled" do
    assert DisabledRouter.__routes__() == []
  end

  test "builds a minimal session containing only mount and transport configuration" do
    session = BeamConsole.Router.__session__(%{}, "/dev/beam", "/live", "longpoll")

    assert session == %{
             "live_path" => "/live",
             "live_transport" => "longpoll",
             "prefix" => "/dev/beam"
           }
  end

  test "rejects unsupported and malformed options" do
    assert_raise ArgumentError, fn ->
      BeamConsole.Router.__options__("/beam", transport: "sse")
    end

    assert_raise ArgumentError, fn ->
      BeamConsole.Router.__options__("/beam", unknown: true)
    end
  end
end
