#!/usr/bin/env bash
# Apply the cursor theme/size chosen in Settings > Cursor at Hyprland start.
# Reads the shell config directly rather than hardcoding a literal, so this
# line no longer clobbers the user's choice on every start.
#
# The theme is checked against the installed icon roots BEFORE it reaches the
# compositor, because `hyprctl setcursor <theme-that-is-not-installed> <size>`
# is not a harmless no-op: Hyprland hands the name to libXcursor, no theme
# directory matches, so XCursorManager::loadTheme() logs "XCursor failed finding
# any shapes in theme" and keeps an empty shape list. The compositor then has no
# cursor of its own and swaps between that empty cursor and whatever surface each
# client sets, which is exactly the pointer that blinks/flickers as it crosses
# windows. A saved theme that is not installed falls back to Adwaita (shipped by
# the adwaita-cursors package and named by every other AniOS default); if even
# Adwaita is missing, the compositor's own default is left alone.
set -u

theme="Adwaita"
size=24

cfg="$HOME/.config/immaterial-impulse/config.json"
# Pre-migration installs still hold their config under the legacy name; the
# shell migrates it on first start, which may not have happened yet at this
# point in Hyprland's startup.
[ -f "$cfg" ] || cfg="$HOME/.config/illogical-impulse/config.json"

if [ -f "$cfg" ]; then
    saved="$(python3 - "$cfg" <<'PY'
import json, sys
try:
    cursor = json.load(open(sys.argv[1])).get("hyprland", {}).get("cursor", {})
    theme = str(cursor.get("theme", "") or "")
    size = int(cursor.get("size", 0) or 0)
except (OSError, ValueError, TypeError):
    theme, size = "", 0
print(theme)
print(size)
PY
)" || saved=""
    saved_theme="$(printf '%s\n' "$saved" | sed -n 1p)"
    saved_size="$(printf '%s\n' "$saved" | sed -n 2p)"
    [ -n "$saved_theme" ] && theme="$saved_theme"
    case "$saved_size" in
        ''|*[!0-9]*|0) ;;
        *) size="$saved_size" ;;
    esac
fi

# Icon roots to look for cursor themes in, colon-separated. Same order libXcursor
# and scripts/cursor/apply-cursor-theme.sh use. Overridable so
# scripts/selftest-apply-saved-cursor.sh can point this at a fake tree instead of
# the real /usr/share/icons.
icon_roots="${ANIOS_CURSOR_ICON_ROOTS:-${XDG_DATA_HOME:-$HOME/.local/share}/icons:$HOME/.icons:/usr/share/icons}"

# A theme counts as installed when it ships either cursor format: an XCursor
# `cursors/` payload or a hyprcursor manifest (hyprctl setcursor accepts both).
theme_installed() {
    local id="$1" root
    local -a roots=()
    IFS=: read -r -a roots <<<"$icon_roots"
    for root in "${roots[@]}"; do
        [ -n "$root" ] || continue
        [ -d "$root/$id/cursors" ] && return 0
        [ -f "$root/$id/manifest.hl" ] && return 0
        [ -f "$root/$id/manifest.toml" ] && return 0
    done
    return 1
}

if ! theme_installed "$theme"; then
    echo "apply_saved_cursor: cursor theme '$theme' is not installed; falling back to Adwaita" >&2
    theme="Adwaita"
fi

if ! theme_installed "$theme"; then
    echo "apply_saved_cursor: no installed cursor theme found; keeping the compositor default" >&2
    exit 0
fi

exec hyprctl setcursor "$theme" "$size"
