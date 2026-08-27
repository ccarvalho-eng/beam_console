defmodule BeamConsoleWeb.TestEndpoint do
  @moduledoc false

  use Phoenix.Endpoint, otp_app: :beam_console

  @session_options [
    store: :cookie,
    key: "_beam_console_test",
    signing_salt: "beam-console-test"
  ]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  plug(Plug.Session, @session_options)
  plug(BeamConsoleWeb.TestRouter)
end
