defmodule BeamConsole.Lifecycle.RefreshRequest do
  @moduledoc """
  Runs one bounded reconciliation callback without blocking its recorder.

  A small guardian monitors the recorder and owns the callback process. This
  couples callback lifetime to its owner while allowing timeout cancellation to
  wait for actual process termination before another request starts.
  """

  @type outcome :: :ok | :error

  @doc "Starts a monitored refresh request owned by `owner`."
  @spec start(pid(), (-> term())) :: {pid(), reference()}
  def start(owner, requester) when is_pid(owner) and is_function(requester, 0) do
    spawn_monitor(fn -> guard(owner, requester) end)
  end

  @doc "Requests cancellation without unlinking the callback from its guardian."
  @spec cancel(pid()) :: :ok
  def cancel(guardian) when is_pid(guardian) do
    send(guardian, :cancel)
    :ok
  end

  defp guard(owner, requester) do
    Process.flag(:trap_exit, true)
    owner_ref = Process.monitor(owner)
    guardian = self()

    callback =
      spawn_link(fn ->
        send(guardian, {:refresh_callback_result, self(), invoke(requester)})
      end)

    guard_loop(owner, owner_ref, callback, nil)
  end

  defp guard_loop(owner, owner_ref, callback, outcome) do
    receive do
      {:refresh_callback_result, ^callback, next_outcome} ->
        guard_loop(owner, owner_ref, callback, next_outcome)

      {:EXIT, ^callback, :normal} ->
        send(owner, {__MODULE__, self(), outcome || :error})

      {:EXIT, ^callback, _reason} ->
        send(owner, {__MODULE__, self(), :error})

      {:DOWN, ^owner_ref, :process, ^owner, _reason} ->
        stop_callback(callback)

      :cancel ->
        stop_callback(callback)
    end
  end

  defp stop_callback(callback) do
    Process.exit(callback, :kill)

    receive do
      {:EXIT, ^callback, _reason} -> :ok
    end
  end

  defp invoke(requester) do
    try do
      case requester.() do
        {:error, _reason} -> :error
        _result -> :ok
      end
    catch
      _kind, _reason -> :error
    end
  end
end
