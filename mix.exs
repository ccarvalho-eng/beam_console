defmodule BeamConsole.MixProject do
  use Mix.Project

  def project do
    [
      app: :beam_console,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      description: "An embeddable process map for BEAM applications.",
      package: package(),
      deps: deps(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {BeamConsole.Application, []}
    ]
  end

  def cli do
    [preferred_envs: [precommit: :test]]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:phoenix, "~> 1.8.9", optional: true},
      {:phoenix_html, "~> 4.1", optional: true},
      {:phoenix_live_view, "~> 1.2.0", optional: true},
      {:jason, "~> 1.4", optional: true},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      files: ~w(lib priv mix.exs README.md LICENSE THIRD_PARTY_NOTICES)
    ]
  end

  defp aliases do
    [
      precommit: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "test"
      ]
    ]
  end

  defp elixirc_paths(:test) do
    ["lib", "test/support"]
  end

  defp elixirc_paths(_environment) do
    ["lib"]
  end
end
