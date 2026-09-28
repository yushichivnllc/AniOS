#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

[[ -s "$ROOT_DIR/profile/packages.x86_64" ]] || fail "package manifest is missing or empty"
[[ -d "$ROOT_DIR/profile/airootfs" ]] || fail "airootfs overlay is missing"

for package in linux-zen steam hyprland networkmanager waybar; do
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
  "$ROOT_DIR/profile/airootfs/etc/greetd/config.toml" \
  "$ROOT_DIR/profile/airootfs/etc/NetworkManager/conf.d/20-anios-wifi.conf" \
  "$ROOT_DIR/profile/airootfs/etc/systemd/sysusers.d/anios.conf" \
  "$ROOT_DIR/profile/airootfs/etc/tmpfiles.d/anios.conf"; do
  [[ -s "$file" ]] || fail "expected configuration missing: ${file#"$ROOT_DIR/"}"
done

[[ -L "$ROOT_DIR/profile/airootfs/etc/systemd/system/display-manager.service" ]] || fail "greetd display-manager symlink is missing"
[[ -x "$ROOT_DIR/scripts/build-iso.sh" ]] || fail "build script is not executable"
[[ -x "$ROOT_DIR/scripts/check-profile.sh" ]] || fail "check script is not executable"

pass "AniOS profile checks passed (ISO build still requires Arch Linux + archiso)"
