defmodule BeamConsole.ReasonSummaryTest do
  use ExUnit.Case, async: true

  alias BeamConsole.ReasonSummary

  test "classifies known lifecycle and connection reasons" do
    assert ReasonSummary.sanitize(:normal).category == :normal
    assert ReasonSummary.sanitize({:shutdown, :restart}).category == :shutdown
    assert ReasonSummary.sanitize(:killed).category == :killed
    assert ReasonSummary.sanitize(:noproc).category == :missing
    assert ReasonSummary.sanitize(:noconnection).category == :connection
  end

  test "never copies binary, list, map, pid, reference, or function values" do
    secret = "api-secret-value"

    values = [
      secret,
      [secret],
      %{token: secret},
      self(),
      make_ref(),
      fn -> secret end
    ]

    Enum.each(values, fn value ->
      summary = ReasonSummary.sanitize({:error, value})
      refute summary.text =~ secret
    end)
  end

  test "bounds nested structures and UTF-8 output by bytes" do
    reason = {:outer, {:inner, {:deep, "sensitive"}}, :extra, :values}
    summary = ReasonSummary.sanitize(reason, max_bytes: 24, max_depth: 2, max_items: 2)

    assert byte_size(summary.text) <= 24
    assert String.valid?(summary.text)
    refute summary.text =~ "sensitive"
  end

  test "summarizes exceptions without retaining their messages" do
    summary = ReasonSummary.sanitize(%RuntimeError{message: "private token"})

    assert summary.text == "RuntimeError exception"
    refute summary.text =~ "private token"
  end

  test "summarizes scalar and opaque runtime value shapes" do
    reason = {1, 1.5, %{key: :value}, [:item], self(), make_ref(), fn -> :ok end}
    summary = ReasonSummary.sanitize(reason, max_items: 10)

    assert summary.text =~ "1"
    assert summary.text =~ "1.5"
    assert summary.text =~ "map(1 entries)"
    assert summary.text =~ "list(1 items)"
    assert summary.text =~ "pid"
    assert summary.text =~ "reference"
    assert summary.text =~ "function"

    invalid_options = ReasonSummary.sanitize(:error, max_bytes: 0, max_depth: 0, max_items: 0)
    assert invalid_options.text == "error"
  end

  test "sanitizes improper lists without crashing or retaining their tail" do
    summary = ReasonSummary.sanitize({:error, ["private" | {:token, "secret"}]})

    assert summary.text == "{error, improper_list(1 heads)}"
    refute summary.text =~ "private"
    refute summary.text =~ "secret"
  end
end
