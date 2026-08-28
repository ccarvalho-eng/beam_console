defmodule BeamConsole.MixProject do
  use Mix.Project

  @source_url "https://github.com/ccarvalho-eng/beam_console"
  @version "0.5.2"

  def project do
    [
      app: :beam_console,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      description: "An embeddable process flight recorder and process map for BEAM applications.",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: [
        main: "readme",
        extras: ["README.md", "CHANGELOG.md"],
        source_ref: "v#{@version}",
        source_url: @source_url
      ],
      package: package(),
      deps: deps(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [summary: [threshold: 82]],
      dialyzer: [
        plt_add_apps: [:ex_unit, :mix],
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        ignore_warnings: ".dialyzer_ignore.exs"
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:crypto, :logger],
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
      {:lazy_html, ">= 0.1.0", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.23.0", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.15", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "Changelog" => "https://hexdocs.pm/beam_console/changelog.html",
        "Documentation" => "https://hexdocs.pm/beam_console",
        "GitHub" => @source_url
      },
      files: ~w(lib priv/static mix.exs README.md CHANGELOG.md LICENSE THIRD_PARTY_NOTICES)
    ]
  end

  defp aliases do
    [
      quality: [
        "compile --warnings-as-errors",
        "xref graph --format cycles --label compile-connected --fail-above 0",
        "xref graph --format cycles --fail-above 0",
        "deps.unlock --check-unused",
        "format --check-formatted",
        "credo --strict --min-priority high",
        "doctor --raise",
        "sobelow --skip --no-router --ignore Config.HTTPS --private --exit",
        "deps.audit",
        "dialyzer --list-unused-filters"
      ],
      precommit: [
        "quality",
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
