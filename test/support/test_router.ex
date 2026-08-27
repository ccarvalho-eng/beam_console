defmodule BeamConsoleWeb.TestRouter do
  @moduledoc false

  use Phoenix.Router

  import BeamConsole.Router
  import Phoenix.LiveView.Router, only: [fetch_live_flash: 2]

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:protect_from_forgery)
  end

  scope "/" do
    pipe_through(:browser)

    beam_console("/beam", enabled: true)

    beam_console("/secure-beam",
      as: :secure_beam_console,
      enabled: true,
      session: %{"current_role" => "admin"},
      on_mount: [{BeamConsoleWeb.TestAuthHook, :admin}]
    )

    beam_console("/blocked-beam",
      as: :blocked_beam_console,
      enabled: true,
      session: %{"current_role" => "viewer"},
      on_mount: [{BeamConsoleWeb.TestAuthHook, :admin}]
    )
  end
end

defmodule BeamConsoleWeb.TestAuthHook do
  @moduledoc false

  import Phoenix.LiveView, only: [redirect: 2]

  @doc "Authorizes the fixture console only for the configured admin session."
  @spec on_mount(atom(), map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont | :halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:admin, _params, %{"current_role" => "admin"}, socket) do
    {:cont, Phoenix.Component.assign(socket, :authorized_by_host?, true)}
  end

  def on_mount(:admin, _params, _session, socket) do
    {:halt, redirect(socket, to: "/")}
  end
end
