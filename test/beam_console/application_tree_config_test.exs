defmodule BeamConsole.ApplicationTreeConfigTest do
  use ExUnit.Case, async: true

  alias BeamConsole.ApplicationTreeConfig

  test "validates category overrides and labels" do
    config =
      ApplicationTreeConfig.new!(
        host_applications: [:my_app],
        category_labels: %{host: "My application"},
        application_categories: %{phoenix: :dependencies}
      )

    assert config.host_applications == [:my_app]
    assert config.category_labels.host == "My application"
    assert config.category_labels.otp == "Erlang / OTP"
  end

  test "rejects unknown categories and malformed callbacks" do
    assert_raise ArgumentError, fn ->
      ApplicationTreeConfig.new!(application_categories: %{sample: :unknown})
    end

    assert_raise ArgumentError, fn ->
      ApplicationTreeConfig.new!(classify_application: :unsafe)
    end
  end
end
