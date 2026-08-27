defmodule BeamConsoleWeb.Console.ApplicationTreePresenterTest do
  use ExUnit.Case, async: true

  alias BeamConsole.ApplicationInfo
  alias BeamConsole.ApplicationTreeConfig
  alias BeamConsole.Snapshot
  alias BeamConsoleWeb.Console.ApplicationTreePresenter

  test "groups host, dependency, OTP, and tooling applications deterministically" do
    applications = [
      application(:my_app, :external, [:phoenix]),
      application(:phoenix, :external, []),
      application(:kernel, :otp, []),
      application(:beam_console, :external, [])
    ]

    snapshot = %Snapshot{
      sequence: 1,
      sampled_at: ~U[2026-01-01 00:00:00Z],
      local_node_id: "node",
      applications: Map.new(applications, &{&1.id, &1})
    }

    categories = ApplicationTreePresenter.present(snapshot, ApplicationTreeConfig.new!())

    assert names(categories, :host) == [:my_app]
    assert names(categories, :dependencies) == [:phoenix]
    assert names(categories, :otp) == [:kernel]
    assert names(categories, :tooling) == [:beam_console]
  end

  defp names(categories, category) do
    categories
    |> Enum.find(&(&1.category == category))
    |> Map.fetch!(:applications)
    |> Enum.map(& &1.name)
  end

  defp application(name, origin, required) do
    %ApplicationInfo{
      id: "app_#{name}",
      name: name,
      node_id: "node",
      origin: origin,
      required_applications: required
    }
  end
end
