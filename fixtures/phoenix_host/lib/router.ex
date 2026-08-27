defmodule BeamConsolePhoenixHost.Router do
  @moduledoc false

  use Phoenix.Router

  import BeamConsole.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
  end

  scope "/" do
    pipe_through :browser

    beam_console "/beam", enabled: true
  end
end
