# BeamConsole

BeamConsole is an embeddable, read-only process map for Phoenix and BEAM applications.

The first development slice inspects the local BEAM node, shows connected-node inventory, applications, supervision relationships, processes, and safe process details. Runtime changes are sampled, so lifecycle events are described as observed rather than lossless.

## Phoenix installation

```elixir
def deps do
  [
    {:beam_console, path: "../beam_console"}
  ]
end
```

Mount the console inside a development-only router block:

```elixir
if Application.compile_env(:my_app, :beam_console_enabled, false) do
  scope "/" do
    pipe_through :browser
    beam_console "/beam", enabled: true
  end
end
```

The host application owns authentication and authorization. Do not expose process metadata publicly.

## Demo

The database-free sample application lives in `examples/demo` and uses BeamConsole through a path dependency.

```text
cd examples/demo
mix deps.get
mix phx.server
```

Then visit `/lab` for deterministic sample controls or `/beam` for BeamConsole.

## Interface

The console provides a stable process map, a collapsible runtime tree, process
search, and an allowlisted inspector. The light/dark theme follows the system
preference on first use and remembers an explicit selection in the browser.

## Current safety boundary

BeamConsole does not fetch process messages, dictionaries, stacktraces, binaries, or arbitrary state. It does not use `:sys`, tracing, remote RPC, or process mutation.
