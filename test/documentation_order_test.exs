defmodule BeamConsole.DocumentationOrderTest do
  use ExUnit.Case, async: true

  test "documentation attributes precede public typespecs" do
    violations =
      source_paths()
      |> Enum.flat_map(&violations/1)

    assert violations == []
  end

  test "implementation attributes name their behaviour" do
    anonymous_implementation = "@impl " <> "true"

    violations =
      (source_paths() ++ Path.wildcard("test/**/*.exs", match_dot: true))
      |> Enum.filter(fn path ->
        path
        |> File.read!()
        |> String.contains?(anonymous_implementation)
      end)

    assert violations == []
  end

  test "demo public functions keep documentation and typespec contracts" do
    violations =
      "examples/demo/lib/**/*.ex"
      |> Path.wildcard(match_dot: true)
      |> Enum.flat_map(&public_contract_violations/1)

    assert violations == []
  end

  defp source_paths do
    Path.wildcard("lib/**/*.ex", match_dot: true) ++
      Path.wildcard("examples/demo/lib/**/*.ex", match_dot: true)
  end

  defp violations(path) do
    lines = File.read!(path) |> String.split("\n")

    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      case Regex.run(~r/^(\s*)@spec\b/, line) do
        [_, indentation] ->
          next_attribute_violation(lines, path, line_number, indentation)

        nil ->
          []
      end
    end)
  end

  defp public_contract_violations(path) do
    lines = File.read!(path) |> String.split("\n")

    {_seen, violations} =
      lines
      |> Enum.with_index(1)
      |> Enum.reduce({MapSet.new(), []}, fn {line, line_number}, {seen, violations} ->
        case Regex.run(~r/^\s*def(?:macro)?\s+([a-zA-Z0-9_!?]+)/, line) do
          [_, name] -> check_public_contract(lines, path, line_number, name, seen, violations)
          nil -> {seen, violations}
        end
      end)

    Enum.reverse(violations)
  end

  defp check_public_contract(lines, path, line_number, name, seen, violations) do
    if MapSet.member?(seen, name) do
      {seen, violations}
    else
      attributes = preceding_attributes(lines, line_number)
      documented? = Enum.any?(attributes, &Regex.match?(~r/^\s*@doc\b/, &1))
      specified? = Enum.any?(attributes, &Regex.match?(~r/^\s*@spec\b/, &1))
      implemented? = Enum.any?(attributes, &Regex.match?(~r/^\s*@impl\b/, &1))

      violations =
        if implemented? or (documented? and specified?) do
          violations
        else
          ["#{path}:#{line_number}:#{name}" | violations]
        end

      {MapSet.put(seen, name), violations}
    end
  end

  defp preceding_attributes(lines, line_number) do
    lines
    |> Enum.take(line_number - 1)
    |> Enum.reverse()
    |> Enum.take_while(&(not Regex.match?(~r/^\s*def(?:macro|macrop|p)?\b/, &1)))
  end

  defp next_attribute_violation(lines, path, line_number, indentation) do
    following_lines = Enum.drop(lines, line_number)
    boundary = ~r/^#{Regex.escape(indentation)}(?:@(doc|spec)\b|def(?:macro|macrop|p)?\b)/

    case Enum.find(following_lines, &Regex.match?(boundary, &1)) do
      nil ->
        []

      line ->
        if Regex.match?(~r/^#{Regex.escape(indentation)}@doc\b/, line) do
          ["#{path}:#{line_number}"]
        else
          []
        end
    end
  end
end
