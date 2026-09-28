#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

[[ -s "$ROOT_DIR/profile/packages.x86_64" ]] || fail "package manifest is missing or empty"
[[ -d "$ROOT_DIR/profile/airootfs" ]] || fail "airootfs overlay is missing"

for package in linux-zen steam hyprland networkmanager waybar sddm; do
  grep -qxF "$package" "$ROOT_DIR/profile/packages.x86_64" || fail "required package missing: $package"
done
! grep -qxF linux "$ROOT_DIR/profile/packages.x86_64" || fail "manifest must not request the generic linux kernel"

# Pin the build script's stock-Archiso kernel path rewrite, including fallback images.
rewritten="$(printf '%s\n' 'linux /arch/boot/x86_64/vmlinuz-linux' 'initrd /arch/boot/x86_64/initramfs-linux.img' 'initrd /arch/boot/x86_64/initramfs-linux-fallback.img' | sed -E 's/(vmlinuz|initramfs)-linux(-fallback)?([.]|[[:space:]]|$)/\1-linux-zen\2\3/g')"
expected="$(printf '%s\n' 'linux /arch/boot/x86_64/vmlinuz-linux-zen' 'initrd /arch/boot/x86_64/initramfs-linux-zen.img' 'initrd /arch/boot/x86_64/initramfs-linux-zen-fallback.img')"
[[ "$rewritten" == "$expected" ]] || fail "boot-entry rewrite does not select linux-zen"

# Ensure each additional package is a single, uncommented package name.
if grep -nEv '^[[:space:]]*($|#|[a-zA-Z0-9@._+-]+$)' "$ROOT_DIR/profile/packages.x86_64"; then
  fail "invalid line in package manifest"
fi

while IFS= read -r -d '' script; do
  bash -n "$script" || fail "shell syntax error: $script"
done < <(find "$ROOT_DIR/scripts" "$ROOT_DIR/profile/airootfs/usr/local" -type f -print0 2>/dev/null)

for file in \
  "$ROOT_DIR/profile/airootfs/etc/sddm.conf.d/10-anios-autologin.conf" \
  "$ROOT_DIR/profile/airootfs/usr/share/wayland-sessions/anios.desktop" \
  "$ROOT_DIR/profile/airootfs/etc/NetworkManager/conf.d/20-anios-wifi.conf" \
  "$ROOT_DIR/profile/airootfs/etc/systemd/sysusers.d/anios.conf" \
  "$ROOT_DIR/profile/airootfs/etc/tmpfiles.d/anios.conf"; do
  [[ -s "$file" ]] || fail "expected configuration missing: ${file#"$ROOT_DIR/"}"
done

SDDM_CONFIG="$ROOT_DIR/profile/airootfs/etc/sddm.conf.d/10-anios-autologin.conf"
grep -qxF '[Autologin]' "$SDDM_CONFIG" || fail "SDDM autologin section is missing"
grep -qxF 'User=anios' "$SDDM_CONFIG" || fail "SDDM must autologin the live user"
grep -qxF 'Session=anios' "$SDDM_CONFIG" || fail "SDDM must start the AniOS Wayland session"
grep -qxF 'Exec=/usr/local/bin/anios-session' \
  "$ROOT_DIR/profile/airootfs/usr/share/wayland-sessions/anios.desktop" ||
  fail "AniOS SDDM session must start anios-session"

DISPLAY_MANAGER="$ROOT_DIR/profile/airootfs/etc/systemd/system/display-manager.service"
[[ -L "$DISPLAY_MANAGER" ]] || fail "display-manager service symlink is missing"
[[ "$(readlink "$DISPLAY_MANAGER")" == /usr/lib/systemd/system/sddm.service ]] ||
  fail "display-manager must point to sddm.service"
[[ -L "$ROOT_DIR/profile/airootfs/etc/systemd/system/graphical.target.wants/sddm.service" ]] ||
  fail "sddm.service is not enabled for graphical.target"
[[ ! -L "$ROOT_DIR/profile/airootfs/etc/systemd/system/graphical.target.wants/greetd.service" ]] ||
  fail "greetd must not be enabled alongside SDDM"
! grep -qxF greetd "$ROOT_DIR/profile/packages.x86_64" || fail "greetd must be removed when using SDDM"
! grep -qxF greetd-tuigreet "$ROOT_DIR/profile/packages.x86_64" || fail "greetd-tuigreet must be removed when using SDDM"
[[ ! -e "$ROOT_DIR/profile/airootfs/etc/greetd/config.toml" ]] ||
  fail "stale greetd configuration must be removed"
[[ -x "$ROOT_DIR/scripts/build-iso.sh" ]] || fail "build script is not executable"
[[ -x "$ROOT_DIR/scripts/check-profile.sh" ]] || fail "check script is not executable"

pass "AniOS profile checks passed (ISO build still requires Arch Linux + archiso)"
