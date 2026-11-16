#!/usr/bin/env bash
#
# setup.sh -- install the Omarchy Murmo panel plugin into a user's config.
#
#   ./setup.sh install [--autostart] [--no-path]
#   ./setup.sh uninstall
#   ./setup.sh status
#
# install is idempotent: a second run reports what is already in place and
# changes nothing. Every path can be overridden for testing:
#
#   HYPR_DIR=...  (default ~/.config/hypr)
#   BIN_DIR=...   (default ~/.local/bin)
#   SKIP_RELOAD=1 (do not call hyprctl)
#   SKIP_PLUGIN=1 (do not call omarchy)

set -euo pipefail

PLUGIN_ID="pinta365.murmo"
REQUIRE_LINE='require("hypr.murmo")'

# ── resolve paths ─────────────────────────────────────────────────────────────

# The plugin root is this script's own directory (the repo root when run from a
# dev checkout; the clone directory when installed with `omarchy plugin add`).
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  target="$(readlink -- "$SELF")"
  case "$target" in
    /*) SELF="$target" ;;
    *) SELF="$(dirname -- "$SELF")/$target" ;;
  esac
done
PLUGIN_DIR="$(cd -- "$(dirname -- "$SELF")" && pwd -P)"

HYPR_DIR="${HYPR_DIR:-$HOME/.config/hypr}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
SKIP_RELOAD="${SKIP_RELOAD:-0}"
SKIP_PLUGIN="${SKIP_PLUGIN:-0}"

MURMO_LUA="$HYPR_DIR/murmo.lua"
HYPRLAND_LUA="$HYPR_DIR/hyprland.lua"
AUTOSTART_LUA="$HYPR_DIR/autostart.lua"
BIN_LINK="$BIN_DIR/murmo-panel"
PANEL_SCRIPT="$PLUGIN_DIR/bin/murmo-panel"

usage() {
  cat <<'EOF'
Usage:
  setup.sh install [--autostart] [--no-path]   install (idempotent)
  setup.sh uninstall                           remove what install created
  setup.sh status                              show what is installed

Options for install:
  --autostart   also preload the panel hidden at login (o.exec_on_start)
  --no-path     do not link murmo-panel into ~/.local/bin

Env overrides: HYPR_DIR, BIN_DIR, SKIP_RELOAD=1, SKIP_PLUGIN=1
EOF
}

note() { printf '%s\n' "$*"; }
warn() { printf 'setup.sh: %s\n' "$*" >&2; }

have() { command -v "$1" >/dev/null 2>&1; }

# ── helpers ───────────────────────────────────────────────────────────────────

# Move an existing file or symlink aside as <path>.bak.<epoch>.
backup() {
  local path="$1"
  if [ -e "$path" ] || [ -L "$path" ]; then
    local bak="$path.bak.$(date +%s)"
    cp -a -- "$path" "$bak"
    note "backed up $path -> $bak"
  fi
}

# Make `link` a symlink to `target`, idempotently. A symlink that already
# resolves to `target` counts as installed, even if it takes another route.
link_into_plugin() {
  local link="$1" target="$2"
  local want
  want="$(readlink -f -- "$target" 2>/dev/null || true)"
  if [ -L "$link" ] && [ "$want" != "" ] && [ "$(readlink -f -- "$link" 2>/dev/null || true)" = "$want" ]; then
    note "already: $link -> $target"
    return 0
  fi
  if [ -e "$link" ] || [ -L "$link" ]; then
    backup "$link"
  fi
  mkdir -p -- "$(dirname -- "$link")"
  ln -sfn -- "$target" "$link"
  note "linked: $link -> $target"
}

# 0 if `$1` contains the exact line `$2`.
has_line() {
  [ -f "$1" ] && grep -qxF -- "$2" "$1"
}

# Append `$2` to `$1` (backing it up first) unless it is already there.
add_line() {
  local file="$1" line="$2"
  if has_line "$file" "$line"; then
    note "already in $(basename -- "$file"): $line"
    return 0
  fi
  [ -f "$file" ] && backup "$file"
  mkdir -p -- "$(dirname -- "$file")"
  printf '%s\n' "$line" >> "$file"
  note "added to $(basename -- "$file"): $line"
}

# Remove the exact line `$2` from `$1` (backing it up first) if present.
drop_line() {
  local file="$1" line="$2"
  has_line "$file" "$line" || return 0
  backup "$file"
  grep -vxF -- "$line" "$file" > "$file.tmp.$$"
  mv -- "$file.tmp.$$" "$file"
  note "removed from $(basename -- "$file"): $line"
}

# 0 if `link` is a symlink whose target resolves inside the plugin directory.
links_into_plugin() {
  local link="$1" resolved
  [ -L "$link" ] || return 1
  resolved="$(readlink -f -- "$link" 2>/dev/null || true)"
  [ "$resolved" != "" ] && case "$resolved" in "$PLUGIN_DIR"/*) return 0 ;; esac
  return 1
}

require_present() {
  [ -f "$HYPRLAND_LUA" ] && {
    grep -qF -- 'require("hypr.murmo")' "$HYPRLAND_LUA" ||
      grep -qF -- "require('hypr.murmo')" "$HYPRLAND_LUA"
  }
}

# The exec line used for --autostart, with either the bare command or the full
# path (when --no-path leaves murmo-panel off PATH).
autostart_bare='o.exec_on_start("murmo-panel start")'
autostart_full="o.exec_on_start(\"$PANEL_SCRIPT start\")"
autostart_present() {
  [ -f "$AUTOSTART_LUA" ] || return 1
  has_line "$AUTOSTART_LUA" "$autostart_bare" || has_line "$AUTOSTART_LUA" "$autostart_full"
}

plugin_enabled() {
  have omarchy || return 1
  omarchy plugin list --json 2>/dev/null | python3 -c '
import json, sys
try:
    plugins = json.load(sys.stdin)
except Exception:
    sys.exit(1)
sys.exit(0 if any(p.get("id") == "'"$PLUGIN_ID"'" and p.get("enabled") for p in plugins) else 1)'
}

check_prereqs() {
  local missing=()
  have hyprctl || missing+=(hyprctl)
  have python3 || missing+=(python3)
  if [ "$SKIP_PLUGIN" != 1 ]; then
    have omarchy || missing+=(omarchy)
  fi
  if ! have chromium && ! have chromium-browser && ! have google-chrome-stable; then
    missing+=(chromium)
  fi
  if [ "${#missing[@]}" -gt 0 ]; then
    warn "missing required command(s): ${missing[*]}"
    warn "install them (for Chromium: 'omarchy pkg add chromium') and try again"
    exit 1
  fi

  if [ ! -f "$PLUGIN_DIR/manifest.json" ]; then
    warn "no manifest.json in $PLUGIN_DIR -- is this the plugin directory?"
    exit 1
  fi
  if [ ! -x "$PANEL_SCRIPT" ]; then
    warn "helper script missing or not executable: $PANEL_SCRIPT"
    exit 1
  fi
}

reload_hyprland() {
  if [ "$SKIP_RELOAD" = 1 ]; then
    note "skipping hyprctl reload (SKIP_RELOAD=1)"
    return 0
  fi
  hyprctl reload >/dev/null
  local errors
  errors="$(hyprctl configerrors 2>&1 || true)"
  if printf '%s' "$errors" | grep -qi murmo; then
    warn "Hyprland reported config errors mentioning murmo:"
    printf '%s\n' "$errors" >&2
    exit 1
  fi
}

# ── install ───────────────────────────────────────────────────────────────────

do_install() {
  local autostart=0 no_path=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --autostart) autostart=1 ;;
      --no-path) no_path=1 ;;
      *) warn "unknown option: $1"; usage >&2; exit 2 ;;
    esac
    shift
  done

  check_prereqs

  note "plugin: $PLUGIN_DIR"

  # 1. Hyprland window rule.
  link_into_plugin "$MURMO_LUA" "$PLUGIN_DIR/hypr/murmo.lua"

  # 2. require("hypr.murmo") in hyprland.lua.
  add_line "$HYPRLAND_LUA" "$REQUIRE_LINE"

  # 3. murmo-panel on PATH (unless --no-path).
  if [ "$no_path" = 1 ]; then
    note "skipping PATH link (--no-path)"
  else
    link_into_plugin "$BIN_LINK" "$PANEL_SCRIPT"
  fi

  # 4. Autostart.
  if [ "$autostart" = 1 ]; then
    if autostart_present; then
      note "already in $(basename -- "$AUTOSTART_LUA"): murmo-panel start"
    elif [ "$no_path" = 1 ]; then
      add_line "$AUTOSTART_LUA" "$autostart_full"
    else
      add_line "$AUTOSTART_LUA" "$autostart_bare"
    fi
  fi

  # 5. Enable the shell plugin.
  if [ "$SKIP_PLUGIN" = 1 ]; then
    note "skipping plugin enable (SKIP_PLUGIN=1)"
  elif plugin_enabled; then
    note "already enabled: $PLUGIN_ID"
  else
    have omarchy-shell && omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
    omarchy plugin enable "$PLUGIN_ID"
  fi

  # 6. Reload Hyprland.
  reload_hyprland

  note "done."
}

# ── uninstall ─────────────────────────────────────────────────────────────────

do_uninstall() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      *) warn "uninstall takes no options"; usage >&2; exit 2 ;;
    esac
  done

  # Hide the panel window if it is running (the helper needs hyprctl).
  if have hyprctl && [ -x "$PANEL_SCRIPT" ]; then
    "$PANEL_SCRIPT" hide >/dev/null 2>&1 || true
  fi

  # Remove only the symlinks that point into the plugin directory.
  if links_into_plugin "$BIN_LINK"; then
    rm -- "$BIN_LINK"
    note "removed: $BIN_LINK"
  elif [ -L "$BIN_LINK" ]; then
    note "kept (does not point into the plugin): $BIN_LINK"
  fi

  if links_into_plugin "$MURMO_LUA"; then
    rm -- "$MURMO_LUA"
    note "removed: $MURMO_LUA"
  elif [ -e "$MURMO_LUA" ] || [ -L "$MURMO_LUA" ]; then
    note "kept (does not point into the plugin): $MURMO_LUA"
  fi

  # Remove our exact config lines.
  drop_line "$HYPRLAND_LUA" "$REQUIRE_LINE"
  drop_line "$HYPRLAND_LUA" "require('hypr.murmo')"
  drop_line "$AUTOSTART_LUA" "$autostart_bare"
  drop_line "$AUTOSTART_LUA" "$autostart_full"

  # Disable the shell plugin.
  if [ "$SKIP_PLUGIN" = 1 ]; then
    note "skipping plugin disable (SKIP_PLUGIN=1)"
  elif plugin_enabled; then
    omarchy plugin disable "$PLUGIN_ID" || warn "could not disable $PLUGIN_ID"
  else
    note "already disabled: $PLUGIN_ID"
  fi

  reload_hyprland

  note "done."
  note "Your Murmo device data was left untouched at:"
  note "  ${XDG_DATA_HOME:-$HOME/.local/share}/murmo-panel"
  note "Delete it by hand if you also want to forget the device:"
  note "  rm -rf ${XDG_DATA_HOME:-$HOME/.local/share}/murmo-panel"
}

# ── status ────────────────────────────────────────────────────────────────────

do_status() {
  note "plugin:      $PLUGIN_DIR"

  if links_into_plugin "$MURMO_LUA"; then
    note "hypr rule:   installed -> $MURMO_LUA"
  elif [ -e "$MURMO_LUA" ] || [ -L "$MURMO_LUA" ]; then
    note "hypr rule:   present but not ours -> $MURMO_LUA"
  else
    note "hypr rule:   missing ($MURMO_LUA)"
  fi

  if require_present; then
    note "require:     installed ($REQUIRE_LINE)"
  else
    note "require:     missing"
  fi

  if links_into_plugin "$BIN_LINK"; then
    note "path link:   installed -> $BIN_LINK"
  elif [ -e "$BIN_LINK" ] || [ -L "$BIN_LINK" ]; then
    note "path link:   present but not ours -> $BIN_LINK"
  else
    note "path link:   missing ($BIN_LINK)"
  fi

  if autostart_present; then
    note "autostart:   installed"
  else
    note "autostart:   missing"
  fi

  if [ "$SKIP_PLUGIN" = 1 ]; then
    note "plugin:      unknown (SKIP_PLUGIN=1)"
  elif plugin_enabled; then
    note "plugin:      enabled ($PLUGIN_ID)"
  else
    note "plugin:      disabled or not installed ($PLUGIN_ID)"
  fi

  local data="${XDG_DATA_HOME:-$HOME/.local/share}/murmo-panel"
  if [ -d "$data" ]; then
    note "device data: present ($data)"
  else
    note "device data: none yet ($data)"
  fi
}

# ── main ──────────────────────────────────────────────────────────────────────

main() {
  local command="${1:-}"
  [ "$#" -gt 0 ] && shift
  case "$command" in
    install) do_install "$@" ;;
    uninstall) do_uninstall "$@" ;;
    status) do_status "$@" ;;
    "" | -h | --help | help) usage ;;
    *) warn "unknown command: $command"; usage >&2; exit 2 ;;
  esac
}

main "$@"
