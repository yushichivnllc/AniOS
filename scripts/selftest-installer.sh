#!/usr/bin/env bash
# Integration self-test for the Calamares helpers without touching the host.
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PACSTRAP_HELPER="$ROOT_DIR/profile/installer/scripts/anios-installer-pacstrap"
FINALIZE_HELPER="$ROOT_DIR/profile/installer/scripts/anios-installer-finalize"
BOOT_CHOICE="$ROOT_DIR/profile/airootfs/usr/local/bin/anios-boot-choice"
BOOT_CHOICE_QML="$ROOT_DIR/profile/airootfs/usr/share/anios/boot-choice.qml"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

for script in "$PACSTRAP_HELPER" "$FINALIZE_HELPER" "$BOOT_CHOICE" \
  "$ROOT_DIR/profile/installer/scripts/anios-installer-skel" \
  "$ROOT_DIR/profile/installer/scripts/anios-end4-setup" \
  "$ROOT_DIR/profile/installer/scripts/anios-end4-first-login"; do
  [[ -x "$script" ]] || fail "installer script is not executable: ${script#"$ROOT_DIR/"}"
  bash -n "$script" || fail "shell syntax error: ${script#"$ROOT_DIR/"}"
done

# Lock the user-visible selections and the safe execution order into CI.
GRUB_CHOOSER="$ROOT_DIR/profile/installer/calamares/modules/packagechooser-grub.conf"
SDDM_CHOOSER="$ROOT_DIR/profile/installer/calamares/modules/packagechooser-sddm.conf"
DOTFILES_CHOOSER="$ROOT_DIR/profile/installer/calamares/modules/packagechooser-dotfiles.conf"
SETTINGS="$ROOT_DIR/profile/installer/calamares/settings.conf"
AUR_MANIFEST="$ROOT_DIR/profile/packages.aur.x86_64"
BUILD_ISO="$ROOT_DIR/scripts/build-iso.sh"
AUR_BUILDER="$ROOT_DIR/scripts/anios-aur-build.sh"

for text in 'id: default' 'id: gorgeous-grubphemous' 'Jacksaur/Gorgeous-GRUB' 'grub-gorgeous.png'; do
  grep -qF "$text" "$GRUB_CHOOSER" || fail "GRUB chooser is missing: $text"
done
for text in 'id: anios' 'id: wuwa' 'qylock.png'; do
  grep -qF "$text" "$SDDM_CHOOSER" || fail "SDDM chooser is missing: $text"
done
for text in 'id: imi' 'id: end4' 'end-4 / dots-hyprland'; do
  grep -qF "$text" "$DOTFILES_CHOOSER" || fail "dotfiles chooser is missing: $text"
done
grep -qxF 'calamares' "$AUR_MANIFEST" || fail "Calamares must be built into the Live ISO"
grep -qF 'install_calamares_configuration' "$AUR_BUILDER" ||
  fail "the AUR hook must install the staged Calamares configuration"
grep -qF 'upstream/grubphemous' "$BUILD_ISO" ||
  fail "the ISO build must stage the pinned Gorgeous-GRUB theme"

python3 - "$SETTINGS" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
execution = text.split("  - exec:", 1)[1].split("  - show:", 1)[0]
ordered = [
    "- shellprocess@anios-pacstrap",
    "- shellprocess@anios-skel",
    "- users",
    "- grubcfg",
    "- shellprocess@anios-finalize",
    "- bootloader",
]
positions = [execution.find(item) for item in ordered]
assert all(position >= 0 for position in positions), f"settings.conf misses {ordered}"
assert positions == sorted(positions), "Calamares installer jobs are in an unsafe order"
PY

if (( EUID != 0 )) && { ! command -v sudo >/dev/null 2>&1 || ! sudo -n true >/dev/null 2>&1; }; then
  echo "SKIP: root integration tests require passwordless sudo; static checks passed"
  exit 0
fi

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/anios-installer-selftest.XXXXXX")"
cleanup() {
  if [[ -n "${ANIOS_SELFTEST_KEEP_SANDBOX:-}" ]]; then
    echo "Sandbox kept at: $SANDBOX" >&2
  elif (( EUID == 0 )); then
    rm -rf -- "$SANDBOX"
  elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    sudo -n rm -rf -- "$SANDBOX"
  else
    echo "WARN: sandbox contains root-owned test files: $SANDBOX" >&2
  fi
}
trap cleanup EXIT
FAKE_BIN="$SANDBOX/bin"
LIVE_ROOT="$SANDBOX/live"
INSTALLER_DATA="$LIVE_ROOT/usr/share/anios/installer"
mkdir -p -- "$FAKE_BIN" "$LIVE_ROOT/usr/share/anios" \
  "$LIVE_ROOT/usr/share/sddm/themes/anios" "$LIVE_ROOT/usr/share/sddm/themes/wuwa" \
  "$LIVE_ROOT/usr/share/wayland-sessions" "$LIVE_ROOT/usr/local/bin" \
  "$LIVE_ROOT/etc/systemd" "$INSTALLER_DATA/upstream/grubphemous" \
  "$INSTALLER_DATA/licenses" "$INSTALLER_DATA/scripts"

cat >"$FAKE_BIN/mountpoint" <<'FAKE'
#!/usr/bin/env bash
[[ "${1:-}" == -q ]] || exit 1
shift
[[ "${1:-}" == -- ]] && shift
[[ -d "${1:-}" ]]
FAKE
cat >"$FAKE_BIN/pacstrap" <<'FAKE'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$@" >"${ANIOS_TEST_PACSTRAP_LOG:?}"
target="${4:?pacstrap target root is missing}"
install -D -m 0755 /bin/true "$target/usr/bin/pacman"
FAKE
chmod 0755 "$FAKE_BIN/mountpoint" "$FAKE_BIN/pacstrap"

# Mock the Material QML chooser first and KDialog only as a fallback. Live must
# leave the current session alone, while Install launches Calamares on Wayland.
GUI_BIN="$SANDBOX/gui-bin"
GUI_RUNTIME="$SANDBOX/gui-runtime"
CALAMARES_SETTINGS="$SANDBOX/calamares-settings.conf"
CALAMARES_MODULES="$SANDBOX/calamares-modules"
PKEXEC_LOG="$SANDBOX/pkexec-args"
QML_LOG="$SANDBOX/qml-args"
KDIALOG_LOG="$SANDBOX/kdialog-args"
mkdir -p -- "$GUI_BIN" "$GUI_RUNTIME" "$CALAMARES_MODULES"
printf 'settings: AniOS\n' >"$CALAMARES_SETTINGS"
printf 'mock packagechooser plugin\n' >"$CALAMARES_MODULES/libcalamares_viewmodule_packagechooser.so"
cat >"$GUI_BIN/qml6" <<'FAKE'
#!/usr/bin/env bash
set -Eeuo pipefail
{
  printf 'qml=%s\n' "${1:-}"
  printf 'style=%s\n' "${QT_QUICK_CONTROLS_STYLE:-}"
  printf 'args=%s\n' "$*"
} >>"${ANIOS_TEST_QML_LOG:?}"
printf 'qml: ANIOS_BOOT_CHOICE_READY=1\n'
printf 'qml: ANIOS_BOOT_CHOICE=%s\n' "${ANIOS_SELFTEST_CHOICE:-live}"
exit "${ANIOS_TEST_QML_EXIT:-0}"
FAKE
cat >"$GUI_BIN/kdialog" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${ANIOS_TEST_KDIALOG_LOG:?}"
if [[ " $* " == *" --menu "* ]]; then
  printf '%s\n' "${ANIOS_SELFTEST_CHOICE:-live}"
fi
exit 0
FAKE
cat >"$GUI_BIN/calamares" <<'FAKE'
#!/usr/bin/env bash
exit 0
FAKE
cat >"$GUI_BIN/pkexec" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$@" >"${ANIOS_TEST_PKEXEC_LOG:?}"
exit 0
FAKE
chmod 0755 "$GUI_BIN/qml6" "$GUI_BIN/kdialog" "$GUI_BIN/calamares" "$GUI_BIN/pkexec"
: >"$QML_LOG"
: >"$KDIALOG_LOG"
python3 - "$GUI_RUNTIME/wayland-0" <<'PY'
import socket
import sys
sock = socket.socket(socket.AF_UNIX)
sock.bind(sys.argv[1])
sock.close()
PY

env PATH="$GUI_BIN:$PATH" \
  ANIOS_QML_BIN="$GUI_BIN/qml6" \
  ANIOS_BOOT_CHOICE_QML="$BOOT_CHOICE_QML" \
  ANIOS_TEST_QML_LOG="$QML_LOG" ANIOS_TEST_KDIALOG_LOG="$KDIALOG_LOG" \
  ANIOS_CALAMARES_BIN="$GUI_BIN/calamares" \
  ANIOS_CALAMARES_SETTINGS="$CALAMARES_SETTINGS" \
  ANIOS_CALAMARES_MODULE_DIR="$CALAMARES_MODULES" \
  ANIOS_SELFTEST_CHOICE=live \
  "$BOOT_CHOICE"
[[ ! -e "$PKEXEC_LOG" ]] || fail "Live ISO choice unexpectedly started Calamares"
grep -qxF "qml=$BOOT_CHOICE_QML" "$QML_LOG" ||
  fail "Material chooser did not load its QML interface"
grep -qxF 'style=Material' "$QML_LOG" ||
  fail "Material chooser did not request the Material Controls style"
[[ ! -s "$KDIALOG_LOG" ]] || fail "Material chooser unexpectedly used the KDialog fallback"

: >"$QML_LOG"
env PATH="$GUI_BIN:$PATH" \
  ANIOS_QML_BIN="$GUI_BIN/qml6" \
  ANIOS_BOOT_CHOICE_QML="$BOOT_CHOICE_QML" \
  ANIOS_TEST_QML_LOG="$QML_LOG" ANIOS_TEST_KDIALOG_LOG="$KDIALOG_LOG" \
  ANIOS_CALAMARES_BIN="$GUI_BIN/calamares" \
  ANIOS_CALAMARES_SETTINGS="$CALAMARES_SETTINGS" \
  ANIOS_CALAMARES_MODULE_DIR="$CALAMARES_MODULES" \
  ANIOS_SELFTEST_CHOICE=install \
  ANIOS_TEST_PKEXEC_LOG="$PKEXEC_LOG" \
  XDG_RUNTIME_DIR="$GUI_RUNTIME" WAYLAND_DISPLAY=wayland-0 \
  "$BOOT_CHOICE"
grep -qxF "XDG_RUNTIME_DIR=$GUI_RUNTIME" "$PKEXEC_LOG" ||
  fail "Install choice did not pass the Live Wayland runtime to pkexec"
grep -qxF 'WAYLAND_DISPLAY=wayland-0' "$PKEXEC_LOG" ||
  fail "Install choice did not pass WAYLAND_DISPLAY to Calamares"
grep -qxF "$GUI_BIN/calamares" "$PKEXEC_LOG" ||
  fail "Install choice did not launch the Calamares GUI"

# A failed QML launch must fall back to KDialog rather than dropping an install
# selection or treating an error marker as a successful user action.
rm -f -- "$PKEXEC_LOG"
: >"$KDIALOG_LOG"
env PATH="$GUI_BIN:$PATH" \
  ANIOS_QML_BIN="$GUI_BIN/qml6" \
  ANIOS_BOOT_CHOICE_QML="$BOOT_CHOICE_QML" \
  ANIOS_TEST_QML_LOG="$QML_LOG" ANIOS_TEST_KDIALOG_LOG="$KDIALOG_LOG" \
  ANIOS_TEST_QML_EXIT=1 \
  ANIOS_CALAMARES_BIN="$GUI_BIN/calamares" \
  ANIOS_CALAMARES_SETTINGS="$CALAMARES_SETTINGS" \
  ANIOS_CALAMARES_MODULE_DIR="$CALAMARES_MODULES" \
  ANIOS_SELFTEST_CHOICE=install \
  ANIOS_TEST_PKEXEC_LOG="$PKEXEC_LOG" \
  XDG_RUNTIME_DIR="$GUI_RUNTIME" WAYLAND_DISPLAY=wayland-0 \
  "$BOOT_CHOICE"
grep -q -- '--menu' "$KDIALOG_LOG" || fail "QML failure did not activate the KDialog fallback"
grep -qxF "$GUI_BIN/calamares" "$PKEXEC_LOG" ||
  fail "KDialog fallback did not preserve the Install action"

# --no-aur images show the chooser but mark its Install card unavailable.
: >"$QML_LOG"
rm -f -- "$PKEXEC_LOG"
env PATH="$GUI_BIN:$PATH" \
  ANIOS_QML_BIN="$GUI_BIN/qml6" \
  ANIOS_BOOT_CHOICE_QML="$BOOT_CHOICE_QML" \
  ANIOS_TEST_QML_LOG="$QML_LOG" ANIOS_TEST_KDIALOG_LOG="$KDIALOG_LOG" \
  ANIOS_CALAMARES_BIN="$GUI_BIN/not-installed" \
  ANIOS_CALAMARES_SETTINGS="$CALAMARES_SETTINGS" \
  ANIOS_CALAMARES_MODULE_DIR="$CALAMARES_MODULES" \
  ANIOS_SELFTEST_CHOICE=live \
  "$BOOT_CHOICE"
grep -qF -- '--installer-unavailable' "$QML_LOG" ||
  fail "chooser did not disable Install when Calamares is missing"
[[ ! -e "$PKEXEC_LOG" ]] || fail "missing Calamares unexpectedly launched pkexec"

# Defense in depth: even if a broken UI returns Install on a --no-aur image,
# the helper must refuse to start a nonexistent installer.
: >"$KDIALOG_LOG"
env PATH="$GUI_BIN:$PATH" \
  ANIOS_QML_BIN="$GUI_BIN/qml6" \
  ANIOS_BOOT_CHOICE_QML="$BOOT_CHOICE_QML" \
  ANIOS_TEST_QML_LOG="$QML_LOG" ANIOS_TEST_KDIALOG_LOG="$KDIALOG_LOG" \
  ANIOS_CALAMARES_BIN="$GUI_BIN/not-installed" \
  ANIOS_CALAMARES_SETTINGS="$CALAMARES_SETTINGS" \
  ANIOS_CALAMARES_MODULE_DIR="$CALAMARES_MODULES" \
  ANIOS_SELFTEST_CHOICE=install \
  "$BOOT_CHOICE"
[[ ! -e "$PKEXEC_LOG" ]] || fail "installer helper bypassed the missing-Calamares guard"
grep -qF -- '--error' "$KDIALOG_LOG" ||
  fail "missing-Calamares install attempt did not explain why it was refused"

# Minimal but realistic Live payload required by the finalizer.
printf 'fake wallpaper\n' >"$LIVE_ROOT/usr/share/anios/wallpaper.png"
printf '[General]\nbackground=wallpaper.png\n' >"$LIVE_ROOT/usr/share/sddm/themes/anios/theme.conf"
printf '[General]\nbackground=bg.mp4\n' >"$LIVE_ROOT/usr/share/sddm/themes/wuwa/theme.conf"
printf 'import QtQuick\n' >"$LIVE_ROOT/usr/share/sddm/themes/anios/Main.qml"
printf 'ANIOS · ARCH LINUX LIVE\n' >"$LIVE_ROOT/usr/share/sddm/themes/wuwa/Main.qml"
printf 'Name=AniOS live SDDM theme\n' >"$LIVE_ROOT/usr/share/sddm/themes/anios/metadata.desktop"
for session in anios.desktop anios-imi.desktop anios-minimal.desktop; do
  printf '[Desktop Entry]\nExec=/usr/local/bin/anios-session\nTryExec=/usr/local/bin/anios-session\n' \
    >"$LIVE_ROOT/usr/share/wayland-sessions/$session"
done
for binary in anios-session anios-audio-setup anios-audio-check anios-switch-desktop \
  anios-switch-im anios-update; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$LIVE_ROOT/usr/local/bin/$binary"
done
chmod 0755 "$LIVE_ROOT"/usr/local/bin/*
printf 'zram-size = min(ram / 2, 4096)\n' >"$LIVE_ROOT/etc/systemd/zram-generator.conf"
mkdir -p -- "$LIVE_ROOT/usr/share/anios/skel/.config/hypr" "$LIVE_ROOT/usr/share/anios/skel/Desktop"
cat >"$LIVE_ROOT/usr/share/anios/skel/.config/hypr/hyprlock.conf" <<'HYPRLOCK'
# Live password: 1111
 auth {
    pam:module = anios-live
}
label {
# Nhắc mật khẩu live: remove this block
text = Mật khẩu phiên live: 1111
}
text = Hyprland live gaming desktop
HYPRLOCK
printf 'live desktop shortcut\n' >"$LIVE_ROOT/usr/share/anios/skel/Desktop/README.txt"
printf 'Sober shortcut\n' >"$LIVE_ROOT/usr/share/anios/skel/Desktop/Sober.desktop"
printf 'hyprland config\n' >"$LIVE_ROOT/usr/share/anios/skel/.config/hypr/hyprland.lua"

cat >"$INSTALLER_DATA/upstream/grubphemous/theme.txt" <<'THEME'
item_font = "Blasphemous Regular 30"
font = "Blasphemous Regular 20"
THEME
for asset in background.png blasphemous-regular-15.pf2 blasphemous-regular-20.pf2 blasphemous-regular-30.pf2; do
  printf 'theme asset\n' >"$INSTALLER_DATA/upstream/grubphemous/$asset"
done
printf 'MIT license\n' >"$INSTALLER_DATA/licenses/Grubphemous-LICENSE"
printf 'Font attribution\n' >"$INSTALLER_DATA/licenses/Grubphemous-README.md"
for script in anios-end4-first-login anios-end4-setup; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$INSTALLER_DATA/scripts/$script"
done

as_root() {
  local -a env_args=("PATH=$FAKE_BIN:$PATH" "ANIOS_LIVE_ROOT=$LIVE_ROOT" "ANIOS_INSTALLER_DATA=$INSTALLER_DATA")
  if (( EUID == 0 )); then
    env "${env_args[@]}" "$@"
  elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    sudo -n env "${env_args[@]}" "$@"
  else
    return 77
  fi
}

# The skeleton helper must strip the public Live lock password/PAM policy before
# Calamares creates a user, while preserving the Live source skeleton unchanged.
SKEL_ROOT="$SANDBOX/skeleton-target"
mkdir -p -- "$SKEL_ROOT"
if ! as_root "$ROOT_DIR/profile/installer/scripts/anios-installer-skel" "$SKEL_ROOT" imi; then
  fail "sanitized skeleton integration test failed"
fi
SKEL_OUTPUT="$SKEL_ROOT/etc/skel"
! grep -R -qE '1111|anios-live|live gaming desktop' "$SKEL_OUTPUT/.config/hypr" ||
  fail "Live-only password/PAM/branding leaked into the target skeleton"
[[ ! -e "$SKEL_OUTPUT/Desktop/README.txt" && ! -e "$SKEL_OUTPUT/Desktop/Sober.desktop" ]] ||
  fail "Live-only desktop shortcuts leaked into the target skeleton"
grep -q 'pam:module = hyprlock' "$SKEL_OUTPUT/.config/hypr/hyprlock.conf" ||
  fail "target skeleton did not switch to the normal Hyprlock PAM service"
[[ -s "$SKEL_ROOT/usr/share/wayland-sessions/anios.desktop" ]] ||
  fail "AniOS Wayland session was not installed before Calamares configures SDDM"
as_root test -x "$SKEL_ROOT/usr/local/bin/anios-session" ||
  fail "AniOS SDDM TryExec launcher was not installed before displaymanager setup"

# Exercise pacstrap argument parsing and multilib validation with a safe fake.
PACSTRAP_ROOT="$SANDBOX/pacstrap-target"
PACSTRAP_MANIFEST="$SANDBOX/packages.x86_64"
PACMAN_CONF="$SANDBOX/pacman.conf"
PACSTRAP_LOG="$SANDBOX/pacstrap-args"
mkdir -p -- "$PACSTRAP_ROOT"
printf '[options]\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >"$PACMAN_CONF"
printf '# target\nbase\nlib32-mesa\n' >"$PACSTRAP_MANIFEST"
if ! as_root env \
  ANIOS_TARGET_MANIFEST="$PACSTRAP_MANIFEST" \
  ANIOS_LIVE_PACMAN_CONF="$PACMAN_CONF" \
  ANIOS_TEST_PACSTRAP_LOG="$PACSTRAP_LOG" \
  "$PACSTRAP_HELPER" "$PACSTRAP_ROOT"; then
  if (( EUID != 0 )) && ! sudo -n true >/dev/null 2>&1; then
    echo "SKIP: root integration tests require passwordless sudo; static checks passed"
    exit 0
  fi
  fail "pacstrap helper integration test failed"
fi
mapfile -t pacstrap_args <"$PACSTRAP_LOG"
[[ "${pacstrap_args[0]}" == -K && "${pacstrap_args[1]}" == -C &&
  "${pacstrap_args[2]}" == "$PACMAN_CONF" && "${pacstrap_args[3]}" == "$PACSTRAP_ROOT" ]] ||
  fail "pacstrap helper passed invalid options/order: ${pacstrap_args[*]}"
! printf '%s\n' "${pacstrap_args[@]}" | grep -qxE -- '--needed|--noconfirm' ||
  fail "pacstrap does not accept pacman-only --needed/--noconfirm flags"
[[ -x "$PACSTRAP_ROOT/usr/bin/pacman" ]] || fail "fake pacstrap did not create target pacman"

make_target() {
  local root="$1"
  mkdir -p -- "$root/etc/default" "$root/etc/skel/.config/hypr" \
    "$root/usr/share/anios/skel/.config/hypr"
  cat >"$root/etc/passwd" <<'PASSWD'
root:x:0:0:root:/root:/bin/bash
demo:x:1001:1001:Demo:/home/demo:/bin/bash
PASSWD
  cat >"$root/etc/sddm.conf" <<'SDDM'
[Autologin]
Current=autologin-profile
[Theme]
Current=old-theme
SDDM
  printf '[Theme]\nCurrent=old-theme\n' >"$root/etc/sddm.conf.d.tmp"
  printf '[options]\n# [multilib]\n# Include = /etc/pacman.d/mirrorlist\n' >"$root/etc/pacman.conf"
  printf 'NAME="Arch Linux"\nPRETTY_NAME="Arch Linux"\nID=arch\n' >"$root/etc/os-release"
  printf 'GRUB_THEME="old-theme"\nGRUB_FONT="old-font"\nGRUB_TERMINAL_OUTPUT=console\n' \
    >"$root/etc/default/grub"
  printf '%s\n' '-- installed-user-config --' >"$root/usr/share/anios/skel/.config/hypr/hyprland.lua"
  printf '%s\n' '-- initial-skel --' >"$root/etc/skel/.config/hypr/hyprland.lua"
}

# Exercise both branches: selected Gorgeous-GRUB + qylock + end-4, then default
# GRUB + AniOS SDDM + bundled Immaterial Impulse.
GORGEOUS_ROOT="$SANDBOX/gorgeous-target"
make_target "$GORGEOUS_ROOT"
if ! as_root "$FINALIZE_HELPER" "$GORGEOUS_ROOT" demo gorgeous-grubphemous wuwa end4; then
  fail "finalizer integration test (Gorgeous-GRUB/qylock/end-4) failed"
fi
grep -q '^GRUB_THEME="/boot/grub/themes/anios-grubphemous/theme.txt"$' "$GORGEOUS_ROOT/etc/default/grub" ||
  fail "Gorgeous-GRUB selection did not configure GRUB_THEME"
grep -q '^GRUB_FONT="/boot/grub/themes/anios-grubphemous/blasphemous-regular-30.pf2"$' "$GORGEOUS_ROOT/etc/default/grub" ||
  fail "Gorgeous-GRUB selection did not configure its bundled font"
grep -q '^GRUB_TERMINAL_OUTPUT="gfxterm"$' "$GORGEOUS_ROOT/etc/default/grub" ||
  fail "Gorgeous-GRUB selection did not enable gfxterm"
grep -q '^Current=autologin-profile$' "$GORGEOUS_ROOT/etc/sddm.conf" ||
  fail "SDDM finalizer changed a setting outside the [Theme] section"
grep -q '^Current=wuwa$' "$GORGEOUS_ROOT/etc/sddm.conf" ||
  fail "Qylock selection did not configure the SDDM theme"
grep -qxF 'Include = /etc/pacman.d/mirrorlist' "$GORGEOUS_ROOT/etc/pacman.conf" ||
  fail "target multilib repository was not enabled"
grep -qxF 'NAME="AniOS"' "$GORGEOUS_ROOT/etc/os-release" || fail "target identity was not branded AniOS"
grep -qF 'Blasphemous Regular 30' "$GORGEOUS_ROOT/boot/grub/themes/anios-grubphemous/theme.txt" ||
  fail "GRUB theme compatibility font size was not normalized"
[[ -s "$GORGEOUS_ROOT/usr/share/licenses/anios/grubphemous/README.md" ]] ||
  fail "upstream font attribution was not installed"
as_root test -x "$GORGEOUS_ROOT/usr/local/bin/anios-end4-setup" ||
  fail "end-4 setup helper was not installed for the target user"
as_root test -f "$GORGEOUS_ROOT/home/demo/.config/anios/end4-setup-pending" ||
  fail "end-4 first-login marker was not staged for the target user"

DEFAULT_ROOT="$SANDBOX/default-target"
make_target "$DEFAULT_ROOT"
if ! as_root "$FINALIZE_HELPER" "$DEFAULT_ROOT" demo default anios imi; then
  fail "finalizer integration test (default GRUB/AniOS/IMI) failed"
fi
! grep -qE '^[[:space:]]*GRUB_(THEME|FONT)[[:space:]]*=' "$DEFAULT_ROOT/etc/default/grub" ||
  fail "default GRUB selection left a custom theme/font enabled"
grep -q '^GRUB_TERMINAL_OUTPUT="console"$' "$DEFAULT_ROOT/etc/default/grub" ||
  fail "default GRUB selection did not restore console output"
grep -q '^Current=anios$' "$DEFAULT_ROOT/etc/sddm.conf" ||
  fail "AniOS SDDM selection was not applied"
if as_root test -e "$DEFAULT_ROOT/usr/local/bin/anios-end4-setup" ||
  as_root test -e "$DEFAULT_ROOT/home/demo/.config/anios/end4-setup-pending"; then
  fail "end-4 helpers were installed despite choosing the bundled dotfiles"
fi

pass "installer helpers, Calamares choices, pacstrap, GRUB/SDDM and dotfiles checks passed"
