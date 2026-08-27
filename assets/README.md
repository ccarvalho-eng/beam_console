# BeamConsole browser assets

The authored browser code lives in the focused files under `css/` and `js/`.
The library ships concatenated artifacts under `priv/static/` so host
applications do not need a JavaScript or CSS build step.

Run `npm run build` after changing an authored source file. `npm run check`
verifies that the committed artifacts are current, checks JavaScript syntax,
executes the client contract tests, and validates vendored dependencies.
