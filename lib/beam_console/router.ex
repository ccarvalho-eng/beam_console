if Code.ensure_loaded?(Phoenix.Router) and Code.ensure_loaded?(Phoenix.LiveView.Router) do
  defmodule BeamConsole.Router do
    @moduledoc """
    Router helpers for mounting BeamConsole inside a Phoenix application.

    The host owns authentication, authorization, endpoint configuration, and
    deployment exposure.
    """

    @default_options [
      as: :beam_console,
      socket_path: "/live",
      transport: "websocket",
      on_mount: [],
      session: nil
    ]
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

    ## Options

      * `:enabled` - mounts the routes when `true`; defaults to `true` only in
        the `:dev` Mix environment
      * `:as` - names the LiveView session and route helpers; defaults to
        `:beam_console` and must be distinct for multiple mounts
      * `:on_mount` - host authorization hooks run before BeamConsole's hook;
        defaults to `[]`
      * `:session` - a string-keyed map or `{module, function, arguments}`
        callback merged into the LiveView session; defaults to `nil`
      * `:socket_path` - the host LiveView socket path; defaults to `"/live"`
        and must match the socket configured by the endpoint
      * `:transport` - `"websocket"` or `"longpoll"`; defaults to
        `"websocket"` and must match a transport enabled by the endpoint
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
              get("/assets/css/:digest", BeamConsoleWeb.Assets, :css, as: nil)
              get("/assets/js/:digest", BeamConsoleWeb.Assets, :js, as: nil)
              get("/assets/phoenix/:digest", BeamConsoleWeb.Assets, :phoenix, as: nil)
              get("/assets/live-view/:digest", BeamConsoleWeb.Assets, :live_view, as: nil)
              get("/assets/cytoscape/:digest", BeamConsoleWeb.Assets, :cytoscape, as: nil)
              get("/assets/support/:digest", BeamConsoleWeb.Assets, :support, as: nil)
              get("/assets/theme/:digest", BeamConsoleWeb.Assets, :theme, as: nil)
              live("/", BeamConsoleWeb.ConsoleLive, :process_map, route_options)
              live("/lifecycle", BeamConsoleWeb.ConsoleLive, :lifecycle, route_options)
              live("/activity", BeamConsoleWeb.ConsoleLive, :activity, route_options)
              live("/runtime", BeamConsoleWeb.ConsoleLive, :runtime, route_options)
            end
          end
        end
      end
    end

    @doc "Builds validated LiveView session and route options for the router macro."
    @spec __options__(String.t(), keyword()) :: {atom(), keyword(), keyword()}
    def __options__(prefix, options) do
      options = Keyword.merge(@default_options, options)
      validate_options!(options)

      session_arguments = [prefix, options[:socket_path], options[:transport], options[:session]]

      session_options = [
        on_mount: options[:on_mount] ++ [BeamConsoleWeb.Hooks],
        session: {__MODULE__, :__session__, session_arguments},
        root_layout: {BeamConsoleWeb.Layouts, :root}
      ]

      {options[:as], session_options, as: options[:as]}
    end

    @doc "Builds the serializable session metadata used by the embedded LiveView."
    @spec __session__(Plug.Conn.t() | map(), String.t(), String.t(), String.t()) :: map()
    def __session__(conn, prefix, live_path, live_transport) do
      %{
        "prefix" => request_path(conn, prefix),
        "live_path" => live_path,
        "live_transport" => live_transport
      }
    end

    @doc "Merges a host-supplied session map with BeamConsole's reserved mount metadata."
    @spec __session__(
            Plug.Conn.t() | map(),
            String.t(),
            String.t(),
            String.t(),
            map() | tuple() | nil
          ) :: map()
    def __session__(conn, prefix, live_path, live_transport, host_session) do
      host_session
      |> resolve_host_session(conn)
      |> Map.merge(__session__(conn, prefix, live_path, live_transport))
    end

    defp validate_options!(options) do
      allowed = [:as, :enabled, :on_mount, :session, :socket_path, :transport]

      Enum.each(options, fn
        {:as, value} when is_atom(value) ->
          :ok

        {:enabled, value} when is_boolean(value) ->
          :ok

        {:on_mount, value} when is_list(value) ->
          :ok

        {:session, nil} ->
          :ok

        {:session, value} when is_map(value) ->
          validate_session_map!(value)

        {:session, {module, function, arguments}}
        when is_atom(module) and is_atom(function) and is_list(arguments) ->
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

    defp resolve_host_session(nil, _conn) do
      %{}
    end

    defp resolve_host_session(session, _conn) when is_map(session) do
      validate_session_map!(session)
    end

    defp resolve_host_session({module, function, arguments}, conn) do
      module
      |> apply(function, [conn | arguments])
      |> validate_session_map!()
    end

    defp request_path(%{script_name: script_name}, path)
         when is_list(script_name) and script_name != [] do
      "/" <> Enum.join(script_name, "/") <> path
    end

    defp request_path(_conn, path) do
      path
    end

    defp validate_session_map!(session) when is_map(session) do
      if Enum.all?(Map.keys(session), &is_binary/1) do
        session
      else
        raise ArgumentError, "BeamConsole host session keys must be strings"
      end
    end

    defp validate_session_map!(_session) do
      raise ArgumentError, "BeamConsole host session callback must return a map"
    end
  end
end
