# Process Flight Recorder: Testing and Performance Boundaries

## Conclusion

The recorder is viable if it stores compact event/frame data, not historical `Snapshot` structs, and if its limits are enforced independently of browser count. The default session should remain idle until the first subscriber and stop sampling after the last subscriber leaves. This preserves the library's current observer-overhead boundary; the UI must state when recording began rather than implying pre-existing history.

Three changes are blocking for a safe recorder:

1. Replace unrestricted subscriber sends with an acknowledgement/coalescing protocol so a stalled subscriber can hold at most one snapshot notification.
2. Give history hard limits for age, events, tracked processes, samples per series, total sample points, chart points, and estimated bytes. Never retain whole past snapshots.
3. Treat restart correlation as evidence with confidence. A label/module match is never sufficient, dynamic-supervisor `:undefined` child IDs are ambiguous, and partial or skipped samples cannot produce high confidence.

## Current repository baseline

- `BeamConsole.Collector` already uses one monitored task, coalesces concurrent refreshes, retains the last completed snapshot, and remains idle without subscribers.
- `collector_test.exs` has a barrier-driven non-overlap fixture, but it stores the test owner in application environment, forcing `async: false`. Pass the owner in per-collector runtime options instead so instances remain isolated.
- Notifications currently include the full `Diff` in an unrestricted `send/2`. A slow LiveView can accumulate one copied diff every interval.
- The collector retains current/previous snapshots only. Preserve that boundary; the recorder should receive compact committed frames/events from the collector.
- `Diff` already caps lifecycle records and uses correct `observed_` terminology.
- `Local` scans up to 20,000 processes at a two-second interval with a 1.5-second task timeout. These are provisional values, not measured production guarantees.
- Root tests enforce 82% line coverage, current CI uses Elixir 1.19/OTP 28, the demo covers the Phoenix host, and `fixtures/plain_host` verifies optional Phoenix dependencies are not required.
- The demo already exposes supervised restart, dynamic-child churn, mailbox growth, short-lived tasks, and a monitor relationship. Its restart assertion should wait for the replacement's explicit start message instead of reading the supervisor immediately after the old PID's `:DOWN`.

## Testable recorder contract

Model the flight recorder as a separate supervised in-memory service that accepts only committed collector data:

```text
committed snapshot + bounded diff
              |
              v
     compact Frame/Event values
              |
       bounded History
              |
       query + downsample
```

Recommended default logical bounds, subject to production benchmarks:

| Bound | Default | Acceptance rule |
|---|---:|---|
| Recording retention | 15 minutes | Entries older than the injected monotonic cutoff are evicted on append/query |
| Global events | 1,000 | `event_count <= 1_000` after any append sequence |
| Summary frames | 450 | One frame per two-second sample for at most 15 minutes |
| Tracked process series | 32 | New series use explicit bounded LRU eviction; browser count cannot raise the cap |
| Points per series | 450 | Oldest points are evicted deterministically |
| Total process points | 14,400 | Enforced independently of per-series caps |
| Chart output | 240 points/series | Any query returns at most 240 ordered points |
| Timeline response | 500 events | Omitted count and available range are returned |
| Estimated history bytes | 8 MiB | Append evicts until the configured estimator is at or below the cap |

The byte estimator must be deterministic and injectable in pure tests. Production may use `:erlang.external_size/1` for normalized values, with a documented safety multiplier because serialized size understates live map/process overhead. A production benchmark must also measure actual recorder-process memory after garbage collection.

Frames should contain sequence, monotonic/sample time, aggregate counts, coverage flags, and only the scalar metrics needed by charts. Events should contain opaque entity IDs, event kind, evidence, confidence, and bounded labels. Do not retain PIDs, snapshot indexes, application descriptions, arbitrary runtime terms, or relationship lists in history.

Appending an older/duplicate sequence returns a structured stale result and changes no state. A sequence gap starts a new correlation segment. Collector or recorder restart creates an explicit reset/gap event; correlation never crosses it.

## Deterministic OTP fixtures without sleeps

All test-owned processes use `start_supervised!/1`. No test uses `Process.sleep/1` or timing-dependent polling.

### Stable supervisor restart fixture

Create a test supervisor with a stable child spec ID and a worker that sends the owner:

```elixir
{:fixture_started, child_id, generation, pid}
```

from `init/1`. The test sequence is:

1. Receive generation 1 and take an explicit collector sample.
2. Monitor the old PID, terminate it abnormally, and assert its exact `:DOWN`.
3. Assert the generation-2 start message and verify the replacement PID differs.
4. Trigger/release the next explicit scan through the runtime barrier.
5. Assert the recorder emits the expected slot transition and confidence.

The replacement start message is the synchronization boundary. `:DOWN` alone proves only that the old PID exited, not that its supervisor completed restart.

### Restarting-gap fixture

Use a child whose second `init/1` waits on `{:continue_start, generation}` and reports that it is waiting. Sample the supervisor while its child slot is `:restarting`, then release it and sample again. This deterministically exercises old PID -> restarting -> new PID without sleeps.

### Dynamic-supervisor ambiguity fixture

Start at least two children under a `DynamicSupervisor`, terminate one, and start another with matching module/label. Since dynamic children commonly expose `:undefined` child IDs, assert that the correlation engine does not treat parent plus `:undefined` as a stable slot and does not report a high-confidence restart.

### Short-lived and missing-sample fixture

Use barrier-controlled runtime snapshots rather than racing the real scheduler. Supply snapshots in which a process appears and disappears between committed sequences, a sequence is skipped, or coverage is partial/truncated. Assert conservative observed events and no invented causal correlation.

## Correlation confidence tests

Keep correlation as a pure function over fixed prior/current slot observations, coverage, and time. Table-test both the confidence and its evidence payload.

| Scenario | Expected result |
|---|---|
| Same stable supervisor/child-spec slot changes old PID -> new PID in consecutive complete snapshots; old stops and new starts | `:high` observed replacement |
| Same stable slot passes through `:restarting`/`:undefined`, then receives a new PID within the configured window and all samples are complete | `:medium` observed replacement |
| Same stable slot changes target but lifecycle diff was truncated | At most `:medium`, with truncation evidence |
| Sequence gap, stale/reset segment, or partial supervisor branch | No high-confidence correlation |
| Same registered name/module/label under a different parent | No replacement correlation |
| Two plausible new targets for one old target | `:ambiguous`, not a chosen winner |
| Dynamic-supervisor `:undefined` siblings | No stable-slot correlation |
| Candidate arrives exactly at the correlation-window boundary | Deterministic inclusive/exclusive behavior documented and tested |
| Candidate arrives after the window | Independent observed stop/start events |

Every emitted correlation must retain machine-readable evidence: previous/current sequence, stable slot ID when available, old/new process IDs, completeness flags, elapsed time, and why confidence was capped. UI wording remains “observed replacement”; it must not claim exact supervisor causality.

## Bounded-history tests

Use pure `async: true` ExUnit tests with an injected monotonic clock and fixed structs:

- Empty, one-entry, exactly-at-cap, cap-plus-one, and many-times-cap append cases.
- Age eviction at one tick before, exactly at, and one tick after the retention boundary.
- Combined age/count/byte pressure always evicts oldest eligible data and terminates.
- LRU tracked-series eviction is deterministic when timestamps tie; use entity ID as the tie-breaker.
- Duplicate and out-of-order sequences are rejected without mutating counts or byte accounting.
- A sequence gap/reset closes the previous correlation segment.
- One diff containing more than the event cap records the correct omitted count without exceeding memory bounds.
- Repeated process churn does not leave empty series/index entries behind.
- After at least ten times every capacity has been appended, public stats still satisfy every configured maximum.

For the default configuration, add a production-only memory test/benchmark that fills and churns the recorder, forces GC on the recorder process, and records `Process.info(pid, :memory)`. Do not make hardware-sensitive memory or timing thresholds part of ordinary unit tests; CI asserts logical/estimated bounds.

## Chart downsampling tests

Use a pure downsampler that preserves the first/last points and bucket extrema in chronological order. Mailbox and memory charts must not average away a brief spike. Reduction counters should be converted to rate before downsampling, with reset/wrap represented as a gap rather than a negative spike.

Acceptance properties:

- Output is deterministic, chronological, and `<= max_points` for every input.
- Empty, singleton, exact-limit, repeated timestamp, constant, monotonic, and alternating-extrema series are handled.
- First and last valid points are retained when the budget allows.
- Each bucket's minimum and maximum are retained or represented by an explicitly documented equivalent.
- Missing samples create gap markers; the renderer never draws a continuous line across a collector failure/reset.
- No output value is invented outside the input range.
- A 450-point default series becomes at most 240 chart points.
- Serialized data for three selected-process series plus visible events remains below 128 KiB under default limits.

Property-style tests can generate deterministic pseudo-random series with a fixed seed; adding a property-test dependency is optional. Ordinary table tests remain the source of precise edge-case expectations.

## Collector non-overlap and failure recovery

Replace the application-environment fake runtime with a behaviour fixture that receives `owner:` through `runtime_options`. It sends `{:scan_started, sequence, task_pid}` and waits for an explicit release instruction containing `{:ok, snapshot}`, `{:error, reason}`, `:crash`, or no response for timeout testing.

Required tests:

- Ten refresh requests during one blocked scan produce exactly one follow-up scan.
- Periodic tick plus manual refresh during a scan still produces one follow-up.
- Successful scans commit strictly increasing sequences and append once to history.
- Runtime `{:error, reason}`, task crash, and task timeout do not alter the last good snapshot/history.
- A success immediately after each failure mode resumes recording and inserts an explicit gap/health event.
- A late task result or stale timeout message cannot overwrite a newer snapshot or duplicate history.
- Recorder unavailability does not crash or block the collector; the collector continues and reports a recorder gap after recovery.
- Collector restart does not make the surviving recorder correlate across the sequence reset.
- Recorder restart loses only bounded in-memory history by design; the collector continues and subscribers receive a resync/reset indication.
- Removing the final subscriber cancels future ticks in default mode and does not enqueue additional history. An in-flight scan may finish once, with behavior documented and tested.

Use `assert_receive`, `refute_receive`, monitors, and barrier messages only. Each spawned fixture has an explicit supervised cleanup path.

## Subscriber backpressure contract

Change notifications from unrestricted diff delivery to version invalidation with acknowledgement:

```text
collector -> subscriber: {:beam_console_snapshot, latest_sequence}
subscriber -> collector: ack(latest_sequence)
```

Per subscriber, retain at most one outstanding sequence and one replaceable pending sequence. If commits 2..100 occur before sequence 1 is acknowledged, do not send 99 messages; store only pending `100`. After acknowledging 1, send one notification for 100. Slow subscribers retrieve bounded updates with `since(last_seen)` or receive `{:resync, latest}` if history no longer covers their sequence.

Acceptance tests:

- After 100 commits with no acknowledgement, the stalled subscriber mailbox contains exactly one recorder notification.
- Collector subscriber state contains one outstanding and at most one pending sequence regardless of commit count.
- A matching acknowledgement sends only the newest pending sequence.
- Duplicate, stale, future, and cross-subscriber acknowledgements are ignored safely.
- A dead subscriber is removed through its monitor with no retained pending state.
- A fast subscriber receives monotonically increasing versions and can reproduce the current recorder view.
- A subscriber older than retained history receives a full resync, never an incomplete event chain presented as complete.
- One stalled subscriber does not delay scans, history eviction, or notifications to an independent fast subscriber.

## Performance benchmark design

Performance measurements run with `MIX_ENV=prod`; dev/test-mode numbers are invalid. Keep benchmarks outside normal CI timing gates and publish machine/OTP metadata with results.

Build a supervised process-farm fixture at 1k, 5k, 10k, and 20k live processes. Use lightweight waiting GenServers, with separate scenarios for flat processes, nested supervisors, churn, mailbox spikes, and maximum configured history. Run paired baseline/recorder trials long enough for warm-up and at least 100 completed scans.

Record:

- scan duration median/p95/p99 and timeout count;
- collector/recorder process memory before warm-up, at capacity, and after ten-capacity churn plus GC;
- total VM memory delta and history estimated bytes;
- collector/recorder reductions per scan;
- scheduler utilization/run-queue delta versus baseline;
- subscriber notification count and mailbox length for fast and stalled consumers;
- `since/2`, correlation, downsampling, and LiveView payload-build latency;
- encoded response size for default and worst allowed timeline/chart queries.

Provisional release gates on the documented reference machine:

- At 20k processes and default limits, scan p95 is below 1,000 ms and p99 below the 1,500 ms scan timeout.
- No scans overlap and normal-load timeout rate is 0 across 100 scans.
- Recorder incremental memory is at most 8 MiB estimated and 16 MiB actual after GC; total collector plus current/previous snapshots is reported separately.
- Ten-capacity churn leaves recorder memory within 20% of its at-capacity steady state after GC.
- Recorder append/correlation p95 is below 5 ms for a capped 500-event diff.
- A default process timeline query/downsample p95 is below 10 ms and emits at most 240 points per series.
- Worst allowed timeline/chart payload is at most 128 KiB encoded.
- Sampling increases average scheduler utilization by less than five percentage points in the idle process-farm workload.
- A stalled subscriber has one notification message after 100 commits; a fast subscriber has no version gaps.

These are acceptance hypotheses, not claims about the current implementation. If the scan cannot satisfy the timeout at 20k, reduce the supported default process cap or increase the interval based on measurements; do not silently raise the timeout and observer effect.

## Coverage and doctests

Keep the repository's 82% global line-coverage floor as a minimum and require at least 95% line coverage for new pure recorder/correlation/downsampling modules. More importantly, every state transition listed above must have an explicit test; line percentage does not substitute for concurrency/failure coverage.

Add deterministic doctests only for pure public APIs:

- creating/appending/querying a small bounded history;
- classifying a fully specified correlation evidence value;
- downsampling a small fixed point list;
- reporting omitted/range metadata.

Do not doctest collectors, timers, PIDs, LiveViews, wall-clock timestamps, or host integration. Continue running all declared doctests from a root ExUnit module.

Required verification:

```text
rtk mix compile --warnings-as-errors
rtk mix format --check-formatted
rtk mix test --cover
rtk mix quality
```

## Phoenix and plain-Elixir compatibility

### Phoenix host

Extend the demo/LiveView tests to verify:

- the timeline starts with a clear recording-start/reset state;
- selecting a process renders bounded charts and correlated events using stable DOM IDs;
- a restart fixture updates without sleeps and preserves selected/tombstone identity;
- sequence gaps trigger full resync and visible coverage state;
- chart-range and point-count input is clamped server-side;
- a stalled LiveView cannot grow collector work/history;
- package assets remain self-contained and no host asset pipeline changes are required.

Run demo compile, format, and tests through its path dependency.

### Plain Elixir host

Turn `fixtures/plain_host` into a runtime smoke test, not compile-only. With Phoenix/LiveView/Jason absent, start the host, subscribe, release/await a snapshot notification, query recorder history, acknowledge the sequence, unsubscribe, and stop cleanly. Assert no `BeamConsoleWeb` module is required or loaded for core recording APIs.

Run both `MIX_ENV=test` tests and `MIX_ENV=prod` warnings-as-errors compilation for the fixture. Keep all core recorder modules free of Phoenix structs, PubSub, JSON protocols, and endpoint configuration.

### Version matrix

The package declares Elixir `~> 1.17`; add a small compatibility matrix rather than testing only the current toolchain:

- Elixir 1.17 with its supported OTP 26/27 pairing;
- Elixir 1.18 with OTP 27;
- Elixir 1.19 with OTP 28;
- Phoenix-enabled root/demo on the minimum and current supported Phoenix 1.8 versions;
- plain-host fixture on every Elixir/OTP row.

If only Phoenix 1.8.9+ is supported, document that boundary and make the dependency constraint/tests agree. Compatibility jobs can omit expensive static analysis and performance benchmarks.

## Measurable acceptance checklist

- [ ] All history/event/series/point/byte caps hold after ten times capacity.
- [ ] Correlation table passes, including dynamic-supervisor ambiguity and partial/gapped samples.
- [ ] Downsampling emits at most 240 ordered points per series and preserves tested extrema/gaps.
- [ ] Ten concurrent refreshes produce one active plus one coalesced scan, with no sleeps.
- [ ] Error, crash, timeout, collector restart, and recorder restart preserve documented last-good/reset semantics.
- [ ] A stalled subscriber has exactly one notification after 100 commits and catches up with one coalesced notification or resync.
- [ ] Root coverage remains at least 82%; new pure recorder modules reach at least 95% line coverage and all state transitions have named tests.
- [ ] Pure API doctests pass without runtime/time dependencies.
- [ ] Phoenix demo tests and plain-host runtime smoke tests pass; plain host has no Phoenix dependencies.
- [ ] Elixir/OTP minimum and current compatibility rows pass.
- [ ] Production benchmark results meet or explicitly revise the stated 20k-process, memory, latency, payload, and scheduler-utilization gates before release.

## Residual risks

- `Process.info/2` and application attribution across 20k processes may dominate overhead regardless of recorder efficiency. Only production-mode measurement can settle the default cap/cadence.
- Live Erlang term memory is not exactly predicted by serialized size. Enforce both logical/estimated caps and measure actual process memory.
- Supervisor child identity is not universally stable, especially for dynamic supervisors. Conservative non-correlation is preferable to a persuasive but false restart story.
- In-memory history disappears on VM/recorder restart and is unavailable before the first subscriber under the safe default. The UI and documentation must state both limits plainly.
