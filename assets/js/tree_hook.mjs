const BeamConsoleTree = {
  mounted() {
    this.branchStates = new Map(storedBranchStates());
    this.bindings = [];
    this.applyState();
    this.bindBranches();
  },
  updated() {
    this.unbindBranches();
    this.applyState();
    this.bindBranches();
  },
  destroyed() {
    this.unbindBranches();
    if (this.applyFrame) window.cancelAnimationFrame(this.applyFrame);
  },
  applyState() {
    this.applying = true;
    this.el.querySelectorAll("details[id]").forEach(branch => {
      if (this.branchStates.has(branch.id)) branch.open = this.branchStates.get(branch.id);
    });
    if (this.applyFrame) window.cancelAnimationFrame(this.applyFrame);
    this.applyFrame = window.requestAnimationFrame(() => { this.applying = false; });
  },
  bindBranches() {
    this.bindings = Array.from(this.el.querySelectorAll("details[id]"), branch => {
      const onToggle = () => {
        if (this.applying) return;
        this.branchStates.delete(branch.id);
        this.branchStates.set(branch.id, branch.open);
        persistBranchStates(this.branchStates);
      };
      branch.addEventListener("toggle", onToggle);
      return { branch, onToggle };
    });
  },
  unbindBranches() {
    this.bindings.forEach(({ branch, onToggle }) => branch.removeEventListener("toggle", onToggle));
    this.bindings = [];
  }
};
