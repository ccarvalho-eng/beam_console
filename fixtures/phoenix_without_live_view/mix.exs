defmodule BeamConsolePhoenixWithoutLiveView.MixProject do
  use Mix.Project

  def project do
    [
      app: :beam_console_phoenix_without_live_view,
      version: "0.1.0",
      elixir: "~> 1.17",
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:beam_console, path: "../.."},
      {:phoenix, "~> 1.8.9"}
    ]
  end
end
