import Config

config :beam_console, BeamConsoleWeb.TestEndpoint,
  debug_errors: true,
  http: [ip: {127, 0, 0, 1}, port: 0],
  live_view: [signing_salt: "beam-console-live-view-test"],
  secret_key_base: String.duplicate("beam-console-test-secret-", 4),
  server: false,
  url: [host: "localhost"]
