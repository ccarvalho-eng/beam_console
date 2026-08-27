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
  end
end
