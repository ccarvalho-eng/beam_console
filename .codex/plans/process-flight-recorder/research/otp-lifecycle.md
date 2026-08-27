# OTP lifecycle research: Process Flight Recorder

## Conclusion

A useful, low-intrusion recorder is feasible without tracing, but its honest boundary is:

> Record local `:DOWN` evidence for supervised PIDs discovered while BeamConsole is active, then correlate a new PID to the same stable supervisor child slot when OTP exposes one.

This can provide real exit reasons and strong static-supervisor replacement evidence. It cannot provide lossless process history, identify the initiating failure in `one_for_all` or `rest_for_one` cascades, or reliably pair DynamicSupervisor children across PIDs. Those distinctions must appear in the event model and UI.

## What OTP can prove

`Process.monitor(pid)` is unidirectional and does not link to or alter the target. A process monitor fires once and sends `{:DOWN, ref, :process, pid, info}`. `info` is the exit reason when the monitor observed termination, `:noproc` when the process did not exist when the monitor request reached it, or `:noconnection` when a remote connection was lost. The monitor request itself is asynchronous, so a PID found during traversal can exit before monitoring is established. [ERTS `monitor/2`](https://www.erlang.org/docs/27/apps/erts/erlang.html#monitor-2)

For a normal `Supervisor`, `which_children/1` returns the configured child ID and current PID, including the transitional values `:restarting` and `:undefined`. The child ID identifies the child specification internally and remains the useful logical slot across a normal restart. [OTP `supervisor`](https://www.erlang.org/doc/apps/stdlib/supervisor.html#which_children-1)

Therefore BeamConsole can state, with strong evidence:

- “PID X terminated with reason R” only when an established local monitor returns an actual reason;
- “child slot S changed from PID X to PID Y” when the same local supervisor PID and stable child ID are later observed with Y;
- “replacement observed” rather than “supervisor restarted X because of R.” A manual restart and collateral restarts under `one_for_all` or `rest_for_one` produce the same visible slot transition. OTP documents that those strategies terminate and restart siblings, so receipt order must not be interpreted as causality. [Supervisor restart strategies](https://www.erlang.org/doc/system/sup_princ.html#restart-strategy)

Child restart policy can be read for normal supervisors with `Supervisor.get_childspec/2`, but that is another synchronous supervisor call and predicts policy rather than proving what happened. It is not necessary for the first recorder and must never run in the `:DOWN` handler.

## What OTP cannot prove

### DynamicSupervisor replacement identity

`DynamicSupervisor.which_children/1` always returns `:undefined` as the child ID. Multiple children commonly have identical type/module metadata, so `(parent, module)` is not an identity. The API also warns that enumerating a very large dynamic supervisor under low-memory conditions can bring the system down. [Elixir `DynamicSupervisor.which_children/1`](https://elixir.hexdocs.pm/DynamicSupervisor.html#which_children/1)

The first version should record monitored dynamic-child exits and newly observed dynamic PIDs as separate events. It should not pair them as replacements. A later heuristic may emit “possible replacement” only when exactly one disappearance and one appearance share a bounded fingerprint and time window, but that remains low-confidence and can confuse an unrelated stop/start with a restart.

### Lossless history

Discovery remains sampled. A process that starts and exits between successful supervision traversals is invisible. A PID that exits between traversal and `monitor/2` produces `:noproc`, which confirms a coverage miss but not its exit reason. Rapid repeated crashes can replace a child several times before BeamConsole observes an intermediate PID.

Monitoring supervisors as well as workers does not create global event order. Signals originating from different processes have no total ordering guarantee. A supervisor failure can produce many child `:DOWN` messages, but their receive order is not a causal sequence.

### Remote death

Remote process monitors exist, but `:noconnection` means the connection was lost and the process may still be alive. Node-down delivery also has ordering subtleties, and Erlang monotonic clocks from different runtime instances are not directly comparable. [ERTS monitor semantics](https://www.erlang.org/docs/27/apps/erts/erlang.html#monitor-2), [`net_kernel:monitor_nodes/2`](https://www.erlang.org/docs/25/man/net_kernel.html#monitor_nodes-2)

The recorder should remain local-only alongside the current local adapter. Future distributed support should run one recorder on each BEAM node and aggregate bounded, node-sequenced events. It should not create thousands of cross-node monitors from the web host.

## Current repository implications

The existing architecture is a good fit: `BeamConsole.Collector` already owns one lazy, non-overlapping snapshot loop, and `BeamConsole.Runtime.Supervision` already discovers supervised children. The recorder should consume those completed traversal observations and must not perform a second traversal.

Two model gaps must be resolved before lifecycle work:

1. `Runtime.Supervision` currently builds an edge ID from `{node, parent_pid, child_key}`. Every DynamicSupervisor child has child key `:undefined`, so multiple dynamic children under one parent overwrite each other in the edge map. Dynamic edges require PID-disambiguated identity.
2. `SupervisionEdge` contains sanitized IDs but not the server-side `(supervisor_pid, child_key, child_pid)` observation needed to install a monitor and retain a stable slot. Add a private lifecycle observation to the snapshot; never decode a browser entity ID back into a PID.

Also, `Diff` compares edge key sets. A static slot keeps the same edge key when its PID changes, so current `edge_added`/`edge_removed` fields cannot express replacement. Process start/stop diffs remain sampled evidence, not slot correlation.

## Recommended design boundary

Add a separate `BeamConsole.Lifecycle.Recorder` GenServer supervised beside the collector. Do not put potentially thousands of lifecycle `:DOWN` messages in the collector mailbox, which already handles scan-task and subscriber monitors.

On every successful local snapshot, the collector sends the recorder bounded server-only observations shaped like:

```elixir
%{
  slot_id: opaque_id,
  slot_kind: :stable | :dynamic,
  supervisor_pid: pid,
  child_pid: pid,
  child_type: :worker | :supervisor,
  modules: bounded_modules,
  snapshot_sequence: sequence
}
```

The recorder reconciles PIDs, installs at most one monitor per PID, and stores monitor metadata keyed by reference. Its `:DOWN` handler only timestamps, classifies/sanitizes the reason, updates bounded state, and schedules reconciliation; it never calls a supervisor. A later completed snapshot closes a pending static slot transition when the same `(supervisor_pid, child_id)` points to a new PID.

Use these evidence semantics instead of an undifferentiated confidence score:

| Event | Evidence | UI wording |
|---|---|---|
| Actual local `:DOWN` reason | `:monitor` / `:direct` | “Process terminated” |
| `:noproc` after watch request | `:monitor` / `:missed` | “Process disappeared before recording began” |
| Same stable slot, new PID | `:slot_reconciliation` / `:strong` | “Replacement observed” |
| Snapshot-only PID difference | `:snapshot_diff` / `:sampled` | “Start/stop observed between samples” |
| Dynamic child old/new pairing | unsupported initially | Show separate exit and appearance |
| Remote `:noconnection` | `:connection` | “Node connection lost,” never “process died” |

Every event should include node, node-local sequence, receive timestamp, source, certainty, sanitized reason category, and related snapshot sequences. Store no raw exit term. Keep a bounded reason summary only after depth/length limiting and redaction; exit reasons can contain large or sensitive application terms.

## Safety and overhead budget

There is no portable documented byte cost per monitor, so limits must be explicit and benchmarked rather than justified by a guessed constant.

Recommended defaults for the first implementation:

- activate only while at least one BeamConsole subscriber is connected; offer explicit `:always` mode later;
- monitor supervised local PIDs only, never the global `Process.list/0` population;
- cap active watches at 5,000 and expose `watched / eligible / omitted` coverage;
- cap monitor additions/removals per reconciliation at 500 to avoid bursty setup work;
- retain 1,000 sanitized events or five minutes, whichever is smaller, plus a dropped-event counter;
- retain pending stable-slot exits for 30 seconds, then emit an unpaired termination;
- keep watches across partial supervision snapshots and remove them only after two complete reconciliations omit a still-live PID;
- never call `which_children/1` from the recorder. Reuse the collector traversal and skip/mark oversized branches before materializing them where possible;
- process `:DOWN` in O(1), keep the recorder mailbox observable, and surface overload/coverage degradation rather than silently claiming completeness.

Default lazy activation means the UI must say “Recording since …”; BeamConsole cannot show events from before the first subscriber. An always-on recorder is an explicit operational tradeoff, not the zero-config default.

## Concrete first-release boundary

Ship local, supervised-child monitoring with sanitized direct `:DOWN` reasons, a bounded in-memory event window, and strong replacement correlation only for stable child IDs under the same still-running normal supervisor. Include explicit recording start time and watch coverage.

Defer DynamicSupervisor replacement pairing, supervisor-strategy causality, restart-policy inspection, remote monitors, cross-node timelines, tracing, persistence, and raw exit reasons. This boundary is meaningfully more informative than sampled diffs while preserving BeamConsole's read-only, no-tracing safety contract.
