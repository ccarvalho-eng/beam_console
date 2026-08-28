# Changelog

## Unreleased

- Add bounded scheduling, heap, and garbage-collection diagnostics to the process inspector.
- Make process group leaders selectable when they are present in the latest snapshot.

## 0.4.0 - 2026-08-27

- Add restart-safe operator recording control shared by the collector and lifecycle recorder.
- Stop opt-in always-on background scans after recording is paused and the final viewer disconnects.
- Keep connected dashboards live while lifecycle recording is paused.
- Cancel deferred lifecycle reconciliation on pause without terminating an in-flight runtime scan.

## 0.3.0 - 2026-08-27

- Keep always-on lifecycle recording active across zero-viewer and runtime-service restart windows.
- Add bounded, acknowledged lifecycle reconciliation without collector-recorder dependency cycles.
- Distinguish exact VM process totals from the bounded set inspected by the collector.
- Add bounded runtime-client timeouts and explicit stale-service handling in the console.
- Preserve process, lifecycle, graph, chart, selection, and folder-tree continuity across live samples.
- Add responsive runtime and inspector drawers with modal focus isolation and keyboard dismissal.

## 0.2.0 - 2026-08-27

- Add atom count, atom limit, and utilization to the Runtime summary.
- Add bounded atom-table utilization history to the Runtime charts.

## 0.1.1 - 2026-08-27

- Add CI, security, Hex, HexDocs, and license badges to the project README.
- Update the installation example for the 0.1.1 release.

## 0.1.0 - 2026-08-27

- Add an embeddable Phoenix LiveView process map and collapsible runtime tree.
- Add safe process, application, connected-node, link, and monitor inspection.
- Add a bounded process flight recorder with pause/resume controls and lifecycle correlation.
- Add Activity and Runtime history views with deterministic bounded downsampling.
- Add light, dark, and system themes, stale-sample reporting, and explicit coverage warnings.
- Add host LiveView authorization hooks and session integration.
