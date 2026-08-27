# Process Flight Recorder scratchpad

## Product decision

BeamConsole should become the process-first dashboard for understanding the shape and recent behavior of a running BEAM system. Its differentiator is a bounded, honest **Process Flight Recorder**: supervised-process exits, observed replacements, topology changes, and process-linked activity over a short in-memory window.

This complements rather than copies the existing tools:

- LiveDashboard remains the broad Phoenix/runtime performance dashboard.
- Observer remains the deep local VM inspection tool.
- BeamConsole explains which process belongs where, what changed recently, and what evidence supports that conclusion.

Do not claim that no other tool has a feature. Describe the concrete capability and evidence boundary.

## User requirements carried forward

- Embeddable with a router macro and no host asset-pipeline work.
- Phoenix demo remains the primary integration fixture; plain Elixir remains supported.
- Process Map, Lifecycle, Activity, and Runtime tabs.
- Nodes, applications, supervisors, processes, links, monitors, and safe details remain clickable.
- Runtime tree uses native collapsible folder branches and preserves disclosure state across patches.
- Applications are grouped into useful categories, with deterministic inference and host overrides.
- Theme control matches Ancient Stones: system/light/dark segmented switcher, persisted browser-side, after refresh.
- Graph positions remain stable for small live changes; a materially different initial topology is laid out once after its container settles.
- Public modules/functions have meaningful docs and typespecs; deterministic pure APIs get doctests.
- Code remains functional, modular, Phoenix-optional, and readable from the file tree.
- Ancient Stones-equivalent quality, CI, security, license, coverage, and packaging checks remain required.

## Evidence and wording contract

- An established local process monitor can prove a termination and provide an exit reason.
- A normal supervisor's stable `(supervisor PID, child spec ID)` slot can strongly support “replacement observed.”
- This does not prove why a restart occurred or which process initiated a restart cascade.
- DynamicSupervisor children have `:undefined` child IDs. Their exit and later appearance remain separate events in the first release.
- Snapshot differences are sampled observations, never a lossless trace.
- `:noconnection` is a connection event, not proof that a remote process died.
- The UI uses “observed,” “recording since,” “replacement observed,” and explicit coverage/gap language.

## Safety boundary

- Local node only for lifecycle monitoring in this plan.
- Monitor only local supervised PIDs discovered by the collector.
- Never call a supervisor from a `:DOWN` handler.
- Never decode browser entity IDs back into PIDs.
- Never store raw exit terms, PIDs, application paths, full snapshots, or arbitrary runtime terms in history.
- Sanitize and bound all labels/reason summaries before retention.
- Read-only: no kill, restart, tracing, process manipulation, or `:sys.get_state/1` expansion.
- Recording is lazy while at least one console subscriber exists; the UI states when it began.

## Default bounds to validate

| Resource | Default |
|---|---:|
| Retention | 15 minutes |
| Lifecycle events | 1,000 |
| Summary frames | 450 |
| Watched local supervised PIDs | 5,000 |
| Watch changes per reconciliation | 500 |
| Pending stable-slot correlation | 30 seconds |
| Tracked process series | 32 |
| Points per process series | 450 |
| Total process points | 14,400 |
| Chart points per series | 240 |
| Series per chart | 6 |
| Charts per tab update | 4 |
| Timeline query result | 500 events |
| Estimated recorder state | 8 MiB |
| Encoded visible payload | 128 KiB |

All limits are configuration values with validation and hard production enforcement. Benchmark results may lower supported caps or lengthen the sampling interval; they must not silently weaken the observer-overhead boundary.

## Architecture decisions

- Keep one URL-driven `BeamConsoleWeb.ConsoleLive` for shared subscription and selection, but reduce it to lifecycle callbacks and effects.
- Use four live actions/routes targeting the same LiveView.
- Long-lived sockets do not retain `%BeamConsole.Snapshot{}` or chart point arrays.
- Presenters are pure transformations; function components render their bounded view models.
- Add a separate `BeamConsole.Recorder`/lifecycle GenServer so monitor traffic does not share the collector mailbox.
- The collector supplies private server-side supervision observations; the recorder never traverses supervisors independently.
- Store compact frames/events, not historical snapshots.
- Use version invalidation plus acknowledgements so a stalled subscriber has one outstanding and one replaceable pending notification.
- Use a small native SVG/canvas chart hook first; add a chart dependency only if accessibility or interaction materially improves.
- Keep authored JS/CSS modular and bundle one committed, self-contained distribution asset for Hex consumers.

## Application categorization

Default categories:

1. Host application
2. Dependencies
3. Erlang/OTP
4. Tooling
5. Unattributed processes

Classification precedence:

1. Explicit application-to-category override.
2. Validated server-side classifier callback.
3. Explicit host application list.
4. BeamConsole/tooling designation.
5. OTP provenance.
6. Inferred non-dependency top-level application.
7. Remaining non-OTP dependency.
8. Unattributed virtual group.

Inference is presented as a useful default, not exact ownership. Host configuration can make it exact.

## Deferred intentionally

- DynamicSupervisor restart pairing heuristics.
- Cross-node monitors and merged distributed timelines.
- Persistence or history across VM restarts.
- Message tracing, flame graphs, raw message/state inspection.
- Exact supervisor-strategy causality.
- Production authentication and authorization policy.
- Generic telemetry dashboards already served by LiveDashboard.

## Research

- `research/otp-lifecycle.md`
- `research/dashboard-architecture.md`
- `research/testing-and-performance.md`
- `reviews/api-docs.md`

