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

  defmodule RootRouter do
    use Phoenix.Router

    import BeamConsole.Router

    beam_console("/", enabled: true, as: :root_beam_console)
  end

  def host_session(_conn, role) do
    %{"current_role" => role, "prefix" => "cannot-override"}
  end

  test "mounts console and package assets below a nested host prefix" do
    routes = NestedRouter.__routes__()
    paths = Enum.map(routes, & &1.path)

    assert "/dev/beam" in paths
    assert "/dev/beam/lifecycle" in paths
    assert "/dev/beam/activity" in paths
    assert "/dev/beam/runtime" in paths
    assert "/dev/beam/assets/css/:digest" in paths
    assert "/dev/beam/assets/js/:digest" in paths
    assert "/dev/beam/assets/cytoscape/:digest" in paths
    assert "/dev/beam/assets/support/:digest" in paths
    assert "/dev/beam/assets/theme/:digest" in paths

    asset_routes = Enum.filter(routes, &String.contains?(&1.path, "/assets/"))
    assert Enum.all?(asset_routes, &is_nil(&1.helper))
  end

  test "omits every route when explicitly disabled" do
    assert DisabledRouter.__routes__() == []
  end

  test "mounts the process map at the host root" do
    paths = Enum.map(RootRouter.__routes__(), & &1.path)

    assert "/" in paths
    assert "/lifecycle" in paths
    assert "/assets/css/:digest" in paths
  end

  test "builds a minimal session containing only mount and transport configuration" do
    session = BeamConsole.Router.__session__(%{}, "/dev/beam", "/live", "longpoll")

    assert session == %{
             "live_path" => "/live",
             "live_transport" => "longpoll",
             "prefix" => "/dev/beam"
           }
  end

  test "preserves an endpoint or forwarding script-name prefix" do
    conn = %{script_name: ["internal", "myapp"]}
    session = BeamConsole.Router.__session__(conn, "/dev/beam", "/live", "websocket")

    assert session["prefix"] == "/internal/myapp/dev/beam"
    assert session["live_path"] == "/live"

    custom =
      BeamConsole.Router.__session__(
        conn,
        "/dev/beam",
        "/external/myapp/live",
        "websocket"
      )

    assert custom["live_path"] == "/external/myapp/live"
  end

  test "rejects unsupported and malformed options" do
    assert_raise ArgumentError, fn ->
      BeamConsole.Router.__options__("/beam", transport: "sse")
    end

    assert_raise ArgumentError, fn ->
      BeamConsole.Router.__options__("/beam", unknown: true)
    end

    assert_raise ArgumentError, fn ->
      BeamConsole.Router.__options__("/beam", session: %{role: "admin"})
    end
  end

  test "merges host authorization session data without allowing reserved overrides" do
    session =
      BeamConsole.Router.__session__(
        %{},
        "/beam",
        "/live",
        "websocket",
        {__MODULE__, :host_session, ["admin"]}
      )

    assert session["current_role"] == "admin"
    assert session["prefix"] == "/beam"
  end

  test "accepts host on-mount hooks" do
    {_name, options, _route} =
      BeamConsole.Router.__options__("/beam", on_mount: [{MyAppWeb.Auth, :admin}])

    assert options[:on_mount] == [{MyAppWeb.Auth, :admin}, BeamConsoleWeb.Hooks]
  end
end
