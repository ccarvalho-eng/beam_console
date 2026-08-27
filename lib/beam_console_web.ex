if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule BeamConsoleWeb do
    @moduledoc """
    Provides the component and LiveView definitions used by BeamConsole's
    optional Phoenix interface.

    The module is compiled only when Phoenix LiveView is available.
    """

    @doc "Returns the shared imports and aliases for BeamConsole LiveViews."
    @spec live_view() :: Macro.t()
    def live_view do
      quote do
        use Phoenix.LiveView

        import Phoenix.Component

        alias BeamConsoleWeb.Layouts
      end
    end

    @doc "Returns the shared imports for BeamConsole function components."
    @spec html() :: Macro.t()
    def html do
      quote do
        use Phoenix.Component

        import Phoenix.Component
      end
    end

    @doc "Expands the requested BeamConsole web definition."
    defmacro __using__(which) when is_atom(which) do
      apply(__MODULE__, which, [])
    end
  end
end
