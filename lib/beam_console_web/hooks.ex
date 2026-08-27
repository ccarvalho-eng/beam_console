if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule BeamConsoleWeb.Hooks do
    @moduledoc """
    Loads host-owned routing and transport settings into the embedded LiveView.
    """

    import Phoenix.Component, only: [assign: 3]

    @doc "Initializes the route prefix, socket path, and transport from the signed session."
    @spec on_mount(atom(), map(), map(), Phoenix.LiveView.Socket.t()) ::
            {:cont, Phoenix.LiveView.Socket.t()}
    def on_mount(:default, _params, session, socket) do
      socket =
        socket
        |> assign(:prefix, Map.fetch!(session, "prefix"))
        |> assign(:live_path, Map.fetch!(session, "live_path"))
        |> assign(:live_transport, Map.fetch!(session, "live_transport"))

      {:cont, socket}
    end
  end
end
