#!/usr/bin/env bash
# Validate both skel copies without requiring a Wayland session or GPU.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LUA="${LUA:-lua}"
command -v "$LUA" >/dev/null 2>&1 || {
  echo "FAIL: Lua is required (Arch: pacman -S lua; Debian/Ubuntu: apt install lua5.4)" >&2
  exit 1
}
TMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TMP_DIR"' EXIT

for skel in etc/skel usr/share/anios/skel; do
  source_config="$ROOT_DIR/profile/airootfs/$skel/.config"
  # Parse all modules, including currently empty/custom overrides, not just the
  # master file. loadfile compiles but never runs the config or requires hl.
  while IFS= read -r -d '' file; do
    LUA_CHECK_FILE="$file" "$LUA" -e 'assert(loadfile(os.getenv("LUA_CHECK_FILE")))'
  done < <(find "$source_config/hypr" -type f -name '*.lua' -print0)

  home="$TMP_DIR/$skel"
  config_home="$TMP_DIR/$skel-xdg-config"
  mkdir -p "$home/.config/anios" "$config_home/anios"
  cp -a "$source_config/hypr" "$home/.config/"
  for case in \
    'hyprland.lua minimal minimal imi' \
    'hyprland.lua imi imi minimal' \
    'hyprland.lua imi not-a-mode imi' \
    'hyprland-minimal.lua minimal imi imi' \
    'hyprland-imi.lua imi minimal minimal'; do
    read -r entry mode saved_mode env_mode <<< "$case"
    printf '%s\n' "$saved_mode" > "$config_home/anios/desktop-mode"
    HOME="$home" XDG_CONFIG_HOME="$config_home" ANIOS_DESKTOP="$env_mode" \
      "$LUA" "$ROOT_DIR/tests/hyprland-config.lua" \
      "$home/.config/hypr" "$entry" "$mode" \
      "$source_config/matugen/templates/hyprland/colors.lua"
  done
  echo "OK: Hyprland Lua syntax and smoke tests ($skel)"
done

for dir in hypr matugen/templates/hyprland quickshell; do
  diff -qr "$ROOT_DIR/profile/airootfs/etc/skel/.config/$dir" \
           "$ROOT_DIR/profile/airootfs/usr/share/anios/skel/.config/$dir"
done
