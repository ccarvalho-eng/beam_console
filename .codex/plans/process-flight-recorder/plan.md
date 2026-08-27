# Process Flight Recorder implementation plan

## Outcome

Build a bounded, local, process-centric flight recorder and four-tab embedded dashboard that answers:

> What is running, where does it belong, what changed recently, and what direct or sampled evidence do we have?

The work is intentionally split into reviewable increments. Each increment must leave the Process Map usable, preserve optional Phoenix dependencies, and keep the package shippable.

## Delivery slices

1. **Foundation checkpoint**: accept the current quality, documentation, folder-tree, theme, graph, and DynamicSupervisor-edge fixes as a focused commit.
2. **Recorder core**: compact contracts, bounded history, subscriber backpressure, supervised PID monitors, and conservative correlation.
3. **Dashboard structure**: URL-backed tabs, pure presenters/components, categorized application tree, and removal of full snapshots from socket state.
4. **Flight-recorder UI**: Lifecycle, Activity, and Runtime views with bounded, process-linked charts.
5. **Release hardening**: compatibility matrix, deterministic failure tests, benchmarks, docs, and package verification.

Do not combine these into one large change. Recorder behavior and concurrency should be independently reviewable from the visual dashboard work.

## Non-negotiable contracts

- Lifecycle history is local, in-memory, bounded, and begins when recording activates.
- Direct process-monitor evidence and sampled snapshot evidence are visibly distinct.
- A stable supervisor slot supports “replacement observed”; it does not prove causality.
- DynamicSupervisor children are not paired as replacements in the first release.
- Browser payloads contain opaque IDs and bounded scalar data only.
- Recorder history contains no PIDs, full snapshots, raw exit terms, paths, or arbitrary application terms.
- A stalled subscriber cannot accumulate an unbounded notification mailbox.
- No LiveView retains a complete snapshot after a callback returns.
- No host instrumentation or asset-pipeline modification is required.
- Every new public API has `@moduledoc`, `@doc`, and `@spec`; pure deterministic APIs include doctests where useful.

## Phase 0: foundation checkpoint

### 0.1 Review and isolate the current foundation

- [x] Review the uncommitted diff and separate it from recorder behavior. — committed as focused runtime, web, quality, and planning checkpoints.
- [x] Keep the full Apache 2.0 license, Ancient Stones-equivalent quality aliases, CI/security workflows, Hex packaging rules, module docs, specs, and doctests.
- [x] Keep the extracted `BeamConsole.Runtime.Supervision` traversal and immutable state module.
- [x] Keep distinct DynamicSupervisor edge identities and the two-child regression test.
- [x] Keep native `<details>` runtime branches with disclosure preservation.
- [x] Keep the three-way system/light/dark control after refresh and the settled graph-camera behavior.
- [x] Run the complete existing precommit, coverage, demo, plain-host, npm syntax, workflow YAML, Hex build, and diff checks before committing this slice. — final coverage 83.18%; root, demo, plain-host, asset, static-analysis, security, and package checks passed.

Done when the working dashboard is a clean, independently revertible base and no recorder modules exist in the slice.

## Phase 1: compact recorder contracts and pure history

### 1.1 Add validated recorder configuration

Files:

- `lib/beam_console/recorder/config.ex`
- `lib/beam_console/config.ex`
- `config/config.exs` documentation examples as applicable

Tasks:

- [x] Define validated limits for retention, event/frame counts, watch count, reconciliation batch size, pending-slot window, tracked series, point caps, byte estimate, and lazy/always mode. — added `BeamConsole.Recorder.Config` with conservative hard defaults.
- [x] Reject negative or internally inconsistent limits at startup with actionable errors. — structured validation plus raising startup loader.
- [x] Keep the config Phoenix-independent and document operational tradeoffs.
- [x] Add table tests for defaults, overrides, invalid values, and boundary values. — 5 focused tests pass.

### 1.2 Define compact normalized values

Files:

- `lib/beam_console/recorder/frame.ex`
- `lib/beam_console/lifecycle/event.ex`
- `lib/beam_console/lifecycle/observation.ex`
- `lib/beam_console/activity/sample.ex`
- `lib/beam_console/runtime/sample.ex`
- `lib/beam_console/reason_summary.ex`

Tasks:

- [x] Define typed structs for compact summary frames, safe lifecycle events, private ephemeral observations, activity samples, and allowlisted runtime samples. — added six documented, field-typed core values.
- [x] Separate ephemeral monitor observations containing PIDs from retained/browser-safe values. — only `Lifecycle.Observation` carries PIDs and documents its non-retention boundary.
- [x] Add explicit evidence/certainty enums and sequence-segment metadata.
- [x] Implement bounded label and exit-reason sanitization with redaction, depth, collection, and byte limits. — arbitrary binaries and runtime terms are represented structurally.
- [x] Add doctests only for deterministic constructors/sanitizers. — ReasonSummary doctests pass with the existing EntityId doctests.

### 1.3 Implement pure bounded history

Files:

- `lib/beam_console/recorder/history.ex`
- `lib/beam_console/recorder/query.ex`
- `test/beam_console/recorder/history_test.exs`

Tasks:

- [x] Implement immutable append/query/eviction transitions with injected monotonic time and byte estimator. — `History` and `Query` remain process-free and deterministic under injected inputs.
- [x] Enforce age, count, series, points, total-points, and estimated-byte caps independently.
- [x] Reject duplicate/out-of-order sequences without mutation.
- [x] Start a new segment on sequence gaps or reset and prevent correlation across it. — explicit bounded gap/reset events mark segment boundaries.
- [x] Track dropped/omitted counts and available ranges.
- [x] Use deterministic LRU eviction with opaque entity ID as the tie-breaker.
- [x] Test empty, exact-cap, cap-plus-one, ten-times-cap, age boundaries, byte pressure, churn cleanup, and stale/reset behavior. — 48 full-suite tests and 5 doctests pass.
- [x] Require at least 95% coverage for the new pure history/query modules. — History 99.31%, Query 100%, overall 87.55%.

Done when compact frames/events can be appended and queried under all hard bounds without starting a process.

## Phase 2: collector delivery, lifecycle monitoring, and correlation

### 2.1 Replace unbounded subscriber messages

Files:

- `lib/beam_console/collector.ex`
- `lib/beam_console.ex`
- `test/beam_console/collector_test.exs`

Tasks:

- [x] Replace full diff notifications with version invalidation: one outstanding sequence and one replaceable pending sequence per subscriber. — Notifications now carry only the newest committed sequence.
- [x] Add a documented acknowledgement API and bounded `since`/resync behavior. — `acknowledge/2` and `changes_since/2` are caller-scoped and documented.
- [x] Ignore stale, duplicate, future, dead-subscriber, and cross-subscriber acknowledgements safely. — Covered by invalid, independent-subscriber, and monitored-death tests.
- [x] Pass fake-runtime owner/options per collector instance instead of using application environment. — Runtime fixture state is collector-local.
- [x] Add barrier-driven tests showing 100 commits produce one stalled-subscriber message and one pending version. — A concurrent fast subscriber also proves isolation.
- [x] Preserve scan non-overlap, coalesced refresh, last-good snapshot, and failure recovery. — Error, crash, timeout, manual-refresh, and last-good paths pass targeted tests.

This is a public protocol change. Document migration behavior and keep delivery state isolated behind `Collector.Subscriber`.

### 2.2 Emit private supervision observations once

Files:

- `lib/beam_console/runtime/supervision.ex`
- `lib/beam_console/snapshot.ex`
- `lib/beam_console/collector.ex`

Tasks:

- [x] Produce bounded server-only observations during the existing supervision traversal. — One child-limit-bound observation is produced beside each normalized edge.
- [x] Mark stable normal-supervisor slots separately from dynamic slots. — Stable child-spec slots persist across stopped/restarted states; dynamic children remain PID-disambiguated.
- [x] Include supervisor PID, child PID/state/type/modules, stable opaque slot ID, sequence, and coverage flags only in the ephemeral handoff. — Modules are atom-only and capped; observations are removed before public snapshot storage.
- [x] Never decode an entity ID or repeat `which_children/1` in the recorder. — The collector hands the original private runtime observations directly to the recorder boundary.
- [x] Preserve partial/truncated branch metadata so certainty can only decrease. — Per-observation truncation and overall snapshot coverage travel together in the handoff.

### 2.3 Implement the supervised lifecycle recorder

Files:

- `lib/beam_console/recorder.ex`
- `lib/beam_console/lifecycle/recorder.ex`
- `lib/beam_console/application.ex`
- `test/beam_console/lifecycle/recorder_test.exs`

Tasks:

- [x] Supervise a recorder GenServer beside the collector. — The public facade returns only PID-free status and bounded event queries.
- [x] Activate watches lazily with the first subscriber and stop future sampling after the last subscriber leaves; document in-flight completion. — `:always` mode now also drives collector sampling without viewers.
- [x] Monitor only eligible local supervised PIDs, one monitor per PID, capped at 5,000 by default. — Dynamic children are watched for direct exits but excluded from stable-slot candidates.
- [x] Reconcile at most 500 watch changes per completed snapshot and expose watched/eligible/omitted coverage. — Deferred work is reported separately from hard-cap omissions.
- [x] Handle `:DOWN` in O(1): timestamp, sanitize/classify, append, and schedule later reconciliation only. — Bounded history enforcement runs in a deferred mailbox turn.
- [x] Keep watches across partial samples and require two complete omissions before removing a still-live watch. — Barrier tests cover partial, truncated, first-complete, and second-complete frames.
- [x] Store pending stable-slot exits for the bounded correlation window. — Pending values are private, watch-capped, and expire at a documented inclusive boundary.
- [x] Continue collector operation when the recorder is unavailable; emit a reset/gap after recovery. — Each handoff reasserts activation; missed delivery and opaque collector-epoch changes force a reset boundary.

### 2.4 Implement conservative pure correlation

Files:

- `lib/beam_console/lifecycle/correlator.ex`
- `test/beam_console/lifecycle/correlator_test.exs`

Tasks:

- [ ] Correlate only the same stable supervisor PID and child-spec slot within one complete sequence segment.
- [ ] Emit direct termination and strong/medium replacement evidence with machine-readable reasons for any certainty cap.
- [ ] Represent restarting transitions without inventing intermediate PIDs.
- [ ] Refuse high certainty for partial/truncated samples, sequence gaps, ambiguous targets, module/name-only matches, and all dynamic slots.
- [ ] Table-test every research scenario, including exact correlation-window boundaries.
- [ ] Add deterministic doctests for fully specified evidence values.

Done when the core API can report bounded direct exits and honest stable-slot replacements without Phoenix running.

## Phase 3: dashboard structure and categorized folder tree

### 3.1 Add URL-backed tab state

Files:

- `lib/beam_console/router.ex`
- `lib/beam_console_web/console/params.ex`
- `lib/beam_console_web/console/paths.ex`
- `lib/beam_console_web/console_live.ex`

Tasks:

- [ ] Route `/beam`, `/beam/lifecycle`, `/beam/activity`, and `/beam/runtime` to one LiveView with four live actions.
- [ ] Make `handle_params/3` the source of truth for tab, node, entity, query, kind, edge preset, and window.
- [ ] Whitelist/cap values without creating atoms from client input.
- [ ] Preserve shared node/entity selection across tab patches and discard irrelevant tab-only filters.
- [ ] Test nested mount prefixes and params/path round trips.

### 3.2 Decompose the current LiveView

Files:

- `lib/beam_console_web/console_live.ex`
- `lib/beam_console_web/console_live.html.heex`
- `lib/beam_console_web/console/*_presenter.ex`
- `lib/beam_console_web/components/*_components.ex`

Tasks:

- [ ] Limit `ConsoleLive` to mount, params, events, messages, stream resets, and bounded push events.
- [ ] Move all snapshot-to-view work into pure presenters.
- [ ] Move HEEx sections into stateless function components; do not add stateful LiveComponents.
- [ ] Stop assigning `%BeamConsole.Snapshot{}` to sockets. Consume it transiently and retain only bounded summaries, selection view models, revisions, and URL state.
- [ ] Keep large collections in bounded streams.
- [ ] Add a state-inspection regression test proving sockets retain neither a snapshot nor chart point arrays.

### 3.3 Add deterministic application categories

Files:

- `lib/beam_console/application_info.ex`
- `lib/beam_console/application_tree_config.ex`
- `lib/beam_console_web/console/application_tree_presenter.ex`
- `lib/beam_console_web/components/tree_components.ex`

Tasks:

- [ ] Collect safe application dependency/provenance facts without exposing paths.
- [ ] Implement host, dependencies, OTP, tooling, and unattributed default categories.
- [ ] Apply explicit mapping, validated classifier callback, host list, provenance, top-level dependency inference, and fallback in deterministic precedence order.
- [ ] Validate configured IDs, order, labels, and callback results server-side.
- [ ] Render category and application branches as native `<details>` with stable IDs and counts.
- [ ] Persist collapsed state by mount prefix and node ID without `phx-update="ignore"` on server-owned tree content.
- [ ] Test umbrella-style hosts, overrides, custom labels/order, invalid callbacks, inference, and unattributed processes.

Done when Process Map behavior is preserved behind a smaller coordinator and the tree is useful without configuration but exact when configured.

## Phase 4: Lifecycle tab

Files:

- `lib/beam_console_web/console/lifecycle_presenter.ex`
- `lib/beam_console_web/components/lifecycle_components.ex`
- lifecycle query tests and LiveView tests

Tasks:

- [ ] Stream at most 250 visible newest events from a bounded recorder query.
- [ ] Support capped search, event-kind, application/category, node, and time-window filters.
- [ ] Show recording start/reset, available range, omitted count, watch coverage, and partial/gap warnings.
- [ ] Render direct exit, sampled start/stop, topology change, mailbox threshold, and replacement evidence with distinct wording/badges.
- [ ] Keep a stopped selected process as a safe tombstone using event-captured labels/metadata.
- [ ] Link lifecycle rows to the shared inspector and Process Map selection.
- [ ] Add deterministic Phoenix demo restart tests synchronized by fixture messages, never sleeps.

Done when a developer can watch a supervised process exit and its stable-slot replacement appear in real time with correct evidence language.

## Phase 5: process activity and runtime samples

### 5.1 Collect compact activity deltas

Files:

- `lib/beam_console/activity.ex`
- `lib/beam_console/activity/sample.ex`
- collector-to-recorder commit path

Tasks:

- [ ] Compute reductions, mailbox, and memory deltas while both current and prior snapshots are transiently available.
- [ ] Convert reductions counters to rates; represent counter reset/wrap and sampling gaps explicitly.
- [ ] Rank before capping and retain aggregates plus at most 25 top movers per sample.
- [ ] Track selected/sparse process series under the global 32-series and 14,400-point budgets.
- [ ] Never derive activity from whole-struct `Diff.changed`.

### 5.2 Collect allowlisted runtime samples

Files:

- `lib/beam_console/runtime/local.ex`
- `lib/beam_console/runtime/sample.ex`

Tasks:

- [ ] Normalize process/application/supervisor/ETS counts, BEAM memory categories, scheduler/run-queue signals, and collector/recorder health.
- [ ] Keep runtime calls in the Phoenix-independent adapter, not presenters or LiveViews.
- [ ] Mark unsupported and partial measurements explicitly.
- [ ] Keep connected nodes inventory-only until a future remote adapter provides the same contract.

### 5.3 Implement deterministic downsampling

Files:

- `lib/beam_console/series/downsampler.ex`
- `test/beam_console/series/downsampler_test.exs`

Tasks:

- [ ] Downsample to at most 240 ordered points while preserving first/last, bucket extrema, and gap markers.
- [ ] Handle empty, singleton, constant, repeated timestamp, monotonic, spike, reset, and missing-sample series.
- [ ] Guarantee no invented out-of-range values and no line across a gap.
- [ ] Add deterministic property-style tests and a small doctest.

## Phase 6: Activity and Runtime tabs

### 6.1 Add bounded chart presenters and hooks

Files:

- `lib/beam_console_web/console/activity_presenter.ex`
- `lib/beam_console_web/console/runtime_presenter.ex`
- `lib/beam_console_web/components/activity_components.ex`
- `lib/beam_console_web/components/runtime_components.ex`
- `assets/js/hooks/chart.js`

Tasks:

- [ ] Emit scalar chart payloads with stable ID, revision, allowlisted unit/window, sampled time, bounded series/points, and omission metadata.
- [ ] Cap each tab update at four charts, six series per chart, 240 points per series, and 128 KiB encoded.
- [ ] Send chart events only for the active tab and coalesce to one pending flush per LiveView.
- [ ] Reject stale revisions/windows client-side and mutate one renderer instead of rebuilding it.
- [ ] Keep accessible titles, legends, current summaries, empty/error text, and table alternatives in LiveView-owned HTML.
- [ ] Start with a small native SVG/canvas renderer; document the reason before adding another browser dependency.

### 6.2 Build process-centric views

Tasks:

- [ ] Activity: reductions rate, mailbox movement/spikes, memory movement, application aggregates, and top movers.
- [ ] Runtime: BEAM memory composition, scheduler/run queue, process/application/supervisor/ETS counts, and collector/recorder health.
- [ ] Overlay or cross-link selected-process series and recent lifecycle events so charts explain processes rather than duplicate generic VM telemetry.
- [ ] Preserve selection and time window in URL-backed navigation.
- [ ] Restyle existing graph/charts on system/light/dark changes without changing data, positions, or zoom.

Done when each chart leads back to processes/topology and the Runtime tab remains a concise health context, not a LiveDashboard clone.

## Phase 7: maintainable browser assets

Files:

- `assets/js/beam_console.js`
- `assets/js/theme_controller.js`
- `assets/js/hooks/{application_tree,graph,chart}.js`
- `assets/js/{graph,charts}/*.js`
- `assets/css/*.css`
- `priv/static/beam_console.{mjs,css}`

Tasks:

- [ ] Extract authored theme, disclosure, graph, reconciliation, chart, and payload logic into focused source modules.
- [ ] Split CSS tokens, shell, tabs, tree, graph, inspector, lifecycle, charts, responsive, and dark-theme sources.
- [ ] Add a maintainer-only deterministic build and freshness check.
- [ ] Continue shipping one committed JS asset, one CSS asset, and vendored Cytoscape so Hex consumers run no npm build.
- [ ] Preserve immutable digest routes and optional Phoenix compilation guards.
- [ ] Add browser unit tests for disclosure persistence, graph settled-fit/material relayout, stale chart revisions, system-theme changes, storage synchronization, and hook cleanup.

## Phase 8: verification, performance, and release boundary

### 8.1 Deterministic concurrency/failure matrix

- [ ] Stable normal-supervisor replacement with explicit generation-start messages.
- [ ] Deterministic `:restarting` gap fixture.
- [ ] DynamicSupervisor ambiguity with no replacement correlation.
- [ ] Short-lived/missing-sample, partial branch, sequence gap, and reset fixtures.
- [ ] Runtime error, task crash, timeout, stale result, collector restart, and recorder restart.
- [ ] Lazy activation/deactivation and documented in-flight completion.
- [ ] Fast and stalled independent subscribers with acknowledgement/resync behavior.
- [ ] No `Process.sleep/1` in lifecycle/concurrency fixtures.

### 8.2 Compatibility and package checks

- [ ] Root warnings-as-errors compile, format, xref, unused lock, coverage, quality, security, docs, and Dialyzer.
- [ ] Phoenix demo compile/format/tests for all four tabs and self-contained assets.
- [ ] Plain-host runtime smoke: subscribe, receive version, query recorder, acknowledge, unsubscribe, and stop with no Phoenix module required.
- [ ] Elixir/OTP matrix covering Elixir 1.17–1.19 and OTP 26–28 with compatible pairings.
- [ ] Minimum/current supported Phoenix 1.8 rows, with declared constraints matching tested support.
- [ ] Hex build contents, Apache license, generated asset freshness, and documentation links.

### 8.3 Production-mode performance evidence

- [ ] Benchmark 1k, 5k, 10k, and 20k flat/nested/churning process farms after warm-up.
- [ ] Measure scan p50/p95/p99, timeouts, memory at capacity/after churn+GC, reductions, scheduler/run queue, mailbox lengths, append/query/downsample latency, and payload sizes.
- [ ] Validate provisional gates: 20k scan p95 < 1s and p99 < 1.5s, no overlap/timeouts, recorder <= 8 MiB estimated/16 MiB actual, append p95 < 5ms, query p95 < 10ms, payload <= 128 KiB, and stalled subscriber one-message bound.
- [ ] Lower limits or revise cadence based on evidence if a gate fails; document the tested envelope instead of hiding observer overhead.

### 8.4 Documentation and release notes

- [ ] Document what BeamConsole adds relative to LiveDashboard/Observer without competitive overclaims.
- [ ] Document recording start, bounded retention, gaps, sampled/direct evidence, local-only scope, and lost history on restart.
- [ ] Document application-category overrides and classifier safety contract.
- [ ] Document router installation, port override in the demo, theme/tree behavior, and troubleshooting/restart expectations after asset changes.
- [ ] Generate HexDocs and confirm public API docs/spec/doctests remain complete.

## Final acceptance

- [ ] A developer adds the dependency, mounts `/beam`, and needs no host instrumentation or asset changes.
- [ ] The Runtime tree is categorized, folder-like, collapsible, and stable across live patches.
- [ ] Small topology changes preserve graph positions; initial/material changes settle to a readable deterministic layout.
- [ ] A stable supervised crash produces a direct exit and a correctly worded replacement observation in real time.
- [ ] Dynamic children are never falsely paired.
- [ ] Lifecycle history and all charts respect every logical/byte/payload cap after ten-times-cap churn.
- [ ] Process Map, Lifecycle, Activity, and Runtime share URL-backed selection and safe details.
- [ ] LiveView sockets retain no full snapshots/history/point arrays.
- [ ] One stalled subscriber cannot grow its notification mailbox without bound.
- [ ] Root coverage remains at least 82%; new pure recorder/correlation/downsampling modules reach at least 95% and all state transitions have named tests.
- [ ] Phoenix demo, plain Elixir host, version matrix, static analysis, security, packaging, and production benchmarks satisfy the documented release envelope.

## Rollback boundaries

- Recorder supervision can be disabled independently while preserving the Process Map.
- Each new tab is route-gated and can be removed without changing collector snapshots.
- Application inference falls back to a flat started-application branch if config normalization fails before startup.
- Chart delivery is read-only and independent of the process table/inspector.
- In-memory recorder restart intentionally drops its bounded window and emits a visible reset; it never blocks collection.

## References

- `scratchpad.md`
- `research/otp-lifecycle.md`
- `research/dashboard-architecture.md`
- `research/testing-and-performance.md`
