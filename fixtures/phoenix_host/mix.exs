defmodule BeamConsolePhoenixHost.MixProject do
  use Mix.Project

  def project do
    [
      app: :beam_console_phoenix_host,
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
      {:jason, "~> 1.4"},
      {:phoenix, dependency_version("PHOENIX_VERSION", "~> 1.8.9")},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, dependency_version("LIVE_VIEW_VERSION", "~> 1.2.0")}
    ]
  end

  defp dependency_version(name, default) do
    System.get_env(name, default)
  end
end
