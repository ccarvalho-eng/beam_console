# BeamConsole

[![CI](https://github.com/ccarvalho-eng/beam_console/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/ccarvalho-eng/beam_console/actions/workflows/ci.yml)
[![Security](https://github.com/ccarvalho-eng/beam_console/actions/workflows/security.yml/badge.svg?branch=main)](https://github.com/ccarvalho-eng/beam_console/actions/workflows/security.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/beam_console.svg)](https://hex.pm/packages/beam_console)
[![HexDocs](https://img.shields.io/badge/hex-docs-714a9f.svg)](https://hexdocs.pm/beam_console)
[![License](https://img.shields.io/hexpm/l/beam_console.svg)](https://github.com/ccarvalho-eng/beam_console/blob/main/LICENSE)

BeamConsole is an embeddable, read-only process flight recorder and process map for Phoenix and BEAM applications. It makes supervision, process relationships, lifecycle changes, per-process activity, and node-wide runtime health visible without application-specific instrumentation.

<img width="1623" height="969" alt="Screenshot 2026-08-27 at 8 30 16 PM" src="https://github.com/user-attachments/assets/d628095e-ba57-4a5d-855b-2302fb30bf04" />

## Installation

Add BeamConsole to a Phoenix application:

```elixir
def deps do
  [
    {:beam_console, "~> 0.3.0"}
  ]
end
```

Import and mount it from the host router. The route is disabled outside development by default.

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  import BeamConsole.Router

  scope "/" do
    pipe_through :browser
    beam_console "/beam"
  end
end
```

Visit `/beam` after restarting the host application. A different Phoenix server port can be supplied through the host application's usual endpoint environment configuration; BeamConsole does not own the HTTP listener.

### Plain Elixir applications

The dependency also starts its bounded collector and recorder in applications without Phoenix. Those applications can consume normalized snapshots and recorder queries directly; the embedded web interface is available only when Phoenix and LiveView are installed by the host.

```elixir
{:ok, latest_snapshot} = BeamConsole.subscribe()
:ok = BeamConsole.refresh()

receive do
  {:beam_console_snapshot, sequence} ->
    snapshot = BeamConsole.latest_snapshot()
    :ok = BeamConsole.acknowledge(sequence)
end

status = BeamConsole.Recorder.status()
events = BeamConsole.Recorder.events(limit: 100)
```

Call `BeamConsole.unsubscribe/0` when a long-lived manual subscriber no longer needs updates. Subscribers are also removed automatically when their process terminates.

## What it shows

- Process Map: a stable, focused supervision graph with optional process links and monitors, plus a searchable process explorer.
- Lifecycle: observed process starts, terminations, and replacement correlations with explicit evidence and coverage language.
- Activity: reductions per second, mailbox growth, memory movement, and ranked process movers.
- Runtime: BEAM memory categories, run queue, atom count and utilization, runtime inventory, collector duration, applications, ETS tables, and connected-node inventory.
- Inspector: allowlisted process, application, and node details. Process relationships are clickable when their target is present in the latest sample.

Applications are grouped into host, dependencies, OTP, and tooling categories. Every tree branch can be collapsed and its state remains stable while LiveView updates.

## Recording model

The default `:subscribers` mode records while at least one BeamConsole page is connected. The header control pauses and resumes recording explicitly. Retained samples remain bounded by age, item count, chart point count, and estimated bytes.

To begin recording when the application starts, even before anyone opens the page:

```elixir
config :beam_console, :recorder,
  mode: :always
```

In `:always` mode, sampling and lifecycle recording remain active with zero connected pages. The collector and recorder both derive their demand from this mode, so ordinary subscriber disconnects and supervised collector or recorder restarts do not silently return recording to subscriber-only behavior. An explicit operator pause still takes precedence until recording is resumed.

Lifecycle recording is observational rather than a lossless trace. Sampling gaps, partial supervision traversal, process limits, watch limits, and dropped history are surfaced in the interface instead of being hidden.

## Access control

BeamConsole deliberately does not ship a production authentication system. The host application owns exposure, authentication, and authorization. Do not expose runtime metadata publicly.

Use the host browser pipeline for plug-based authorization. For LiveView authorization, pass existing `on_mount` hooks to the embedded live session:

```elixir
beam_console "/beam",
  enabled: true,
  on_mount: [{MyAppWeb.UserAuth, :ensure_admin}]
```

When an authorization hook needs host session values, merge a static string-keyed map or a session callback. The callback receives the connection as its first argument.

```elixir
beam_console "/beam",
  enabled: true,
  session: {MyAppWeb.BeamConsoleSession, :build, []},
  on_mount: [{MyAppWeb.UserAuth, :ensure_admin}]

defmodule MyAppWeb.BeamConsoleSession do
  def build(conn) do
    %{"current_user_id" => Plug.Conn.get_session(conn, :current_user_id)}
  end
end
```

Host authorization hooks run before BeamConsole's internal mount hook. Reserved transport and mount keys cannot be overridden by the host session callback.

LiveView sessions are signed but not encrypted. Return only the minimal identifiers and authorization context required by the hook; never return secrets, credentials, or the complete host session.

### Router options

| Option | Default | Purpose |
| --- | --- | --- |
| `:enabled` | `Mix.env() == :dev` | Controls whether BeamConsole routes are mounted. |
| `:as` | `:beam_console` | Names the LiveView session and route helpers. Use a distinct atom for each mount. |
| `:on_mount` | `[]` | Adds host authentication or authorization hooks before BeamConsole's hook. |
| `:session` | `nil` | Merges a string-keyed map or `{module, function, arguments}` callback result into the LiveView session. |
| `:socket_path` | `"/live"` | Selects the host endpoint's LiveView socket path. It must match the endpoint configuration. |
| `:transport` | `"websocket"` | Selects `"websocket"` or `"longpoll"`. The endpoint must enable the same transport. |

Endpoint URL paths and Phoenix forwarding prefixes from `conn.script_name` are applied automatically to navigation and asset paths. Set `:socket_path` to the endpoint socket's externally reachable path when a proxy also prefixes WebSocket or long-poll requests.

For example, a host that exposes a long-poll-only socket at `/internal/live` mounts BeamConsole with matching connection settings:

```elixir
beam_console "/beam",
  socket_path: "/internal/live",
  transport: "longpoll"
```

## Configuration

Collector settings are bounded and reject unknown keys:

```elixir
config :beam_console, :collector,
  interval: 2_000,
  scan_timeout: 1_500,
  process_limit: 20_000,
  supervisor_limit: 2_000,
  relationship_limit: 200
```

Recorder retention can also be tuned explicitly:

```elixir
config :beam_console, :recorder,
  retention_ms: 15 * 60_000,
  frame_limit: 450,
  event_limit: 1_000,
  chart_points_limit: 240,
  byte_limit: 8 * 1_024 * 1_024
```

## Safety boundary

BeamConsole does not fetch process messages, dictionaries, stacktraces, binaries, or arbitrary process state. It does not use `:sys`, tracing, remote RPC, or process mutation. Browser inputs are matched against fixed allowlists and opaque entity IDs are revalidated against the latest snapshot.

## Compared with Observer and Phoenix LiveDashboard

Observer is a broad Erlang runtime desktop tool. Phoenix LiveDashboard is a Phoenix-focused operational dashboard built around metrics and framework integrations. BeamConsole is narrower: it is an embeddable, process-first tool focused on supervision topology, observed crash-and-replacement history, process relationships, and bounded activity over time.

## Demo

The database-free sample application lives in `examples/demo` and uses BeamConsole through a path dependency.

```text
cd examples/demo
mix deps.get
mix phx.server
```

Visit `/lab` for deterministic sample controls or `/beam` for BeamConsole.

## License

BeamConsole is available under the Apache License 2.0. See `LICENSE` and `THIRD_PARTY_NOTICES`.
