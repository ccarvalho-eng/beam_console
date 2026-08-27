defmodule BeamConsoleDemoWeb.LabLive do
  use BeamConsoleDemoWeb, :live_view

  alias BeamConsoleDemo.ProcessLab

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Process laboratory")
     |> assign(:result, nil)
     |> assign(:lab, ProcessLab.snapshot())}
  end

  @impl true
  def handle_event("start-child", _params, socket) do
    {:noreply, run_action(socket, "Started a dynamic child", &ProcessLab.start_dynamic_child/0)}
  end

  def handle_event("stop-child", _params, socket) do
    {:noreply, run_action(socket, "Stopped a dynamic child", &ProcessLab.stop_dynamic_child/0)}
  end

  def handle_event("restart-processor", _params, socket) do
    {:noreply,
     run_action(socket, "Requested a supervised restart", &ProcessLab.restart_processor/0)}
  end

  def handle_event("grow-mailbox", _params, socket) do
    {:noreply, run_action(socket, "Queued bounded mailbox work", &ProcessLab.grow_mailbox/0)}
  end

  def handle_event("spawn-tasks", _params, socket) do
    {:noreply,
     run_action(socket, "Spawned short-lived supervised tasks", &ProcessLab.spawn_short_tasks/0)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div id="process-lab" class="space-y-8">
        <div class="space-y-3">
          <p class="text-sm font-semibold uppercase tracking-[0.2em] text-violet-600">
            BeamConsole demo
          </p>
          <h1 class="text-3xl font-semibold tracking-tight">Process laboratory</h1>
          <p class="text-base text-zinc-600">
            Change a small, bounded supervision tree here, then watch the observations at <.link
              href="/beam"
              class="font-semibold text-violet-700 hover:text-violet-900"
            >
              /beam
            </.link>.
          </p>
        </div>

        <dl class="grid gap-3 sm:grid-cols-3">
          <div class="rounded-xl border border-zinc-200 bg-white p-4">
            <dt class="text-xs uppercase tracking-wide text-zinc-500">Processor</dt>
            <dd id="processor-pid" class="mt-2 font-mono text-sm">{@lab.processor.pid}</dd>
          </div>
          <div class="rounded-xl border border-zinc-200 bg-white p-4">
            <dt class="text-xs uppercase tracking-wide text-zinc-500">Queue mailbox</dt>
            <dd id="queue-mailbox" class="mt-2 text-2xl font-semibold">
              {@lab.queue_worker.mailbox}
            </dd>
          </div>
          <div class="rounded-xl border border-zinc-200 bg-white p-4">
            <dt class="text-xs uppercase tracking-wide text-zinc-500">Dynamic children</dt>
            <dd id="dynamic-count" class="mt-2 text-2xl font-semibold">{@lab.dynamic_children}</dd>
          </div>
        </dl>

        <div class="grid gap-3 sm:grid-cols-2">
          <button id="start-child" class="btn btn-primary" phx-click="start-child">Start child</button>
          <button id="stop-child" class="btn" phx-click="stop-child">Stop child</button>
          <button id="restart-processor" class="btn" phx-click="restart-processor">
            Restart processor
          </button>
          <button id="grow-mailbox" class="btn" phx-click="grow-mailbox">Grow mailbox</button>
          <button id="spawn-tasks" class="btn sm:col-span-2" phx-click="spawn-tasks">
            Spawn short-lived tasks
          </button>
        </div>

        <p :if={@result} id="lab-result" class="rounded-xl bg-violet-50 p-4 text-violet-900">
          {@result}
        </p>
      </div>
    </Layouts.app>
    """
  end

  defp run_action(socket, success_message, action) do
    result =
      case action.() do
        :ok -> success_message
        {:ok, _pid} -> success_message
        {:error, :not_found} -> "No dynamic child is currently running"
        {:error, reason} -> "Action unavailable: #{inspect(reason)}"
      end

    socket
    |> assign(:result, result)
    |> assign(:lab, ProcessLab.snapshot())
  end
end
