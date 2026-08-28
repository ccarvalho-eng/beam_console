const BeamConsolePanels = {
  mounted() {
    this.media = window.matchMedia("(max-width: 760px)");
    this.activePanel = null;
    this.returnFocus = null;
    this.focusStorageKey = this.el.dataset.beamConsoleFocusKey;
    this.focusActive = this.readFocusPreference();
    this.focusReturn = null;
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
    this.toggleFocus = event => {
      const toggle = event.target.closest("[data-beam-console-focus-toggle]");
      if (!toggle) return;

      this.focusReturn = this.el.querySelector("#beam-console-focus-mode");
      this.setFocusMode(!this.focusActive, true, true);
    };
    this.keydown = event => {
      if (event.key === "Escape" && this.activePanel) {
        event.preventDefault();
        this.closePanels();
      } else if (event.key === "Tab" && this.activePanel) {
        this.containFocus(event);
      } else {
        const action = focusShortcutAction(event, this.focusActive);
        if (!action) return;

        event.preventDefault();
        this.focusReturn = this.el.querySelector("#beam-console-focus-mode");
        this.setFocusMode(action === "toggle" ? !this.focusActive : false, true, true);
      }
    };
    this.breakpointChanged = () => {
      if (!this.media.matches) this.activePanel = null;
      this.syncPanels(false);
    };
    this.storageChanged = event => {
      if (event.key !== this.focusStorageKey) return;
      const active = this.readFocusPreference();
      this.setFocusMode(active, false, this.focusTransitionHidesActiveControl(active), true);
    };
    this.el.addEventListener("click", this.togglePanel);
    this.el.addEventListener("click", this.dismissPanel);
    this.el.addEventListener("click", this.toggleFocus);
    window.addEventListener("keydown", this.keydown);
    window.addEventListener("storage", this.storageChanged);
    this.media.addEventListener("change", this.breakpointChanged);
    this.setFocusMode(this.focusActive, false, false);
    this.syncPanels(false);
  },
  updated() {
    this.syncFocusMode(false);
    this.syncPanels(false);
  },
  destroyed() {
    this.el.removeEventListener("click", this.togglePanel);
    this.el.removeEventListener("click", this.dismissPanel);
    this.el.removeEventListener("click", this.toggleFocus);
    window.removeEventListener("keydown", this.keydown);
    window.removeEventListener("storage", this.storageChanged);
    this.media.removeEventListener("change", this.breakpointChanged);
  },
  setFocusMode(active, persist, moveFocus, announce = persist) {
    this.focusActive = Boolean(active);
    document.documentElement.dataset.beamConsoleFocus = String(this.focusActive);

    if (persist) this.writeFocusPreference(this.focusActive);
    if (this.focusActive && this.activePanel) this.closePanels();
    this.syncFocusMode(moveFocus, announce);
    this.scheduleWorkspaceResize();
  },
  syncFocusMode(moveFocus, announce = false) {
    this.el.querySelectorAll("[data-beam-console-focus-toggle]").forEach(toggle => {
      toggle.setAttribute("aria-pressed", String(this.focusActive));
    });

    const announcement = this.el.querySelector("#beam-console-focus-announcement");
    if (announcement && announce) {
      announcement.textContent = this.focusActive ? "Focus mode enabled" : "Focus mode disabled";
    }

    if (!moveFocus) return;

    const target = this.focusActive
      ? this.el.querySelector("#beam-console-focus-exit")
      : this.focusReturn || this.el.querySelector("#beam-console-focus-mode");
    target?.focus();
  },
  focusTransitionHidesActiveControl(active) {
    const current = document.activeElement;
    if (!current || !this.el.contains(current)) return false;

    if (active && this.activePanel) return true;

    if (!active) {
      return Boolean(current.closest(".beam-console-focus-exit, .beam-console-focus-inspector"));
    }

    const selected = this.el.dataset.beamConsoleHasSelection === "true";
    const hiddenChrome = current.closest(
      ".beam-console-header, .beam-console-sidebar, " +
      ".beam-console-runtime-summary, .beam-console-recorder-summary"
    );
    const hiddenInspector = !selected && current.closest(".beam-console-inspector");
    return Boolean(hiddenChrome || hiddenInspector);
  },
  scheduleWorkspaceResize() {
    const schedule = window.requestAnimationFrame || (callback => callback());
    schedule(() => window.dispatchEvent(new Event("resize")));
  },
  readFocusPreference() {
    return readStoredBoolean(window, this.focusStorageKey);
  },
  writeFocusPreference(active) {
    writeStoredBoolean(window, this.focusStorageKey, active);
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
