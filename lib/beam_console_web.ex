if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule BeamConsoleWeb do
    @moduledoc false

    def live_view do
      quote do
        use Phoenix.LiveView

        import Phoenix.Component

        alias BeamConsoleWeb.Layouts
      end
    end

    def html do
      quote do
        use Phoenix.Component

        import Phoenix.Component
      end
    end

    defmacro __using__(which) when is_atom(which) do
      apply(__MODULE__, which, [])
    end
  end
end
