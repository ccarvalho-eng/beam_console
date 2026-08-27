const graphStyle = element => {
  const computed = getComputedStyle(element);
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

  return [
    { selector: "node", style: { width: 132, height: 32, shape: "round-rectangle", "background-color": palette.surface, "border-color": palette.borderStrong, "border-width": 1, label: "data(label)", color: palette.text, "font-size": 10, "font-weight": 500, "text-wrap": "ellipsis", "text-max-width": 112, "text-valign": "center", "text-halign": "center" } },
    { selector: "node[kind = 'supervisor']", style: { "background-color": palette.accentSoft, "border-color": palette.accentBorder, "border-width": 1.5, "font-weight": 650 } },
    { selector: "node[kind = 'application']", style: { width: 144, height: 36, "background-color": palette.surfaceRaised, "border-color": palette.borderStrong, "font-weight": 650 } },
    { selector: "node[kind = 'node']", style: { width: 156, height: 38, "background-color": palette.text, "border-color": palette.text, color: palette.surface, "font-weight": 700 } },
    { selector: "node:selected", style: { "background-color": palette.accent, "border-color": palette.accent, color: palette.surface, "border-width": 2 } },
    { selector: "edge", style: { width: 1.25, "line-color": palette.borderStrong, "target-arrow-color": palette.borderStrong, "target-arrow-shape": "triangle", "arrow-scale": 0.7, "curve-style": "taxi", "taxi-direction": "downward", "taxi-turn": 18 } },
    { selector: "edge[kind = 'contains'], edge[kind = 'owns']", style: { "line-style": "dashed", "line-color": palette.muted, "target-arrow-color": palette.muted } },
    { selector: "edge[kind = 'links']", style: { "line-style": "dotted", "target-arrow-shape": "none", "line-color": palette.accent, opacity: 0.72 } },
    { selector: "edge[kind = 'monitors']", style: { "line-style": "dashed", "line-color": palette.accent, "target-arrow-color": palette.accent, opacity: 0.8 } }
  ];
};
