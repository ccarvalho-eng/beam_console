defmodule BeamConsoleWeb.Console.RuntimeClientsTest do
  use ExUnit.Case, async: true

  alias BeamConsoleWeb.Console.CollectorClient
  alias BeamConsoleWeb.Console.RecorderClient
  alias BeamConsoleWeb.Console.RecordingControlClient

  defmodule WedgedServer do
    use GenServer

    def start_link(_options) do
      GenServer.start_link(__MODULE__, :ok)
    end

    @impl GenServer
    def init(state) do
      {:ok, state}
    end

    @impl GenServer
    def handle_call(_request, _from, state) do
      {:noreply, state}
    end
  end

  test "collector calls return a typed timeout without imposing the default call wait" do
    server = start_supervised!(WedgedServer)
    started_at = System.monotonic_time(:millisecond)

    assert {:error, :timeout} = CollectorClient.status(server, 20)
    assert System.monotonic_time(:millisecond) - started_at < 250
  end

  test "recorder calls return a typed timeout without imposing the default call wait" do
    server = start_supervised!(WedgedServer)
    started_at = System.monotonic_time(:millisecond)

    assert {:error, :timeout} = RecorderClient.status(server, 20)
    assert System.monotonic_time(:millisecond) - started_at < 250
  end

  test "recording control calls return a typed timeout without imposing the default call wait" do
    server = start_supervised!(WedgedServer)
    started_at = System.monotonic_time(:millisecond)

    assert {:error, :timeout} = RecordingControlClient.status(server, 20)
    assert {:error, :timeout} = RecordingControlClient.subscribe(server, 20)
    assert System.monotonic_time(:millisecond) - started_at < 250
  end

  test "dead runtime services remain distinguishable from timeouts" do
    server = start_supervised!(WedgedServer)
    reference = Process.monitor(server)
    GenServer.stop(server)
    assert_receive {:DOWN, ^reference, :process, ^server, :normal}

    assert {:error, :unavailable} = CollectorClient.status(server, 20)
    assert {:error, :unavailable} = RecorderClient.status(server, 20)
    assert {:error, :unavailable} = RecordingControlClient.status(server, 20)
    assert {:error, :unavailable} = RecordingControlClient.subscribe(server, 20)
  end
end
