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
  mkdir -p "$home/.config/anios"
  cp -a "$source_config/hypr" "$home/.config/"
  # Chạy mỗi cấu hình với ba hồ sơ GPU mà anios-session có thể đặt:
  #   * mặc định (Intel/AMD hoặc chưa nạp driver NVIDIA) — cấu hình cũ phải y nguyên;
  #   * ANIOS_GPU=nvidia — tắt con trỏ phần cứng + VFR cho driver proprietary;
  #   * ANIOS_SAFE=1 — phiên "AniOS - Safe" (cũng là chế độ tự lùi khi Hyprland chết).
  for profile in 'default|' 'nvidia|ANIOS_GPU=nvidia' 'safe|ANIOS_SAFE=1'; do
    profile_name="${profile%%|*}"
    profile_env="${profile#*|}"
    for case in 'hyprland.lua minimal' 'hyprland.lua imi' \
                'hyprland-minimal.lua minimal' 'hyprland-imi.lua imi'; do
      read -r entry mode <<< "$case"
      printf '%s\n' "$mode" > "$home/.config/anios/desktop-mode"
      # shellcheck disable=SC2086 # profile_env chỉ chứa các phép gán NAME=value
      env HOME="$home" ANIOS_DESKTOP="$mode" $profile_env \
        "$LUA" "$ROOT_DIR/tests/hyprland-config.lua" \
        "$home/.config/hypr" "$entry" "$mode" \
        "$source_config/matugen/templates/hyprland/colors.lua"
    done
    echo "OK: Hyprland Lua syntax and smoke tests ($skel, hồ sơ $profile_name)"
  done
done

for dir in hypr matugen/templates/hyprland quickshell; do
  diff -qr "$ROOT_DIR/profile/airootfs/etc/skel/.config/$dir" \
           "$ROOT_DIR/profile/airootfs/usr/share/anios/skel/.config/$dir"
done
