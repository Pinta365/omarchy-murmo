# Murmo panel for Omarchy 4

A bar widget that shows the [Murmo](https://murmo.org) web app as a floating
top-right panel, with an unread badge.

- **Icon:** a chat bubble in the bar's right section (`pinta365.murmo`).
- **Left click:** show the panel, or hide it again.
- **Unread badge:** reads the `(N) …` prefix Murmo puts on the window title and
  shows the number (capped at `99+`).
- **Click outside:** hides the panel (a full-screen transparent click-catcher).
- **Resize:** drag with `SUPER` + right mouse button; the click-catcher follows.

Requires Omarchy 4 (Quickshell), Hyprland 0.56, Chromium, and `python3`.

## Install

```sh
omarchy plugin add https://github.com/Pinta365/omarchy-murmo.git
omarchy plugin enable pinta365.murmo
```

The widget appears in the bar's right section. Move it if you like:

```sh
omarchy bar move pinta365.murmo --section right
omarchy bar move pinta365.murmo --after omarchy.audio
```

## Setup

The bundled script does the Hyprland wiring (and enables the plugin). Run it from
the plugin directory (`~/.config/omarchy/plugins/pinta365.murmo`):

```sh
./setup.sh install              # Hyprland rule + require + murmo-panel on PATH
./setup.sh install --autostart  # …and preload the panel hidden at login
./setup.sh status               # show what is installed
./setup.sh uninstall            # undo it (keeps your Murmo device data)
```

It is idempotent — a second run reports what is already in place and changes
nothing — and it backs up every file it edits to `*.bak.<epoch>`. It checks for
`hyprctl`, `chromium`, `python3` and `omarchy` first, then reloads Hyprland and
reports any `murmo` config errors.

Options:

- `--autostart` — also add `o.exec_on_start(...)` to `~/.config/hypr/autostart.lua`,
  so the panel is preloaded hidden and the unread badge is live from login.
- `--no-path` — do not link `murmo-panel` into `~/.local/bin`; `--autostart` then
  uses the full path to the helper.

`uninstall` removes only what `install` created and never touches
`~/.local/share/murmo-panel` (your Murmo device data) — delete that by hand if you
want the server to forget the device.

Env overrides for testing: `HYPR_DIR` (default `~/.config/hypr`), `BIN_DIR`
(default `~/.local/bin`), `SKIP_RELOAD=1`, `SKIP_PLUGIN=1`.

## Manual setup

If you would rather not run the script:

1. Link the Hyprland rule (or copy it):

   ```sh
   ln -s ~/.config/omarchy/plugins/pinta365.murmo/hypr/murmo.lua ~/.config/hypr/murmo.lua
   ```

2. Add `require("hypr.murmo")` to `~/.config/hypr/hyprland.lua` (after
   `require("hypr.autostart")`).

3. Reload and check for errors:

   ```sh
   hyprctl reload && hyprctl configerrors
   ```

4. Optional — put the helper on `PATH` and preload it at login:

   ```sh
   ln -s ~/.config/omarchy/plugins/pinta365.murmo/bin/murmo-panel ~/.local/bin/murmo-panel
   ```

   then add to `~/.config/hypr/autostart.lua`:

   ```lua
   o.exec_on_start("murmo-panel start")
   ```

## Setting: `url`

The web app address, default `https://murmo.org/`. Point it at a self-hosted
Murmo instance:

```sh
omarchy bar set pinta365.murmo url https://example.com/
```

## How it works

- The helper `bin/murmo-panel` launches Chromium as an app
  (`--app=<url> --user-data-dir=~/.local/share/murmo-panel/chromium
  --profile-directory=murmo-panel`) and toggles the special workspace.
- Chromium ignores `--class` on `--app` windows and builds the Wayland app_id as
  `chrome-<url-host>__-<profile-directory>`, so this window arrives as
  `chrome-murmo.org__-murmo-panel`. `hypr/murmo.lua` matches that and parks it on
  `special:murmo` (silent, floating, 460×720).
- When shown, the helper moves the panel to the top-right (16 px from the right
  edge, under the bar) and toggles the workspace with the Hyprland 0.56 Lua
  dispatch `hl.dsp.workspace.toggle_special('murmo')`.
- The widget reads the window title for the badge and creates one transparent
  click-catcher per bar surface. The catcher is a top layer surface that never
  takes keyboard focus, and its input region excludes the panel and the bar, so
  clicks on the panel and the bar are unaffected while a click anywhere else
  hides the panel.

## Known limitations

- The click that hides the panel is swallowed — it hides the panel instead of
  reaching the window underneath.
- Screens without an Omarchy bar get no click-catcher (the catcher comes from the
  bar widget, which only exists on screens that show the bar).
- The panel uses its own Chromium profile, i.e. a separate Murmo device that must
  be approved once.
