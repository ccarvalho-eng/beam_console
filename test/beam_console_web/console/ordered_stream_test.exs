defmodule BeamConsoleWeb.Console.OrderedStreamTest do
  use ExUnit.Case, async: true

  alias BeamConsoleWeb.Console.OrderedStream

  test "distinguishes value updates from actual order changes" do
    first = [%{id: "alpha", value: 10}, %{id: "beta", value: 5}]
    updated = [%{id: "alpha", value: 12}, %{id: "beta", value: 7}]
    reordered = Enum.reverse(updated)

    previous_ids = OrderedStream.ids(first)

    refute OrderedStream.reordered?(previous_ids, OrderedStream.ids(updated))
    assert OrderedStream.reordered?(previous_ids, OrderedStream.ids(reordered))
  end

  test "detects when a process label change alters presenter order" do
    original = [%{id: "alpha", label: "Alpha"}, %{id: "beta", label: "Beta"}]
    renamed = [%{id: "alpha", label: "Zulu"}, %{id: "beta", label: "Beta"}]
    renamed = Enum.sort_by(renamed, & &1.label)

    assert OrderedStream.reordered?(
             OrderedStream.ids(original),
             OrderedStream.ids(renamed)
           )
  end
end
