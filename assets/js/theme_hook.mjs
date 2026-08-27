applyTheme(preferredTheme());

const BeamConsoleTheme = {
  mounted() {
    this.theme = preferredTheme();
    this.selectTheme = event => {
      const button = event.target instanceof Element
        ? event.target.closest("[data-beam-console-theme]")
        : null;
      const theme = button?.dataset.beamConsoleTheme;
      if (!themeModes.has(theme)) return;
      persistTheme(theme);
      this.apply(theme);
    };
    this.systemChanged = () => {
      if (this.theme === "system") this.apply("system");
    };
    this.storageChanged = event => {
      if (event.key === themeStorageKey) this.apply(preferredTheme());
    };
    this.el.addEventListener("click", this.selectTheme);
    systemThemeQuery.addEventListener("change", this.systemChanged);
    window.addEventListener("storage", this.storageChanged);
    this.apply(this.theme);
  },
  updated() {
    this.apply(this.theme);
  },
  destroyed() {
    this.el.removeEventListener("click", this.selectTheme);
    systemThemeQuery.removeEventListener("change", this.systemChanged);
    window.removeEventListener("storage", this.storageChanged);
  },
  apply(theme) {
    this.theme = themeModes.has(theme) ? theme : "system";
    applyTheme(this.theme);
    this.el.querySelectorAll("[data-beam-console-theme]").forEach(button => {
      const active = button.dataset.beamConsoleTheme === this.theme;
      button.classList.toggle("is-active", active);
      button.setAttribute("aria-pressed", String(active));
    });
  }
};
