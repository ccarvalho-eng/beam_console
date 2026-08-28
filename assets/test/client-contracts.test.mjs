import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import { BeamConsolePanels } from "../js/panel_hook.mjs";

import {
  anchoredNodeOffset,
  chartAriaLabel,
  chartDomain,
  chartHeadline,
  focusShortcutAction,
  formatChartValue,
  graphUpdateMode,
  graphOmissionLabel,
  newNodePlacements,
  readStoredBranchStates,
  readStoredBoolean,
  readStoredTheme,
  writeStoredBranchStates,
  writeStoredBoolean,
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

test("focus preference persists as a strict mount-scoped boolean", () => {
  const localStorage = storage({});
  const storageOwner = { localStorage };
  const key = "beam-console:focus:/admin/beam";

  assert.equal(readStoredBoolean(storageOwner, key), false);

  writeStoredBoolean(storageOwner, key, true);
  assert.equal(readStoredBoolean(storageOwner, key), true);

  writeStoredBoolean(storageOwner, key, false);
  assert.equal(readStoredBoolean(storageOwner, key), false);

  localStorage.setItem(key, "unexpected");
  assert.equal(readStoredBoolean(storageOwner, key), false);
});

test("focus shortcuts avoid interactive controls and modified keystrokes", () => {
  const plainTarget = { closest: () => null };
  const editableTarget = { closest: selector => selector.includes("input") ? {} : null };

  assert.equal(focusShortcutAction({ key: "f", target: plainTarget }, false), "toggle");
  assert.equal(focusShortcutAction({ key: "F", target: plainTarget }, true), "toggle");
  assert.equal(focusShortcutAction({ key: "Escape", target: plainTarget }, true), "exit");
  assert.equal(focusShortcutAction({ key: "Escape", target: editableTarget }, true), "exit");
  assert.equal(focusShortcutAction({ key: "Escape", target: plainTarget }, false), null);
  assert.equal(focusShortcutAction({ key: "f", target: editableTarget }, false), null);
  assert.equal(
    focusShortcutAction({ key: "f", target: editableTarget, isComposing: true }, false),
    null
  );
  assert.equal(
    focusShortcutAction({ key: "f", target: plainTarget, metaKey: true }, false),
    null
  );
  assert.equal(focusShortcutAction({ key: "f", target: plainTarget, repeat: true }, false), null);
});

test("restricted storage getters cannot abort client startup", () => {
  const storageOwner = {
    get localStorage() {
      throw new DOMException("Storage is unavailable", "SecurityError");
    }
  };

  assert.equal(readStoredTheme(storageOwner, "phx:theme", new Set(["dark"])), null);
  assert.equal(readStoredBoolean(storageOwner, "beam-console:focus:/beam"), false);
  assert.deepEqual(readStoredBranchStates(storageOwner, "tree"), []);
  assert.doesNotThrow(() => writeStoredTheme(storageOwner, "phx:theme", "dark"));
  assert.doesNotThrow(() => writeStoredBoolean(storageOwner, "beam-console:focus:/beam", true));
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
      [
        { label: "Input", points: [[1, 1, 0]] },
        { label: "Output", points: [[1, 2, 0]] }
      ],
      "bytes",
      format
    ),
    "Input 1 bytes · Output 2 bytes"
  );
});

test("chart values preserve percentage units", () => {
  assert.equal(formatChartValue(11.77, "%"), "11.8%");
  assert.equal(formatChartValue(2048, "bytes/s"), "2.0 KB/s");
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
    /\.beam-console-frame\.has-overlay-panel \.beam-console-panel-backdrop\s*\{[\s\S]*?display:\s*block/
  );

  const panelHook = await readFile(
    new URL("../js/panel_hook.mjs", import.meta.url),
    "utf8"
  );

  assert.match(panelHook, /panel\.inert = overlayOpen \? !active : drawer/);
  assert.match(panelHook, /event\.key === "Tab"/);
  assert.match(panelHook, /activeToggle\?\.focus\(\)/);
});

test("focus mode exposes the runtime hierarchy as a desktop drawer", () => {
  const desktop = { matches: false };
  const hook = { ...BeamConsolePanels, media: desktop, focusActive: true };

  assert.equal(hook.panelIsDrawer("runtime"), true);
  assert.equal(hook.panelIsDrawer("inspector"), false);

  hook.focusActive = false;
  assert.equal(hook.panelIsDrawer("runtime"), false);
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

test("focus mode updates browser state without touching runtime controls", () => {
  const previousDocument = globalThis.document;
  const previousWindow = globalThis.window;
  const localStorage = storage({});
  let synced = false;
  let resized = false;

  globalThis.document = { documentElement: { dataset: {} } };
  globalThis.window = { localStorage };

  try {
    const hook = {
      ...BeamConsolePanels,
      activePanel: null,
      focusActive: false,
      focusStorageKey: "beam-console:focus:/beam",
      writeFocusPreference: active => {
        writeStoredBoolean(window, "beam-console:focus:/beam", active);
      },
      syncFocusMode: () => { synced = true; },
      syncPanels: () => {},
      scheduleWorkspaceResize: () => { resized = true; }
    };

    hook.setFocusMode(true, true, false);

    assert.equal(hook.focusActive, true);
    assert.equal(document.documentElement.dataset.beamConsoleFocus, "true");
    assert.equal(localStorage.getItem(hook.focusStorageKey), "true");
    assert.equal(synced, true);
    assert.equal(resized, true);
  } finally {
    globalThis.document = previousDocument;
    globalThis.window = previousWindow;
  }
});

test("storage-driven focus changes recover focus only from hidden chrome", () => {
  const headerControl = { closest: selector => selector.includes("beam-console-header") ? {} : null };
  const workspaceControl = { closest: () => null };
  const previousDocument = globalThis.document;

  try {
    const hook = {
      ...BeamConsolePanels,
      el: {
        contains: element => [headerControl, workspaceControl].includes(element),
        dataset: { beamConsoleHasSelection: "false" }
      }
    };

    globalThis.document = { activeElement: headerControl };
    assert.equal(hook.focusTransitionHidesActiveControl(true), true);

    globalThis.document = { activeElement: workspaceControl };
    assert.equal(hook.focusTransitionHidesActiveControl(true), false);

    hook.activePanel = "inspector";
    hook.el.dataset.beamConsoleHasSelection = "true";
    assert.equal(hook.focusTransitionHidesActiveControl(true), true);
    assert.equal(hook.focusTransitionHidesActiveControl(false), true);
  } finally {
    globalThis.document = previousDocument;
  }
});

test("storage-driven focus exit closes drawers before restoring visible focus", () => {
  const previousDocument = globalThis.document;
  let closed = false;
  let moveFocus = false;

  globalThis.document = {
    documentElement: { dataset: {} },
    activeElement: { closest: () => null }
  };

  try {
    const hook = {
      ...BeamConsolePanels,
      focusActive: true,
      activePanel: "runtime",
      el: { contains: () => true },
      closePanels: () => {
        closed = true;
        hook.activePanel = null;
      },
      syncFocusMode: move => { moveFocus = move; },
      syncPanels: () => {},
      scheduleWorkspaceResize: () => {}
    };
    const focusMustMove = hook.focusTransitionHidesActiveControl(false);

    hook.setFocusMode(false, false, focusMustMove, false);

    assert.equal(closed, true);
    assert.equal(moveFocus, true);
    assert.equal(hook.activePanel, null);
  } finally {
    globalThis.document = previousDocument;
  }
});

test("focus mode closes an inspector drawer when its selection disappears", () => {
  const exit = {};
  let closed = false;
  const hook = {
    ...BeamConsolePanels,
    focusActive: true,
    activePanel: "inspector",
    returnFocus: null,
    el: {
      dataset: { beamConsoleHasSelection: "false" },
      querySelector: selector => selector === "#beam-console-focus-exit" ? exit : null
    },
    syncFocusMode: () => {},
    closePanels: () => { closed = true; }
  };

  hook.updated();

  assert.equal(hook.returnFocus, exit);
  assert.equal(closed, true);
});

test("a panel receiving focus becomes the active drawer at the mobile breakpoint", () => {
  const runtimeToggle = {};
  const focusedPanel = {
    dataset: { beamConsolePanel: "runtime" }
  };
  const previousDocument = globalThis.document;
  let focusedDrawer = false;

  globalThis.document = {
    activeElement: {
      closest: selector => selector === "[data-beam-console-panel]" ? focusedPanel : null
    }
  };

  try {
    const hook = {
      ...BeamConsolePanels,
      media: { matches: true },
      focusActive: false,
      activePanel: null,
      returnFocus: null,
      panelToggle: () => runtimeToggle,
      syncPanels: focusPanel => { focusedDrawer = focusPanel; }
    };

    hook.syncBreakpoint();

    assert.equal(hook.activePanel, "runtime");
    assert.equal(hook.returnFocus, runtimeToggle);
    assert.equal(focusedDrawer, true);
  } finally {
    globalThis.document = previousDocument;
  }
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
  assert.match(
    stylesheet,
    /@media \(max-width: 760px\)[\s\S]*?\.beam-console-runtime-summary\s*\{[\s\S]*?display:\s*flex[\s\S]*?overflow-x:\s*auto/
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

test("focus mode provides a fixed workspace bar and hierarchy drawer", async () => {
  const stylesheet = await readFile(
    new URL("../../priv/static/beam_console.css", import.meta.url),
    "utf8"
  );
  const bootstrap = await readFile(
    new URL("../../priv/static/beam_console_theme.js", import.meta.url),
    "utf8"
  );

  assert.match(bootstrap, /beam-console:focus:/);
  assert.match(bootstrap, /document\.currentScript/);
  assert.match(bootstrap, /dataset\.consolePrefix/);
  assert.match(
    stylesheet,
    /data-beam-console-focus="true"[\s\S]*?\.beam-console-header[\s\S]*?display:\s*none/
  );
  assert.match(
    stylesheet,
    /data-beam-console-focus="true"[\s\S]*?data-beam-console-has-selection="false"[\s\S]*?\.beam-console-inspector[\s\S]*?display:\s*none/
  );
  assert.match(
    stylesheet,
    /data-beam-console-focus="true"[\s\S]*?\.beam-console-focus-bar[\s\S]*?display:\s*flex/
  );
  assert.match(
    stylesheet,
    /data-beam-console-focus="true"[\s\S]*?\.beam-console-shell\s*\{[\s\S]*?height:\s*100dvh[\s\S]*?min-height:\s*0/
  );
  assert.match(
    stylesheet,
    /data-beam-console-focus="true"[\s\S]*?\.beam-console-focus-bar\s*\{[\s\S]*?grid-column:\s*1 \/ -1[\s\S]*?grid-row:\s*1/
  );
  assert.match(
    stylesheet,
    /data-beam-console-focus="true"[\s\S]*?\.beam-console-frame\s*\{[\s\S]*?height:\s*100dvh[\s\S]*?min-height:\s*0/
  );
  assert.match(
    stylesheet,
    /data-beam-console-focus="true"[\s\S]*?\.beam-console-sidebar[\s\S]*?position:\s*fixed[\s\S]*?transform:\s*translateX\(-105%\)/
  );
  assert.match(
    stylesheet,
    /data-beam-console-focus="true"[\s\S]*?\.beam-console-sidebar\.is-mobile-open[\s\S]*?transform:\s*translateX\(0\)/
  );
  assert.match(
    stylesheet,
    /@media \(max-width: 760px\)[\s\S]*?data-beam-console-focus="true"[\s\S]*?\.beam-console-focus-inspector[\s\S]*?display:\s*grid/
  );
  assert.match(
    stylesheet,
    /data-beam-console-focus="true"[\s\S]*?\.beam-console-focus-actions[\s\S]*?\.beam-console-focus-inspector\s*\{[\s\S]*?display:\s*none/
  );
  assert.match(
    stylesheet,
    /data-beam-console-focus="true"[\s\S]*?grid-template-columns:\s*minmax\(0, 1fr\) clamp\(280px, 32vw, 332px\)/
  );
  assert.match(
    stylesheet,
    /@media \(max-width: 760px\)[\s\S]*?\.beam-console-main:not\(\.beam-console-tab-main\)[\s\S]*?grid-template-rows:\s*minmax\(0, 1\.8fr\) minmax\(0, 1fr\)/
  );
  assert.match(
    stylesheet,
    /@media \(max-width: 760px\)[\s\S]*?data-beam-console-has-selection="true"[\s\S]*?grid-template-columns:\s*minmax\(0, 1fr\)/
  );
  assert.match(
    stylesheet,
    /@media \(max-width: 760px\)[\s\S]*?data-beam-console-focus="true"[\s\S]*?\.beam-console-graph\s*\{[\s\S]*?min-height:\s*0/
  );
});
