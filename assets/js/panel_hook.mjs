const BeamConsolePanels = {
  mounted() {
    this.media = window.matchMedia("(max-width: 760px)");
    this.activePanel = null;
    this.returnFocus = null;
    this.togglePanel = event => {
      const toggle = event.target.closest("[data-beam-console-panel-toggle]");
      if (!toggle || !this.media.matches) return;
      const name = toggle.dataset.beamConsolePanelToggle;
      if (this.activePanel === name) {
        this.closePanels();
        return;
      }

      this.activePanel = name;
      this.returnFocus = toggle;
      this.syncPanels(true);
    };
    this.dismissPanel = event => {
      if (!event.target.closest("[data-beam-console-panel-dismiss]")) return;
      this.closePanels();
    };
    this.keydown = event => {
      if (event.key === "Escape" && this.activePanel) {
        this.closePanels();
      } else if (event.key === "Tab" && this.activePanel) {
        this.containFocus(event);
      }
    };
    this.breakpointChanged = () => {
      if (!this.media.matches) this.activePanel = null;
      this.syncPanels(false);
    };
    this.el.addEventListener("click", this.togglePanel);
    this.el.addEventListener("click", this.dismissPanel);
    window.addEventListener("keydown", this.keydown);
    this.media.addEventListener("change", this.breakpointChanged);
    this.syncPanels(false);
  },
  updated() {
    this.syncPanels(false);
  },
  destroyed() {
    this.el.removeEventListener("click", this.togglePanel);
    this.el.removeEventListener("click", this.dismissPanel);
    window.removeEventListener("keydown", this.keydown);
    this.media.removeEventListener("change", this.breakpointChanged);
  },
  closePanels() {
    const activeToggle = this.returnFocus || this.el.querySelector(
      `[data-beam-console-panel-toggle="${this.activePanel}"]`
    );
    this.activePanel = null;
    this.returnFocus = null;
    this.syncPanels(false);
    activeToggle?.focus();
  },
  containFocus(event) {
    const panel = this.el.querySelector(
      `[data-beam-console-panel="${this.activePanel}"]`
    );
    if (!panel) return;

    const focusable = Array.from(panel.querySelectorAll(
      "a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), " +
      "textarea:not([disabled]), [tabindex]:not([tabindex='-1'])"
    )).filter(element => !element.closest("details:not([open])"));

    if (!focusable.length) {
      event.preventDefault();
      panel.focus();
      return;
    }

    const first = focusable[0];
    const last = focusable.at(-1);

    if (event.shiftKey && [panel, first].includes(document.activeElement)) {
      event.preventDefault();
      last.focus();
    } else if (
      !event.shiftKey &&
      (document.activeElement === last || !panel.contains(document.activeElement))
    ) {
      event.preventDefault();
      first.focus();
    }
  },
  syncPanels(focusPanel) {
    const mobile = this.media.matches;
    const modalOpen = mobile && Boolean(this.activePanel);

    this.el.querySelectorAll("[data-beam-console-panel]").forEach(panel => {
      const active = mobile && panel.dataset.beamConsolePanel === this.activePanel;
      panel.classList.toggle("is-mobile-open", active);
      panel.inert = mobile && !active;

      if (panel.inert) panel.setAttribute("inert", "");
      else panel.removeAttribute("inert");

      if (mobile) panel.setAttribute("aria-hidden", String(!active));
      else panel.removeAttribute("aria-hidden");

      if (active) {
        panel.setAttribute("role", "dialog");
        panel.setAttribute("aria-modal", "true");
      } else {
        panel.removeAttribute("role");
        panel.removeAttribute("aria-modal");
      }

      if (active && focusPanel) panel.focus();
    });

    Array.from(this.el.children).forEach(child => {
      const background = !child.matches(
        "[data-beam-console-panel], [data-beam-console-panel-dismiss]"
      );
      if (!background) return;

      child.inert = modalOpen;
      if (child.inert) child.setAttribute("inert", "");
      else child.removeAttribute("inert");
    });

    this.el.querySelectorAll("[data-beam-console-panel-toggle]").forEach(toggle => {
      const active = mobile && toggle.dataset.beamConsolePanelToggle === this.activePanel;
      toggle.setAttribute("aria-expanded", String(active));
    });

    this.el.classList.toggle("has-mobile-panel", modalOpen);
  }
};

export { BeamConsolePanels };
