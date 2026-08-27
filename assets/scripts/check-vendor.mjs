import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const root = new URL("../../", import.meta.url);
const lock = JSON.parse(await readFile(new URL("assets/package-lock.json", root), "utf8"));
const version = lock.packages["node_modules/cytoscape"].version;
const bundle = await readFile(new URL("priv/static/cytoscape.esm.min.mjs", root), "utf8");
const sourceBundle = await readFile(
  new URL("assets/node_modules/cytoscape/dist/cytoscape.esm.min.mjs", root),
  "utf8"
);
const notices = await readFile(new URL("THIRD_PARTY_NOTICES", root), "utf8");
const license = await readFile(new URL("priv/static/CYTOSCAPE_LICENSE", root), "utf8");
const sourceLicense = await readFile(new URL("assets/node_modules/cytoscape/LICENSE", root), "utf8");
const phoenixLicense = await readFile(new URL("priv/static/PHOENIX_LICENSE", root), "utf8");
const liveViewLicense = await readFile(new URL("priv/static/PHOENIX_LIVE_VIEW_LICENSE", root), "utf8");

assert.match(bundle, new RegExp(`version=["']${version.replaceAll(".", "\\.")}["']`));
assert.equal(bundle, sourceBundle, "vendored Cytoscape bundle differs from the locked package");
assert.equal(license, sourceLicense, "vendored Cytoscape license differs from the locked package");
assert.match(notices, new RegExp(`Cytoscape\\.js ${version.replaceAll(".", "\\.")}`));
assert.match(license, /Permission is hereby granted, free of charge/);
assert.match(license, /The Cytoscape Consortium/);
assert.match(phoenixLicense, /Copyright \(c\) 2014 Chris McCord/);
assert.match(phoenixLicense, /Permission is hereby granted, free of charge/);
assert.match(liveViewLicense, /Copyright \(c\) 2018 Chris McCord/);
assert.match(liveViewLicense, /Permission is hereby granted, free of charge/);
assert.match(notices, /PHOENIX_LICENSE/);
assert.match(notices, /PHOENIX_LIVE_VIEW_LICENSE/);
