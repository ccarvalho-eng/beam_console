import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import { BeamConsolePanels } from "../js/panel_hook.mjs";

import {
  anchoredNodeOffset,
  chartAriaLabel,
  chartDomain,
  chartHeadline,
  formatChartValue,
  graphUpdateMode,
  graphOmissionLabel,
  newNodePlacements,
  readStoredBranchStates,
  readStoredTheme,
  writeStoredBranchStates,
  writeStoredTheme,
  revisionDecision
} from "../js/support.mjs";

const storage = entries => {
  const values = new Map(Object.entries(entries));

  return {
    getItem: key => values.get(key) ?? null,
    removeItem: key => values.delete(key),
    setItem: (key, value) => values.set(key, value),
    values
  };
};

test("theme preference follows the Phoenix storage protocol", () => {
  const localStorage = storage({ "phx:theme": "dark" });
  const storageOwner = { localStorage };
  const themes = new Set(["system", "light", "dark"]);

  assert.equal(readStoredTheme(storageOwner, "phx:theme", themes), "dark");

  writeStoredTheme(storageOwner, "phx:theme", "system");
  assert.equal(localStorage.getItem("phx:theme"), null);

  localStorage.setItem("phx:theme", "unsupported");
  assert.equal(readStoredTheme(storageOwner, "phx:theme", themes), null);
});

test("restricted storage getters cannot abort client startup", () => {
  const storageOwner = {
    get localStorage() {
      throw new DOMException("Storage is unavailable", "SecurityError");
    }
  };

  assert.equal(readStoredTheme(storageOwner, "phx:theme", new Set(["dark"])), null);
  assert.deepEqual(readStoredBranchStates(storageOwner, "tree"), []);
  assert.doesNotThrow(() => writeStoredTheme(storageOwner, "phx:theme", "dark"));
  assert.doesNotThrow(() => writeStoredBranchStates(storageOwner, "tree", new Map()));
});

test("tree disclosure state is validated, bounded, and scoped by key", () => {
  const states = Array.from({ length: 205 }, (_entry, index) => [`branch-${index}`, index % 2 === 0]);
  const localStorage = storage({});

  writeStoredBranchStates(
    { localStorage },
    "beam-console:tree:closed:/admin/beam",
    states
  );

  const restored = readStoredBranchStates(
    { localStorage },
    "beam-console:tree:closed:/admin/beam"
  );

  assert.equal(restored.length, 200);
  assert.deepEqual(restored[0], ["branch-5", false]);
  assert.deepEqual(
    readStoredBranchStates(
      { localStorage },
      "beam-console:tree:closed:/another-mount"
    ),
    []
  );
});

test("chart headline distinguishes a value from multiple series", () => {
  const format = (value, unit) => `${value} ${unit}`;

  assert.equal(chartHeadline([], "ms", format), "No data");
  assert.equal(
    chartHeadline([{ points: [[1, 42, 0]] }], "ms", format),
    "42 ms"
  );
  assert.equal(
    chartHeadline(
      [{ points: [[1, 1, 0]] }, { points: [[1, 2, 0]] }],
      "bytes",
      format
    ),
    "2 series"
  );
});

test("chart values preserve percentage units", () => {
  assert.equal(formatChartValue(11.77, "%"), "11.8%");
});

test("chart domains honor meaningful fixed bounds", () => {
  assert.deepEqual(chartDomain([11.77, 11.78], 0, 100), [0, 100]);
  assert.deepEqual(chartDomain([11, 13], undefined, undefined), [11, 13]);
  assert.deepEqual(chartDomain([12, 12.5], undefined, undefined, [10, 14]), [11, 13.5]);
  assert.deepEqual(chartDomain([9, 15], undefined, undefined, [10, 14]), [9, 15]);
});

test("chart domains recover once after an outlier without rescaling every sample", () => {
  const recovered = chartDomain([40, 60], undefined, undefined, [0, 100]);

  assert.deepEqual(recovered, [38, 62]);
  assert.deepEqual(chartDomain([40, 60], undefined, undefined, recovered), recovered);
});

test("ordinary topology churn patches positions until focus changes", () => {
  assert.equal(graphUpdateMode(12, false), "patch");
  assert.equal(graphUpdateMode(12, true), "layout");
  assert.equal(graphUpdateMode(0, false), "layout");
});

test("collector epochs reset graph and chart revision guards", () => {
  assert.deepEqual(revisionDecision("epoch-a", 12, "epoch-a", 11), {
    reset: false,
    accept: false
  });

  assert.deepEqual(revisionDecision("epoch-a", 12, "epoch-b", 1), {
    reset: true,
    accept: true
  });
});

test("chart accessibility labels use each chart title", () => {
  assert.equal(chartAriaLabel("Run queue"), "Run queue history chart");
  assert.equal(chartAriaLabel(null), "History history chart");
});

test("graph omission labels distinguish processes from relationships", () => {
  assert.equal(graphOmissionLabel(0, 0), "");
  assert.equal(graphOmissionLabel(3, 0), "3 processes omitted");
  assert.equal(graphOmissionLabel(0, 5), "5 relationships omitted");
  assert.equal(graphOmissionLabel(3, 5), "3 processes · 5 relationships omitted");
});

test("new graph nodes anchor to either side of an existing relationship", () => {
  const edges = [
    { data: { id: "incoming", source: "parent", target: "child" } },
    { data: { id: "outgoing", source: "watcher", target: "selected" } }
  ];
  const placements = newNodePlacements(
    edges,
    ["child", "watcher", "missing"],
    new Set(["parent", "selected"])
  );

  assert.equal(placements[0].anchorId, "parent");
  assert.equal(placements[1].anchorId, "selected");
  assert.equal(placements[2].anchorId, null);
});

test("anchored graph positions remain unique beyond the first row", () => {
  const positions = Array.from({ length: 7 }, (_entry, index) => anchoredNodeOffset(index));
  const unique = new Set(positions.map(position => `${position.x}:${position.y}`));

  assert.deepEqual(positions[0], { x: 0, y: 94 });
  assert.deepEqual(positions.slice(0, 5).map(position => position.x), [0, -148, 148, -296, 296]);
  assert.equal(unique.size, positions.length);
  assert.notDeepEqual(positions[0], positions[5]);
});

test("new graph children use independent offsets for each existing parent", () => {
  const edges = [
    { data: { id: "edge-b", source: "parent-b", target: "child-b" } },
    { data: { id: "edge-a", source: "parent-a", target: "child-a" } }
  ];
  const placements = newNodePlacements(
    edges,
    ["child-b", "child-a"],
    new Set(["parent-a", "parent-b"])
  );

  assert.equal(placements[0].anchorId, "parent-b");
  assert.equal(placements[1].anchorId, "parent-a");
  assert.deepEqual(placements[0].offset, placements[1].offset);
});

test("new subtrees are placed parent-first without moving existing nodes", () => {
  const edges = [
    { data: { id: "root-edge", source: "existing", target: "parent" } },
    { data: { id: "edge", source: "parent", target: "child" } }
  ];
  const placements = newNodePlacements(
    edges,
    ["child", "parent"],
    new Set(["existing"])
  );

  assert.deepEqual(placements.map(placement => placement.nodeId), ["parent", "child"]);
  assert.equal(placements[0].anchorId, "existing");
  assert.equal(placements[1].anchorId, "parent");
});

test("later graph children reserve offsets already used by an existing sibling", () => {
  const edges = [
    { data: { id: "old-edge", source: "parent", target: "old-child" } },
    { data: { id: "new-edge", source: "parent", target: "new-child" } }
  ];

  const placements = newNodePlacements(
    edges,
    ["new-child"],
    new Set(["parent", "old-child"])
  );

  assert.deepEqual(placements[0].offset, anchoredNodeOffset(1));
  assert.notDeepEqual(placements[0].offset, anchoredNodeOffset(0));
});

test("mobile layout preserves the tab panel scroll boundary", async () => {
  const stylesheet = await readFile(
    new URL("../../priv/static/beam_console.css", import.meta.url),
    "utf8"
  );

  assert.match(
    stylesheet,
    /@media \(max-width: 760px\)[\s\S]*?\.beam-console-tab-main\s*\{[\s\S]*?flex:\s*0 0 clamp\(520px, 70dvh, 760px\)[\s\S]*?grid-template-rows:\s*minmax\(0, 1fr\)/
  );
  assert.match(stylesheet, /\.beam-console-tab-scroll\s*\{[\s\S]*?overflow:\s*auto/);
  assert.match(
    stylesheet,
    /@media \(max-width: 760px\)[\s\S]*?\.beam-console-legend\s*\{[\s\S]*?display:\s*none[\s\S]*?\.beam-console-graph-controls\s*\{[\s\S]*?flex:\s*0 0 auto/
  );
  assert.match(
    stylesheet,
    /@media \(max-width: 760px\)[\s\S]*?\.beam-console-graph-stage\s*\{[\s\S]*?grid-template-rows:\s*auto 412px[\s\S]*?\.beam-console-graph-toolbar > div:first-child\s*\{[\s\S]*?display:\s*none/
  );
});

test("narrow layouts expose runtime and inspector as overlay panels", async () => {
  const stylesheet = await readFile(
    new URL("../../priv/static/beam_console.css", import.meta.url),
    "utf8"
  );

  assert.match(
    stylesheet,
    /@media \(max-width: 760px\)[\s\S]*?\.beam-console-sidebar\s*\{[\s\S]*?position:\s*fixed[\s\S]*?transform:\s*translateX\(-105%\)/
  );
  assert.match(
    stylesheet,
    /\.beam-console-frame\.has-mobile-panel \.beam-console-panel-backdrop\s*\{[\s\S]*?display:\s*block/
  );

  const panelHook = await readFile(
    new URL("../js/panel_hook.mjs", import.meta.url),
    "utf8"
  );

  assert.match(panelHook, /panel\.inert = mobile && !active/);
  assert.match(panelHook, /event\.key === "Tab"/);
  assert.match(panelHook, /activeToggle\?\.focus\(\)/);
});

test("mobile panels restore focus when dismissed", () => {
  let focused = false;
  let synced = false;

  const hook = {
    ...BeamConsolePanels,
    activePanel: "inspector",
    returnFocus: { focus: () => { focused = true; } },
    syncPanels: () => { synced = true; }
  };

  hook.closePanels();

  assert.equal(hook.activePanel, null);
  assert.equal(synced, true);
  assert.equal(focused, true);
});

test("mobile panels wrap keyboard focus inside the active drawer", () => {
  let firstFocused = false;
  const first = { closest: () => null, focus: () => { firstFocused = true; } };
  const last = { closest: () => null, focus: () => {} };
  const panel = {
    contains: element => [first, last].includes(element),
    querySelectorAll: () => [first, last]
  };
  const previousDocument = globalThis.document;
  globalThis.document = { activeElement: last };

  try {
    const hook = {
      ...BeamConsolePanels,
      activePanel: "runtime",
      el: { querySelector: () => panel }
    };
    let prevented = false;

    hook.containFocus({
      preventDefault: () => { prevented = true; },
      shiftKey: false
    });

    assert.equal(prevented, true);
    assert.equal(firstFocused, true);
  } finally {
    globalThis.document = previousDocument;
  }
});

test("runtime summary adapts before cards become cramped", async () => {
  const stylesheet = await readFile(
    new URL("../../priv/static/beam_console.css", import.meta.url),
    "utf8"
  );

  assert.match(
    stylesheet,
    /\.beam-console-runtime-summary\s*\{[\s\S]*?grid-template-columns:\s*repeat\(auto-fit, minmax\(150px, 1fr\)\)/
  );
});

test("tablet process diagnostics do not compete with relationship rows", async () => {
  const stylesheet = await readFile(
    new URL("../../priv/static/beam_console.css", import.meta.url),
    "utf8"
  );

  assert.match(
    stylesheet,
    /@media \(max-width: 1180px\)[\s\S]*?\.beam-console-diagnostics\s*\{[\s\S]*?grid-column:\s*1 \/ -1/
  );
});

test("header navigation keeps a fixed center column across tabs", async () => {
  const stylesheet = await readFile(
    new URL("../../priv/static/beam_console.css", import.meta.url),
    "utf8"
  );

  assert.match(
    stylesheet,
    /\.beam-console-header\s*\{[\s\S]*?grid-template-columns:\s*minmax\(0, 1fr\) auto minmax\(0, 1fr\)/
  );
  assert.match(
    stylesheet,
    /@media \(max-width: 1180px\)[\s\S]*?\.beam-console-header\s*\{[\s\S]*?grid-template-columns:\s*auto minmax\(0, 1fr\)[\s\S]*?grid-template-rows:\s*auto auto/
  );
  assert.match(stylesheet, /\.beam-console-search-form\.is-placeholder\s*\{[\s\S]*?visibility:\s*hidden/);
});
