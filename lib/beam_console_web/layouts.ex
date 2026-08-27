if Code.ensure_loaded?(Phoenix.Component) do
  defmodule BeamConsoleWeb.Layouts do
    @moduledoc """
    Renders BeamConsole's isolated HTML document and digest-addressed assets.
    """

    use Phoenix.Component

    alias BeamConsoleWeb.Assets

    @spec root(map()) :: Phoenix.LiveView.Rendered.t()
    @doc "Renders the root layout for an embedded BeamConsole LiveView session."
    def root(assigns) do
      prefix = assigns[:prefix] || ""

      assigns =
        assigns
        |> assign_new(:prefix, fn -> "" end)
        |> assign(:css_path, asset_path(prefix, "css", Assets.css_digest()))
        |> assign(:js_path, asset_path(prefix, "js", Assets.js_digest()))

      ~H"""
      <!DOCTYPE html>
      <html lang="en">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
          <title>BeamConsole · Process Map</title>
          <link rel="stylesheet" href={@css_path} />
          <script
            type="module"
            src={@js_path}
            data-beam-console-client
            data-live-path={@live_path}
            data-live-transport={@live_transport}
          >
          </script>
        </head>
        <body class="beam-console-body">
          {@inner_content}
        </body>
      </html>
      """
    end

    defp asset_path(prefix, kind, digest) do
      String.trim_trailing(prefix, "/") <> "/assets/#{kind}/#{digest}"
    end
  end
end
