const BeamConsoleGraph = {
  mounted() {
    this.epoch = null;
    this.sequence = 0;
    this.focus = null;
    this.topologySignature = null;
    this.fitPending = false;
    this.fitFrame = null;
    this.themeChanged = () => this.cy?.style(graphStyle(this.el));
    window.addEventListener("beam-console-theme-change", this.themeChanged);
    this.cy = cytoscape({
      container: this.el,
      elements: [],
      style: graphStyle(this.el)
    });

    this.cy.on("tap", "node", event => this.pushEvent("select_entity", { id: event.target.id() }));
    this.resizeObserver = new ResizeObserver(() => {
      this.cy?.resize();
      if (this.fitPending) this.scheduleFit();
    });
    this.resizeObserver.observe(this.el);
    this.handleEvent("beam_console_graph", payload => this.replaceGraph(payload));
    this.pushEvent("request_graph", {});
  },
  destroyed() {
    window.removeEventListener("beam-console-theme-change", this.themeChanged);
    this.resizeObserver?.disconnect();
    if (this.fitFrame) window.cancelAnimationFrame(this.fitFrame);
    if (this.cy) this.cy.destroy();
  },
  replaceGraph(payload) {
    if (!this.cy || !payload) return;

    const decision = revisionDecision(
      this.epoch,
      this.sequence,
      payload.epoch ?? null,
      payload.sequence
    );
    if (!decision.accept) return;

    if (decision.reset) {
      this.sequence = 0;
      this.focus = null;
      this.topologySignature = null;
    }

    const elements = payload.elements || [];
    const omitted = document.querySelector("[data-graph-omitted]");
    if (omitted) {
      omitted.textContent = graphOmissionLabel(
        payload.omitted_nodes || 0,
        payload.omitted_relationships || 0
      );
    }
    const topologySignature = JSON.stringify(elements.map(element => {
      const data = element.data || {};
      return [data.id, data.source || null, data.target || null, data.kind || null];
    }));
    const focusChanged = this.focus !== payload.focus;

    if (topologySignature === this.topologySignature) {
      this.updateElementData(elements);
      this.updateSelection(payload.selected);
      this.sequence = payload.sequence;
      this.epoch = payload.epoch ?? null;
      this.focus = payload.focus;
      return;
    }

    if (this.sequence > 0 && !focusChanged && !this.requiresRelayout(elements)) {
      this.patchTopology(elements);
    } else {
      this.layoutGraph(elements);
    }

    this.updateSelection(payload.selected);
    this.sequence = payload.sequence;
    this.epoch = payload.epoch ?? null;
    this.focus = payload.focus;
    this.topologySignature = topologySignature;
  },
  requiresRelayout(elements) {
    const incoming = new Set(elements.filter(element => !element.data.source).map(element => element.data.id));
    const current = new Set(this.cy.nodes().map(node => node.id()));

    const changed = [...incoming].filter(id => !current.has(id)).length +
      [...current].filter(id => !incoming.has(id)).length;
    const baseline = Math.max(incoming.size, current.size, 1);
    return changed >= 8 && changed / baseline >= 0.25;
  },
  layoutGraph(elements) {
    this.cy.elements().remove();
    this.cy.add(elements);
    this.cy.resize();
    this.cy.layout({ name: "breadthfirst", directed: true, animate: false, fit: false, padding: 44, spacingFactor: 1.1 }).run();
    this.requestFit();
  },
  requestFit() {
    this.fitPending = true;
    this.fitState = { width: 0, height: 0, stableFrames: 0 };
    this.scheduleFit();
  },
  scheduleFit() {
    if (!this.fitPending || this.fitFrame) return;
    this.fitFrame = window.requestAnimationFrame(() => {
      this.fitFrame = null;
      const width = Math.round(this.el.clientWidth);
      const height = Math.round(this.el.clientHeight);
      if (width < 2 || height < 2) return;

      const unchanged = width === this.fitState.width && height === this.fitState.height;
      this.fitState = {
        width,
        height,
        stableFrames: unchanged ? this.fitState.stableFrames + 1 : 0
      };

      if (this.fitState.stableFrames < 2) {
        this.scheduleFit();
        return;
      }

      this.cy.resize();
      this.cy.fit(undefined, 36);
      this.cy.zoom(Math.max(this.cy.zoom(), 0.45));
      this.cy.center();
      this.fitPending = false;
    });
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
    const existingNodeIds = new Set(this.cy.nodes().map(node => node.id()));
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

    const placements = newNodePlacements(edges, newNodeIds, existingNodeIds);

    placements.forEach(({ nodeId, anchorId, offset }) => {
      const node = this.cy.$id(nodeId);
      const parent = anchorId && this.cy.$id(anchorId);

      if (parent && parent.length) {
        const position = parent.position();
        node.position({ x: position.x + offset.x, y: position.y + offset.y });
      } else {
        const extent = this.cy.extent();
        node.position({
          x: (extent.x1 + extent.x2) / 2 + offset.x,
          y: (extent.y1 + extent.y2) / 2 + offset.y
        });
      }
    });
  }
};
