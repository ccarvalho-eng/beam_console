if Code.ensure_loaded?(Phoenix.Controller) do
  defmodule BeamConsoleWeb.Assets do
    @moduledoc false

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

    @js """
    import { Socket, LongPoll } from "../phoenix/#{@phoenix_digest}";
    import { LiveSocket } from "../live-view/#{@live_view_digest}";
    import cytoscape from "../cytoscape/#{@cytoscape_digest}";

    const script = document.querySelector("script[data-beam-console-client]");
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content");
    const livePath = script?.dataset.livePath || "/live";
    const transport = script?.dataset.liveTransport || "websocket";

    const BeamConsoleGraph = {
      mounted() {
        this.sequence = 0;
        this.focus = null;
        this.topologySignature = null;
        const computed = getComputedStyle(this.el);
        const token = name => computed.getPropertyValue(name).trim();
        const palette = {
          surface: token("--bc-surface") || "#ffffff",
          surfaceMuted: token("--bc-surface-muted") || "#fafafa",
          surfaceRaised: token("--bc-surface-raised") || "#f4f4f5",
          border: token("--bc-border") || "#e4e4e7",
          borderStrong: token("--bc-border-strong") || "#d4d4d8",
          text: token("--bc-text") || "#27272a",
          muted: token("--bc-muted") || "#71717a",
          accent: token("--bc-accent") || "#7c3aed",
          accentSoft: token("--bc-accent-soft") || "#f5f3ff",
          accentBorder: token("--bc-accent-border") || "#c4b5fd"
        };
        this.cy = cytoscape({
          container: this.el,
          elements: [],
          style: [
            { selector: "node", style: { width: 132, height: 32, shape: "round-rectangle", "background-color": palette.surface, "border-color": palette.borderStrong, "border-width": 1, label: "data(label)", color: palette.text, "font-size": 10, "font-weight": 500, "text-wrap": "ellipsis", "text-max-width": 112, "text-valign": "center", "text-halign": "center" } },
            { selector: "node[kind = 'supervisor']", style: { "background-color": palette.accentSoft, "border-color": palette.accentBorder, "border-width": 1.5, "font-weight": 650 } },
            { selector: "node[kind = 'application']", style: { width: 144, height: 36, "background-color": palette.surfaceRaised, "border-color": palette.borderStrong, "font-weight": 650 } },
            { selector: "node[kind = 'node']", style: { width: 156, height: 38, "background-color": palette.text, "border-color": palette.text, color: palette.surface, "font-weight": 700 } },
            { selector: "node:selected", style: { "background-color": palette.accent, "border-color": palette.accent, color: palette.surface, "border-width": 2 } },
            { selector: "edge", style: { width: 1.25, "line-color": palette.borderStrong, "target-arrow-color": palette.borderStrong, "target-arrow-shape": "triangle", "arrow-scale": 0.7, "curve-style": "taxi", "taxi-direction": "downward", "taxi-turn": 18 } },
            { selector: "edge[kind = 'contains'], edge[kind = 'owns']", style: { "line-style": "dashed", "line-color": palette.muted, "target-arrow-color": palette.muted } }
          ]
        });

        this.cy.on("tap", "node", event => this.pushEvent("select_entity", { id: event.target.id() }));
        this.handleEvent("beam_console_graph", payload => this.replaceGraph(payload));
        this.pushEvent("request_graph", {});
      },
      destroyed() {
        if (this.cy) this.cy.destroy();
      },
      replaceGraph(payload) {
        if (!this.cy || !payload || payload.sequence < this.sequence) return;
        const elements = payload.elements || [];
        const topologySignature = JSON.stringify(elements.map(element => {
          const data = element.data || {};
          return [data.id, data.source || null, data.target || null, data.kind || null];
        }));
        const focusChanged = this.focus !== payload.focus;

        if (topologySignature === this.topologySignature) {
          this.updateElementData(elements);
          this.updateSelection(payload.selected);
          this.sequence = payload.sequence;
          this.focus = payload.focus;
          return;
        }

        if (this.sequence > 0 && !focusChanged) {
          this.patchTopology(elements);
        } else {
          this.cy.elements().remove();
          this.cy.add(elements);
          this.cy.layout({ name: "breadthfirst", directed: true, animate: false, fit: false, padding: 44, spacingFactor: 1.1 }).run();
          this.cy.fit(undefined, 36);
        }

        this.updateSelection(payload.selected);
        this.sequence = payload.sequence;
        this.focus = payload.focus;
        this.topologySignature = topologySignature;
      },
      updateElementData(elements) {
        elements.forEach(element => {
          const existing = this.cy.$id(element.data.id);
          if (existing.length) existing.data(element.data);
        });
      },
      updateSelection(selected) {
        this.cy.nodes().unselect();
        if (selected) this.cy.$id(selected).select();
      },
      patchTopology(elements) {
        const incomingIds = new Set(elements.map(element => element.data.id));
        this.cy.elements().filter(element => !incomingIds.has(element.id())).remove();

        const nodes = elements.filter(element => !element.data.source);
        const edges = elements.filter(element => element.data.source);
        const newNodeIds = [];

        nodes.forEach(element => {
          const existing = this.cy.$id(element.data.id);

          if (existing.length) {
            existing.data(element.data);
          } else {
            this.cy.add(element);
            newNodeIds.push(element.data.id);
          }
        });

        edges.forEach(element => {
          const existing = this.cy.$id(element.data.id);
          if (existing.length) existing.data(element.data);
          else this.cy.add(element);
        });

        newNodeIds.forEach((nodeId, index) => {
          const node = this.cy.$id(nodeId);
          const incoming = edges.find(edge => edge.data.target === nodeId);
          const parent = incoming && this.cy.$id(incoming.data.source);

          if (parent && parent.length) {
            const position = parent.position();
            const offset = (index % 5 - 2) * 148;
            node.position({ x: position.x + offset, y: position.y + 94 });
          } else {
            const extent = this.cy.extent();
            node.position({ x: (extent.x1 + extent.x2) / 2, y: (extent.y1 + extent.y2) / 2 });
          }
        });
      }
    };

    const socketOptions = { params: { _csrf_token: csrfToken }, hooks: { BeamConsoleGraph } };
    if (transport === "longpoll") socketOptions.transport = LongPoll;
    const liveSocket = new LiveSocket(livePath, Socket, socketOptions);
    liveSocket.connect();
    window.beamConsoleLiveSocket = liveSocket;
    """
    @js_digest @js
               |> then(&:crypto.hash(:sha256, &1))
               |> Base.encode16(case: :lower)
               |> binary_part(0, 12)

    @spec css_digest() :: String.t()
    def css_digest do
      @css_digest
    end

    @spec js_digest() :: String.t()
    def js_digest do
      @js_digest
    end

    @spec phoenix_digest() :: String.t()
    def phoenix_digest do
      @phoenix_digest
    end

    @spec live_view_digest() :: String.t()
    def live_view_digest do
      @live_view_digest
    end

    @spec cytoscape_digest() :: String.t()
    def cytoscape_digest do
      @cytoscape_digest
    end

    def css(%{params: %{"digest" => @css_digest}} = conn, _params) do
      send_asset(conn, "text/css", @css)
    end

    def css(conn, _params) do
      send_resp(conn, 404, "Not Found")
    end

    def js(%{params: %{"digest" => @js_digest}} = conn, _params) do
      send_asset(conn, "text/javascript", @js)
    end

    def js(conn, _params) do
      send_resp(conn, 404, "Not Found")
    end

    def phoenix(%{params: %{"digest" => @phoenix_digest}} = conn, _params) do
      send_asset(conn, "text/javascript", @phoenix)
    end

    def phoenix(conn, _params) do
      send_resp(conn, 404, "Not Found")
    end

    def live_view(%{params: %{"digest" => @live_view_digest}} = conn, _params) do
      send_asset(conn, "text/javascript", @live_view)
    end

    def live_view(conn, _params) do
      send_resp(conn, 404, "Not Found")
    end

    def cytoscape(%{params: %{"digest" => @cytoscape_digest}} = conn, _params) do
      send_asset(conn, "text/javascript", @cytoscape)
    end

    def cytoscape(conn, _params) do
      send_resp(conn, 404, "Not Found")
    end

    defp send_asset(conn, content_type, body) do
      conn
      |> put_resp_content_type(content_type)
      |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
      |> put_private(:plug_skip_csrf_protection, true)
      |> send_resp(200, body)
    end
  end
end
