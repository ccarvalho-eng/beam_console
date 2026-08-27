defmodule BeamConsoleDemoWeb.PageController do
  use BeamConsoleDemoWeb, :controller

  @doc "Renders the demo process-laboratory page."
  @spec home(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def home(conn, _params) do
    render(conn, :home)
  end
end
