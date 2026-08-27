defmodule BeamConsoleWeb.AssetsTest do
  use ExUnit.Case, async: true

  import Plug.Conn, only: [get_resp_header: 2]
  import Plug.Test

  alias BeamConsoleWeb.Assets

  test "serves current digests with immutable caching" do
    conn = asset_conn(Assets.css_digest())
    conn = Assets.css(conn, %{})

    assert conn.status == 200
    assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
    assert get_resp_header(conn, "content-type") == ["text/css; charset=utf-8"]
    assert conn.resp_body =~ ".beam-console-shell"
  end

  test "rejects stale asset digests" do
    conn = asset_conn("stale")
    conn = Assets.js(conn, %{})

    assert conn.status == 404
  end

  test "serves the vendored graph module" do
    conn = asset_conn(Assets.cytoscape_digest())
    conn = Assets.cytoscape(conn, %{})

    assert conn.status == 200
    assert conn.resp_body =~ "cytoscape"
  end

  test "serves each embedded JavaScript module at its current digest" do
    assets = [
      {&Assets.js/2, Assets.js_digest(), "LiveSocket"},
      {&Assets.phoenix/2, Assets.phoenix_digest(), "Socket"},
      {&Assets.live_view/2, Assets.live_view_digest(), "LiveSocket"}
    ]

    Enum.each(assets, fn {serve, digest, expected_source} ->
      conn = digest |> asset_conn() |> serve.(%{})

      assert conn.status == 200

      assert get_resp_header(conn, "cache-control") == [
               "public, max-age=31536000, immutable"
             ]

      assert conn.resp_body =~ expected_source
    end)
  end

  test "rejects stale digests for every embedded asset" do
    Enum.each(
      [&Assets.css/2, &Assets.js/2, &Assets.phoenix/2, &Assets.live_view/2, &Assets.cytoscape/2],
      fn serve ->
        conn = "stale" |> asset_conn() |> serve.(%{})

        assert conn.status == 404
        assert conn.resp_body == "Not Found"
      end
    )
  end

  defp asset_conn(digest) do
    conn(:get, "/")
    |> Map.put(:params, %{"digest" => digest})
  end
end
