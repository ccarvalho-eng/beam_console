if Code.ensure_loaded?(Phoenix.Router) and Code.ensure_loaded?(Phoenix.LiveView.Router) do
  defmodule BeamConsole.Router do
    @moduledoc """
    Router helpers for mounting BeamConsole inside a Phoenix application.

    The host owns authentication, authorization, endpoint configuration, and
    deployment exposure.
    """

    @default_options [as: :beam_console, socket_path: "/live", transport: "websocket"]
    @transports ~w(longpoll websocket)

    @doc "Imports the `beam_console/1` and `beam_console/2` router macros."
    defmacro __using__(_options) do
      quote do
        import BeamConsole.Router, only: [beam_console: 1, beam_console: 2]
      end
    end

    @doc """
    Mounts the BeamConsole LiveView and its self-contained assets.

    The macro belongs inside a Phoenix router. The host application is
    responsible for placing the route behind an appropriate browser pipeline
    and any required authentication or authorization.
    """
    defmacro beam_console(path, options \\ []) do
      quote bind_quoted: [path: path, options: options] do
        enabled = Keyword.get(options, :enabled, Mix.env() == :dev)

        if enabled do
          prefix = Phoenix.Router.scoped_path(__MODULE__, path)

          {session_name, session_options, route_options} =
            BeamConsole.Router.__options__(prefix, options)

          scope path, alias: false, as: false do
            import Phoenix.LiveView.Router, only: [live: 4, live_session: 3]

            live_session session_name, session_options do
              get("/assets/css/:digest", BeamConsoleWeb.Assets, :css)
              get("/assets/js/:digest", BeamConsoleWeb.Assets, :js)
              get("/assets/phoenix/:digest", BeamConsoleWeb.Assets, :phoenix)
              get("/assets/live-view/:digest", BeamConsoleWeb.Assets, :live_view)
              get("/assets/cytoscape/:digest", BeamConsoleWeb.Assets, :cytoscape)
              live("/", BeamConsoleWeb.ConsoleLive, :process_map, route_options)
              live("/lifecycle", BeamConsoleWeb.ConsoleLive, :lifecycle, route_options)
              live("/activity", BeamConsoleWeb.ConsoleLive, :activity, route_options)
              live("/runtime", BeamConsoleWeb.ConsoleLive, :runtime, route_options)
            end
          end
        end
      end
    end

    @spec __options__(String.t(), keyword()) :: {atom(), keyword(), keyword()}
    @doc "Builds validated LiveView session and route options for the router macro."
    def __options__(prefix, options) do
      options = Keyword.merge(@default_options, options)
      validate_options!(options)

      session_arguments = [prefix, options[:socket_path], options[:transport]]

      session_options = [
        on_mount: [BeamConsoleWeb.Hooks],
        session: {__MODULE__, :__session__, session_arguments},
        root_layout: {BeamConsoleWeb.Layouts, :root}
      ]

      {options[:as], session_options, as: options[:as]}
    end

    @spec __session__(Plug.Conn.t() | map(), String.t(), String.t(), String.t()) :: map()
    @doc "Builds the serializable session metadata used by the embedded LiveView."
    def __session__(_conn, prefix, live_path, live_transport) do
      %{
        "prefix" => prefix,
        "live_path" => live_path,
        "live_transport" => live_transport
      }
    end

    defp validate_options!(options) do
      allowed = [:as, :enabled, :socket_path, :transport]

      Enum.each(options, fn
        {:as, value} when is_atom(value) ->
          :ok

        {:enabled, value} when is_boolean(value) ->
          :ok

        {:socket_path, value} when is_binary(value) ->
          :ok

        {:transport, value} when value in @transports ->
          :ok

        {key, _value} ->
          if key in allowed do
            raise ArgumentError, "invalid BeamConsole option #{key}"
          else
            raise ArgumentError, "unknown BeamConsole option #{key}"
          end
      end)
    end
  end
end
