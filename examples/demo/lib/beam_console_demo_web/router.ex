defmodule BeamConsoleDemoWeb.Router do
  use BeamConsoleDemoWeb, :router

  import BeamConsole.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BeamConsoleDemoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", BeamConsoleDemoWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/lab", LabLive
    beam_console("/beam", enabled: true)
  end

  # Other scopes may use custom stacks.
  # scope "/api", BeamConsoleDemoWeb do
  #   pipe_through :api
  # end
end
