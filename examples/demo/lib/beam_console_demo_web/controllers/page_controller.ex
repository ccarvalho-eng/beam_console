defmodule BeamConsoleDemoWeb.PageController do
  use BeamConsoleDemoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
