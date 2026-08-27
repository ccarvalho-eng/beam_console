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

    assert summary.text == "exception"
    refute summary.text =~ "private token"
  end

  test "redacts arbitrary atom names while preserving a fixed diagnostic allowlist" do
    summary = ReasonSummary.sanitize({:customer_token_name, :badmatch})

    assert summary.text == "{atom, badmatch}"
    refute summary.text =~ "customer"
  end

  test "summarizes scalar and opaque runtime value shapes" do
    reason = {1, 1.5, %{key: :value}, [:item], self(), make_ref(), fn -> :ok end}
    summary = ReasonSummary.sanitize(reason, max_items: 10)

    assert summary.text =~ "integer"
    assert summary.text =~ "float"
    assert summary.text =~ "map(1 entries)"
    assert summary.text =~ "list(1 items)"
    assert summary.text =~ "pid"
    assert summary.text =~ "reference"
    assert summary.text =~ "function"

    invalid_options = ReasonSummary.sanitize(:error, max_bytes: 0, max_depth: 0, max_items: 0)
    assert invalid_options.text == "error"
  end

  test "redacts arbitrary numeric values" do
    summary = ReasonSummary.sanitize({:error, 4_111_111_111_111_111, 123.456})

    assert summary.text == "{error, integer, float}"
    refute summary.text =~ "411111"
    refute summary.text =~ "123.456"
  end

  test "sanitizes improper lists without crashing or retaining their tail" do
    summary = ReasonSummary.sanitize({:error, ["private" | {:token, "secret"}]})

    assert summary.text == "{error, improper_list(1 heads)}"
    refute summary.text =~ "private"
    refute summary.text =~ "secret"
  end

  test "bounds structural work for very large list reasons" do
    reason = List.duplicate(:opaque, 20_000)
    {:reductions, before_reductions} = Process.info(self(), :reductions)

    summary = ReasonSummary.sanitize({:error, reason})

    {:reductions, after_reductions} = Process.info(self(), :reductions)
    assert summary.text == "{error, list(more than 32 items)}"
    assert after_reductions - before_reductions < 10_000
  end

  test "honors byte limits smaller than the Unicode truncation suffix" do
    for max_bytes <- 1..3 do
      summary = ReasonSummary.sanitize(:normal, max_bytes: max_bytes)

      assert byte_size(summary.text) <= max_bytes
    end
  end
end
