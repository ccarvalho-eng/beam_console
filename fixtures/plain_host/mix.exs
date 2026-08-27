defmodule BeamConsolePlainHost.MixProject do
  use Mix.Project

  def project do
    [app: :beam_console_plain_host, version: "0.1.0", elixir: "~> 1.17", deps: deps()]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [{:beam_console, path: "../.."}]
  end
end
