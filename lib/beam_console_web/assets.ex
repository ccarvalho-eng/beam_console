if Code.ensure_loaded?(Phoenix.Controller) and Code.ensure_loaded?(Phoenix.LiveView) do
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

    @external_resource support_path = Path.join(@static_path, "beam_console_support.mjs")
    @support File.read!(support_path)
    @support_digest @support
                    |> then(&:crypto.hash(:sha256, &1))
                    |> Base.encode16(case: :lower)
                    |> binary_part(0, 12)

    @external_resource theme_path = Path.join(@static_path, "beam_console_theme.js")
    @theme File.read!(theme_path)
    @theme_digest @theme
                  |> then(&:crypto.hash(:sha256, &1))
                  |> Base.encode16(case: :lower)
                  |> binary_part(0, 12)

    @external_resource client_path = Path.join(@static_path, "beam_console.mjs")
    @client_template File.read!(client_path)
    @js @client_template
        |> String.replace("__PHOENIX_DIGEST__", @phoenix_digest)
        |> String.replace("__LIVE_VIEW_DIGEST__", @live_view_digest)
        |> String.replace("__CYTOSCAPE_DIGEST__", @cytoscape_digest)
        |> String.replace("__SUPPORT_DIGEST__", @support_digest)
    @js_digest @js
               |> then(&:crypto.hash(:sha256, &1))
               |> Base.encode16(case: :lower)
               |> binary_part(0, 12)

    @doc "Returns the digest embedded in the current BeamConsole stylesheet URL."
    @spec css_digest() :: String.t()
    def css_digest do
      @css_digest
    end

    @doc "Returns the digest embedded in the current BeamConsole client URL."
    @spec js_digest() :: String.t()
    def js_digest do
      @js_digest
    end

    @doc "Returns the digest for the vendored Phoenix browser module."
    @spec phoenix_digest() :: String.t()
    def phoenix_digest do
      @phoenix_digest
    end

    @doc "Returns the digest for the vendored Phoenix LiveView browser module."
    @spec live_view_digest() :: String.t()
    def live_view_digest do
      @live_view_digest
    end

    @doc "Returns the digest for the vendored Cytoscape graph module."
    @spec cytoscape_digest() :: String.t()
    def cytoscape_digest do
      @cytoscape_digest
    end

    @doc "Returns the digest for BeamConsole's browser support module."
    @spec support_digest() :: String.t()
    def support_digest do
      @support_digest
    end

    @doc "Returns the digest for BeamConsole's first-paint theme bootstrap."
    @spec theme_digest() :: String.t()
    def theme_digest do
      @theme_digest
    end

    @doc "Serves the stylesheet when the requested digest matches the current asset."
    @spec css(Plug.Conn.t(), map()) :: Plug.Conn.t()
    def css(%{params: %{"digest" => @css_digest}} = conn, _params) do
      send_asset(conn, "text/css", @css)
    end

    def css(conn, _params) do
      send_resp(conn, 404, "Not Found")
    end

    @doc "Serves the BeamConsole browser client when its digest matches."
    @spec js(Plug.Conn.t(), map()) :: Plug.Conn.t()
    def js(%{params: %{"digest" => @js_digest}} = conn, _params) do
      send_asset(conn, "text/javascript", @js)
    end

    def js(conn, _params) do
      send_resp(conn, 404, "Not Found")
    end

    @doc "Serves the vendored Phoenix browser module when its digest matches."
    @spec phoenix(Plug.Conn.t(), map()) :: Plug.Conn.t()
    def phoenix(%{params: %{"digest" => @phoenix_digest}} = conn, _params) do
      send_asset(conn, "text/javascript", @phoenix)
    end

    def phoenix(conn, _params) do
      send_resp(conn, 404, "Not Found")
    end

    @doc "Serves the vendored LiveView browser module when its digest matches."
    @spec live_view(Plug.Conn.t(), map()) :: Plug.Conn.t()
    def live_view(%{params: %{"digest" => @live_view_digest}} = conn, _params) do
      send_asset(conn, "text/javascript", @live_view)
    end

    def live_view(conn, _params) do
      send_resp(conn, 404, "Not Found")
    end

    @doc "Serves the vendored Cytoscape module when its digest matches."
    @spec cytoscape(Plug.Conn.t(), map()) :: Plug.Conn.t()
    def cytoscape(%{params: %{"digest" => @cytoscape_digest}} = conn, _params) do
      send_asset(conn, "text/javascript", @cytoscape)
    end

    def cytoscape(conn, _params) do
      send_resp(conn, 404, "Not Found")
    end

    @doc "Serves BeamConsole's browser support module when its digest matches."
    @spec support(Plug.Conn.t(), map()) :: Plug.Conn.t()
    def support(%{params: %{"digest" => @support_digest}} = conn, _params) do
      send_asset(conn, "text/javascript", @support)
    end

    def support(conn, _params) do
      send_resp(conn, 404, "Not Found")
    end

    @doc "Serves BeamConsole's first-paint theme bootstrap when its digest matches."
    @spec theme(Plug.Conn.t(), map()) :: Plug.Conn.t()
    def theme(%{params: %{"digest" => @theme_digest}} = conn, _params) do
      send_asset(conn, "text/javascript", @theme)
    end

    def theme(conn, _params) do
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
