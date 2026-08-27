if Code.ensure_loaded?(Phoenix.Controller) do
  defmodule BeamConsoleWeb.Assets do
    @moduledoc """
    Serves BeamConsole's self-contained, digest-addressed browser assets.

    Requests with stale or unknown digests return `404`; current assets are
    immutable and can be cached indefinitely.
    """

    use Phoenix.Controller, formats: []

    @static_path Application.app_dir(:beam_console, "priv/static")

    @external_resource css_path = Path.join(@static_path, "beam_console.css")
    @css File.read!(css_path)
    @css_digest @css
                |> then(&:crypto.hash(:sha256, &1))
                |> Base.encode16(case: :lower)
                |> binary_part(0, 12)

    @external_resource cytoscape_path = Path.join(@static_path, "cytoscape.esm.min.mjs")
    @cytoscape File.read!(cytoscape_path)
    @cytoscape_digest @cytoscape
                      |> then(&:crypto.hash(:sha256, &1))
                      |> Base.encode16(case: :lower)
                      |> binary_part(0, 12)

    @external_resource phoenix_path = Application.app_dir(:phoenix, "priv/static/phoenix.mjs")
    @phoenix File.read!(phoenix_path)
    @phoenix_digest @phoenix
                    |> then(&:crypto.hash(:sha256, &1))
                    |> Base.encode16(case: :lower)
                    |> binary_part(0, 12)

    @external_resource live_view_path =
                         Application.app_dir(
                           :phoenix_live_view,
                           "priv/static/phoenix_live_view.esm.js"
                         )
    @live_view File.read!(live_view_path)
    @live_view_digest @live_view
                      |> then(&:crypto.hash(:sha256, &1))
                      |> Base.encode16(case: :lower)
                      |> binary_part(0, 12)

    @external_resource client_path = Path.join(@static_path, "beam_console.mjs")
    @client_template File.read!(client_path)
    @js @client_template
        |> String.replace("__PHOENIX_DIGEST__", @phoenix_digest)
        |> String.replace("__LIVE_VIEW_DIGEST__", @live_view_digest)
        |> String.replace("__CYTOSCAPE_DIGEST__", @cytoscape_digest)
    @js_digest @js
               |> then(&:crypto.hash(:sha256, &1))
               |> Base.encode16(case: :lower)
               |> binary_part(0, 12)

    @spec css_digest() :: String.t()
    @doc "Returns the digest embedded in the current BeamConsole stylesheet URL."
    def css_digest do
      @css_digest
    end

    @spec js_digest() :: String.t()
    @doc "Returns the digest embedded in the current BeamConsole client URL."
    def js_digest do
      @js_digest
    end

    @spec phoenix_digest() :: String.t()
    @doc "Returns the digest for the vendored Phoenix browser module."
    def phoenix_digest do
      @phoenix_digest
    end

    @spec live_view_digest() :: String.t()
    @doc "Returns the digest for the vendored Phoenix LiveView browser module."
    def live_view_digest do
      @live_view_digest
    end

    @spec cytoscape_digest() :: String.t()
    @doc "Returns the digest for the vendored Cytoscape graph module."
    def cytoscape_digest do
      @cytoscape_digest
    end

    @spec css(Plug.Conn.t(), map()) :: Plug.Conn.t()
    @doc "Serves the stylesheet when the requested digest matches the current asset."
    def css(%{params: %{"digest" => @css_digest}} = conn, _params) do
      send_asset(conn, "text/css", @css)
    end

    def css(conn, _params) do
      send_resp(conn, 404, "Not Found")
    end

    @spec js(Plug.Conn.t(), map()) :: Plug.Conn.t()
    @doc "Serves the BeamConsole browser client when its digest matches."
    def js(%{params: %{"digest" => @js_digest}} = conn, _params) do
      send_asset(conn, "text/javascript", @js)
    end

    def js(conn, _params) do
      send_resp(conn, 404, "Not Found")
    end

    @spec phoenix(Plug.Conn.t(), map()) :: Plug.Conn.t()
    @doc "Serves the vendored Phoenix browser module when its digest matches."
    def phoenix(%{params: %{"digest" => @phoenix_digest}} = conn, _params) do
      send_asset(conn, "text/javascript", @phoenix)
    end

    def phoenix(conn, _params) do
      send_resp(conn, 404, "Not Found")
    end

    @spec live_view(Plug.Conn.t(), map()) :: Plug.Conn.t()
    @doc "Serves the vendored LiveView browser module when its digest matches."
    def live_view(%{params: %{"digest" => @live_view_digest}} = conn, _params) do
      send_asset(conn, "text/javascript", @live_view)
    end

    def live_view(conn, _params) do
      send_resp(conn, 404, "Not Found")
    end

    @spec cytoscape(Plug.Conn.t(), map()) :: Plug.Conn.t()
    @doc "Serves the vendored Cytoscape module when its digest matches."
    def cytoscape(%{params: %{"digest" => @cytoscape_digest}} = conn, _params) do
      send_asset(conn, "text/javascript", @cytoscape)
    end

    def cytoscape(conn, _params) do
      send_resp(conn, 404, "Not Found")
    end

    # The content type and body are compile-time module attributes selected by
    # fixed controller actions; request data cannot reach either argument.
    # sobelow_skip ["XSS.ContentType", "XSS.SendResp"]
    defp send_asset(conn, content_type, body) do
      conn
      |> put_resp_content_type(content_type)
      |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
      |> put_private(:plug_skip_csrf_protection, true)
      |> send_resp(200, body)
    end
  end
end
