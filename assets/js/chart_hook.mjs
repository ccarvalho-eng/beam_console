const chartColors = element => {
  const computed = getComputedStyle(element);
  const token = name => computed.getPropertyValue(name).trim();
  return [
    token("--bc-accent") || "#7c3aed",
    token("--bc-chart-two") || "#0891b2",
    token("--bc-chart-three") || "#ca8a04",
    token("--bc-chart-four") || "#dc2626",
    token("--bc-chart-five") || "#16a34a",
    token("--bc-muted") || "#71717a"
  ];
};

const svgElement = name => document.createElementNS("http://www.w3.org/2000/svg", name);

const formatChartValue = (value, unit) => {
  if (!Number.isFinite(value)) return "—";
  if (unit === "bytes") {
    const absolute = Math.abs(value);
    if (absolute >= 1048576) return `${(value / 1048576).toFixed(1)} MB`;
    if (absolute >= 1024) return `${(value / 1024).toFixed(1)} KB`;
    return `${Math.round(value)} B`;
  }
  if (unit === "reductions/s") return `${Math.round(value).toLocaleString()} /s`;
  if (unit === "ms") return `${Math.round(value)} ms`;
  return Number.isInteger(value) ? value.toLocaleString() : value.toFixed(1);
};

const renderChart = (root, chart) => {
  const card = root.querySelector(`[data-chart-id="${CSS.escape(chart.id)}"]`);
  if (!card) return;
  const svg = card.querySelector("svg");
  const title = card.querySelector("[data-chart-title]");
  const current = card.querySelector("[data-chart-value]");
  const legend = card.querySelector("[data-chart-legend]");
  const series = Array.isArray(chart.series) ? chart.series : [];
  const points = series.flatMap(item => Array.isArray(item.points) ? item.points : []);
  title.textContent = chart.title || "History";
  current.textContent = chartHeadline(series, chart.unit, formatChartValue);
  svg.setAttribute("aria-label", chartAriaLabel(chart.title));
  svg.replaceChildren();
  legend.replaceChildren();
  if (!points.length) return;

  const width = 640;
  const height = 180;
  const inset = 12;
  const times = points.map(point => Number(point[0]));
  const values = points.map(point => Number(point[1])).filter(Number.isFinite);
  const minTime = Math.min(...times);
  const maxTime = Math.max(...times);
  let minValue = Math.min(...values);
  let maxValue = Math.max(...values);
  if (minValue === maxValue) {
    const padding = Math.max(Math.abs(minValue) * 0.08, 1);
    minValue -= padding;
    maxValue += padding;
  }
  const x = value => inset + ((value - minTime) / Math.max(maxTime - minTime, 1)) * (width - inset * 2);
  const y = value => height - inset - ((value - minValue) / (maxValue - minValue)) * (height - inset * 2);
  const colors = chartColors(root);

  [0.25, 0.5, 0.75].forEach(ratio => {
    const line = svgElement("line");
    line.setAttribute("x1", inset);
    line.setAttribute("x2", width - inset);
    line.setAttribute("y1", height * ratio);
    line.setAttribute("y2", height * ratio);
    line.setAttribute("class", "beam-console-chart-gridline");
    svg.append(line);
  });

  series.forEach((item, index) => {
    const color = colors[index % colors.length];
    const chunks = [];
    (item.points || []).forEach(point => {
      const previous = chunks.at(-1);
      if (!previous || previous.segment !== point[2]) chunks.push({ segment: point[2], points: [point] });
      else previous.points.push(point);
    });
    chunks.forEach(chunk => {
      const polyline = svgElement("polyline");
      polyline.setAttribute("points", chunk.points.map(point => `${x(point[0])},${y(point[1])}`).join(" "));
      polyline.setAttribute("fill", "none");
      polyline.setAttribute("stroke", color);
      polyline.setAttribute("class", "beam-console-chart-line");
      svg.append(polyline);
    });
    const key = document.createElement("span");
    const swatch = document.createElement("i");
    swatch.style.backgroundColor = color;
    key.append(swatch, document.createTextNode(item.label || String(item.key)));
    legend.append(key);
  });
};

const BeamConsoleCharts = {
  mounted() {
    this.epoch = null;
    this.revision = -1;
    this.payload = null;
    this.themeChanged = () => this.render();
    window.addEventListener("beam-console-theme-change", this.themeChanged);
    this.handleEvent("beam_console_charts", payload => {
      if (!payload) return;

      const decision = revisionDecision(
        this.epoch,
        this.revision,
        payload.epoch ?? null,
        payload.revision
      );
      if (!decision.accept) return;

      if (decision.reset) {
        this.revision = -1;
        this.payload = null;
      }

      this.epoch = payload.epoch ?? null;
      this.revision = payload.revision;
      this.payload = payload;
      this.render();
    });
  },
  destroyed() {
    window.removeEventListener("beam-console-theme-change", this.themeChanged);
  },
  render() {
    (this.payload?.charts || []).forEach(chart => renderChart(this.el, chart));
  }
};
