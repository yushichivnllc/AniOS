#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
AIROOTFS="$ROOT_DIR/profile/airootfs"
BRANDING="$ROOT_DIR/profile/branding"
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

[[ -s "$ROOT_DIR/profile/packages.x86_64" ]] || fail "package manifest is missing or empty"
[[ -d "$AIROOTFS" ]] || fail "airootfs overlay is missing"

# --- Danh sách gói ---------------------------------------------------------
for package in \
  linux-zen shadow steam hyprland networkmanager waybar sddm hyprlock \
  qt6-declarative qt6-multimedia qt6-multimedia-ffmpeg qt6-5compat \
  gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly \
  fcitx5 fcitx5-unikey ibus ibus-unikey xf86-video-fbdev xf86-video-vesa \
  udisks2 thunar-volman gvfs rsync fastfetch \
  xorg-xwayland ttf-nerd-fonts-symbols firefox curl wget unzip; do
  grep -qxF "$package" "$ROOT_DIR/profile/packages.x86_64" || fail "required package missing: $package"
done
! grep -qxF linux "$ROOT_DIR/profile/packages.x86_64" || fail "manifest must not request the generic linux kernel"
! grep -qxF greetd "$ROOT_DIR/profile/packages.x86_64" || fail "greetd must be removed when using SDDM"
! grep -qxF greetd-tuigreet "$ROOT_DIR/profile/packages.x86_64" || fail "greetd-tuigreet must be removed when using SDDM"

# Pin the build script's stock-Archiso kernel path rewrite, including fallback images.
rewritten="$(printf '%s\n' 'linux /arch/boot/x86_64/vmlinuz-linux' 'initrd /arch/boot/x86_64/initramfs-linux.img' 'initrd /arch/boot/x86_64/initramfs-linux-fallback.img' | sed -E 's/(vmlinuz|initramfs)-linux(-fallback)?([.]|[[:space:]]|$)/\1-linux-zen\2\3/g')"
expected="$(printf '%s\n' 'linux /arch/boot/x86_64/vmlinuz-linux-zen' 'initrd /arch/boot/x86_64/initramfs-linux-zen.img' 'initrd /arch/boot/x86_64/initramfs-linux-zen-fallback.img')"
[[ "$rewritten" == "$expected" ]] || fail "boot-entry rewrite does not select linux-zen"

# Pin luôn quy tắc đổi tên mục menu khởi động của build script.
rebranded="$(printf '%s\n' \
  'MENU TITLE Arch Linux' \
  'MENU LABEL Arch Linux install medium (%ARCH%, BIOS)' \
  'MENU LABEL Arch Linux live medium (%ARCH%, NFS)' \
  'title    Arch Linux install medium (%ARCH%, UEFI)' \
  'menuentry "Arch Linux install medium (%ARCH%, BIOS)"' |
  sed -E \
    -e 's/Arch Linux install medium/AniOS Live/g' \
    -e 's/Arch Linux live medium/AniOS Live/g' \
    -e 's/^(MENU TITLE )Arch Linux$/\1AniOS/')"
expected="$(printf '%s\n' \
  'MENU TITLE AniOS' \
  'MENU LABEL AniOS Live (%ARCH%, BIOS)' \
  'MENU LABEL AniOS Live (%ARCH%, NFS)' \
  'title    AniOS Live (%ARCH%, UEFI)' \
  'menuentry "AniOS Live (%ARCH%, BIOS)"')"
[[ "$rebranded" == "$expected" ]] || fail "boot-menu rebranding does not produce AniOS labels"

# mkarchiso chép airootfs bằng `cp --no-preserve=mode`: bit thực thi chỉ sống
# sót nếu build script khai báo lại trong file_permissions.
for declaration in \
  '["/etc/sudoers.d/10-anios-live"]="0:0:440"' \
  '["/usr/local/bin/anios-session"]="0:0:755"' \
  '["/usr/local/bin/anios-setup"]="0:0:755"' \
  '["/usr/local/bin/anios-switch-im"]="0:0:755"' \
  '["/usr/local/lib/anios/create-live-user"]="0:0:755"' \
  '["/usr/local/lib/anios/live-home-setup"]="0:0:755"'; do
  grep -qF "$declaration" "$ROOT_DIR/scripts/build-iso.sh" ||
    fail "build script does not declare file permission $declaration"
done

SUDOERS="$AIROOTFS/etc/sudoers.d/10-anios-live"
[[ -s "$SUDOERS" ]] || fail "live sudoers policy is missing"
grep -qxF 'anios ALL=(ALL:ALL) PASSWD: ALL' "$SUDOERS" ||
  fail "sudo must require the live user's password"
! grep -qF 'NOPASSWD' "$SUDOERS" || fail "live sudoers policy must not bypass password authentication"

# Ensure each additional package is a single, uncommented package name.
if grep -nEv '^[[:space:]]*($|#|[a-zA-Z0-9@._+-]+$)' "$ROOT_DIR/profile/packages.x86_64"; then
  fail "invalid line in package manifest"
fi

# --- Cú pháp shell --------------------------------------------------------
while IFS= read -r -d '' script; do
  bash -n "$script" || fail "shell syntax error: $script"
done < <(find "$ROOT_DIR/scripts" "$AIROOTFS/usr/local" -type f -print0 2>/dev/null)

# --- Danh tính AniOS ------------------------------------------------------
OS_RELEASE="$AIROOTFS/etc/os-release"
[[ -s "$OS_RELEASE" ]] || fail "AniOS identity file is missing: etc/os-release"
grep -qxF 'NAME="AniOS"' "$OS_RELEASE" || fail 'os-release must name the distribution "AniOS"'
grep -qxF 'PRETTY_NAME="AniOS (Arch Linux based, Hyprland live gaming desktop)"' "$OS_RELEASE" ||
  fail "os-release PRETTY_NAME must introduce AniOS without hiding the Arch base"
grep -qxF 'ID=arch' "$OS_RELEASE" || fail "os-release ID must stay arch so Arch tooling keeps working"
grep -qxF 'ID_LIKE=arch' "$OS_RELEASE" || fail "os-release ID_LIKE must stay arch"
for key in HOME_URL SUPPORT_URL BUG_REPORT_URL; do
  grep -qE "^${key}=\"https://" "$OS_RELEASE" || fail "os-release is missing $key"
done
grep -qF 'Arch Linux' "$AIROOTFS/etc/issue" || fail "console login banner must mention the Arch Linux base"
grep -qF 'AniOS' "$AIROOTFS/etc/issue" || fail "console login banner must show the AniOS name"
grep -qF 'AniOS' "$AIROOTFS/etc/motd" || fail "motd must show the AniOS name"
[[ -s "$AIROOTFS/usr/share/anios/logo.txt" ]] || fail "fastfetch logo is missing"

# --- Ảnh thương hiệu ------------------------------------------------------
for asset in wallpaper.png syslinux-splash.png; do
  asset_path="$BRANDING/$asset"
  [[ -s "$asset_path" ]] ||
    fail "branding asset is missing: profile/branding/$asset (run scripts/make-branding-assets.sh)"
  [[ "$(head -c 8 -- "$asset_path" | od -An -tx1 | tr -d ' \n')" == 89504e470d0a1a0a ]] ||
    fail "profile/branding/$asset is not a PNG file"
done
if command -v identify >/dev/null 2>&1; then
  geometry="$(identify -format '%wx%h' "$BRANDING/syslinux-splash.png")"
  [[ "$geometry" == "640x480" ]] || fail "syslinux splash must be 640x480, found $geometry"
  geometry="$(identify -format '%wx%h' "$BRANDING/wallpaper.png")"
  [[ "$geometry" == "2560x1440" ]] || fail "live wallpaper must be 2560x1440, found $geometry"
fi

# --- SDDM, phiên live và giao diện đăng nhập ------------------------------
for file in \
  "$AIROOTFS/etc/sddm.conf.d/10-anios-autologin.conf" \
  "$AIROOTFS/etc/NetworkManager/conf.d/20-anios-wifi.conf" \
  "$AIROOTFS/etc/systemd/sysusers.d/anios.conf" \
  "$AIROOTFS/etc/tmpfiles.d/anios.conf" \
  "$AIROOTFS/etc/systemd/zram-generator.conf" \
  "$AIROOTFS/etc/sysctl.d/90-anios-live.conf" \
  "$AIROOTFS/usr/share/wayland-sessions/anios.desktop"; do
  [[ -s "$file" ]] || fail "expected configuration missing: ${file#"$ROOT_DIR/"}"
done

SDDM_CONFIG="$AIROOTFS/etc/sddm.conf.d/10-anios-autologin.conf"
grep -qxF '[Autologin]' "$SDDM_CONFIG" || fail "SDDM autologin section is missing"
grep -qxF 'User=anios' "$SDDM_CONFIG" || fail "SDDM must autologin the live user"
grep -qxF 'Session=anios' "$SDDM_CONFIG" || fail "SDDM must start the AniOS Wayland session"
grep -qxF 'Current=wuwa' "$SDDM_CONFIG" || fail "SDDM must use the Wuthering Waves theme"
[[ -s "$AIROOTFS/usr/share/sddm/themes/anios/Main.qml" ]] || fail "legacy AniOS SDDM theme Main.qml is missing"
[[ -s "$AIROOTFS/usr/share/sddm/themes/anios/theme.conf" ]] || fail "SDDM theme.conf is missing"
THEME_CONF="$AIROOTFS/usr/share/sddm/themes/anios/theme.conf"
grep -qxF '[General]' "$THEME_CONF" || fail "SDDM theme.conf is missing its [General] section"
grep -qxF 'background=/usr/share/anios/wallpaper.png' "$THEME_CONF" ||
  fail "SDDM theme must use the AniOS live wallpaper"
THEME_QML="$AIROOTFS/usr/share/sddm/themes/anios/Main.qml"
grep -qxF 'import SddmComponents 2.0' "$THEME_QML" || fail "SDDM theme must import SddmComponents 2.0"
grep -qF 'sddm.login(' "$THEME_QML" || fail "SDDM theme never calls sddm.login()"
grep -qF 'config.background' "$THEME_QML" || fail "SDDM theme must read background from theme.conf"

# Qylock Wuthering Waves theme uses Qt 6 multimedia. Load the static frame
# first and defer MP4 decoding so a missing/slow codec cannot blank the greeter.
WUWA_DIR="$AIROOTFS/usr/share/sddm/themes/wuwa"
for file in Main.qml theme.conf metadata.desktop bg.mp4 fallback.png logo.png LICENSE UPSTREAM \
  font/Orbitron-VariableFont_wght.ttf; do
  [[ -s "$WUWA_DIR/$file" ]] || fail "Wuthering Waves SDDM theme asset is missing: $file"
done
WUWA_QML="$WUWA_DIR/Main.qml"
grep -qF 'import QtMultimedia' "$WUWA_QML" || fail "Wuthering Waves theme must import Qt Multimedia"
grep -qF 'source: Qt.resolvedUrl("fallback.png")' "$WUWA_QML" ||
  fail "Wuthering Waves theme must show a static fallback background"
grep -qF 'interval: 1200' "$WUWA_QML" || fail "Wuthering Waves video must be deferred until after greeter startup"
grep -qF 'bgVideoPlayer.source = Qt.resolvedUrl("bg.mp4")' "$WUWA_QML" ||
  fail "Wuthering Waves background video must use its installed asset"
grep -qF 'onErrorOccurred: root.videoReady = false' "$WUWA_QML" ||
  fail "Wuthering Waves theme must keep its fallback when video decoding fails"
grep -qF 'sddm.login(uname, passIn.text, root.sessionIndex)' "$WUWA_QML" ||
  fail "Wuthering Waves theme must submit credentials to SDDM"

grep -qxF 'Exec=/usr/local/bin/anios-session' "$AIROOTFS/usr/share/wayland-sessions/anios.desktop" ||
  fail "AniOS SDDM session must start anios-session"
grep -qxF 'TryExec=/usr/local/bin/anios-session' "$AIROOTFS/usr/share/wayland-sessions/anios.desktop" ||
  fail "AniOS SDDM session must advertise anios-session as TryExec"
[[ -x "$AIROOTFS/usr/local/bin/anios-session" ]] || fail "anios-session must be executable"
[[ -x "$AIROOTFS/usr/local/bin/anios-setup" ]] || fail "anios-setup must be executable"
[[ -x "$AIROOTFS/usr/local/bin/anios-switch-im" ]] || fail "anios-switch-im must be executable"
[[ -x "$AIROOTFS/usr/local/lib/anios/live-home-setup" ]] || fail "live-home-setup must be executable"

DISPLAY_MANAGER="$AIROOTFS/etc/systemd/system/display-manager.service"
[[ -L "$DISPLAY_MANAGER" ]] || fail "display-manager service symlink is missing"
[[ "$(readlink "$DISPLAY_MANAGER")" == /usr/lib/systemd/system/sddm.service ]] ||
  fail "display-manager must point to sddm.service"
[[ -L "$AIROOTFS/etc/systemd/system/graphical.target.wants/sddm.service" ]] ||
  fail "sddm.service is not enabled for graphical.target"
[[ ! -e "$AIROOTFS/etc/greetd/config.toml" ]] || fail "stale greetd configuration must be removed"

# Fixes for SDDM: UID 1000, MinimumUid, non-conflicting tty1
grep -qxF 'u anios 1000 "AniOS Live User" /home/anios /bin/bash' "$AIROOTFS/etc/systemd/sysusers.d/anios.conf" ||
  fail "anios user must have standard UID 1000 for SDDM greeter discovery"
grep -qxF 'MinimumUid=500' "$SDDM_CONFIG" || fail "SDDM must accept users with UID >= 500"
grep -qF 'getty@tty1.service.d' "$ROOT_DIR/scripts/build-iso.sh" ||
  fail "build-iso.sh must remove releng getty autologin so SDDM can use tty1"

# /home/anios nằm trên lớp ghi tạm của hệ thống live, nên tài khoản live cần một
# unit nhỏ chạy trước SDDM để chép skel còn thiếu và chuyển quyền sở hữu.
LIVE_HOME_UNIT="$AIROOTFS/etc/systemd/system/anios-live-home.service"
[[ -s "$LIVE_HOME_UNIT" ]] || fail "anios-live-home.service is missing"
[[ -s "$AIROOTFS/usr/lib/systemd/system/anios-live-home.service" ]] ||
  fail "anios-live-home.service must exist in /usr/lib/systemd/system"
grep -qxF 'Before=sddm.service' "$LIVE_HOME_UNIT" || fail "the live home setup must run before SDDM"
grep -qxF 'ExecStart=/usr/local/lib/anios/live-home-setup' "$LIVE_HOME_UNIT" ||
  fail "the live home service must run live-home-setup"
[[ -L "$AIROOTFS/etc/systemd/system/multi-user.target.wants/anios-live-home.service" ]] ||
  fail "anios-live-home.service is not enabled"
LIVE_HOME_SETUP="$AIROOTFS/usr/local/lib/anios/live-home-setup"
grep -qF '/usr/share/anios/skel' "$LIVE_HOME_SETUP" || fail "live-home-setup must use the AniOS skeleton"
grep -qF 'chown -R' "$LIVE_HOME_SETUP" || fail "live-home-setup must give the live user ownership of its home"
# Đặt mật khẩu sau khi sysusers tạo tài khoản, trước khi SDDM khởi động.
grep -qF 'password=1111' "$LIVE_HOME_SETUP" ||
  fail "live-home-setup must configure the requested live password"
grep -qF 'chpasswd' "$LIVE_HOME_SETUP" ||
  fail "live-home-setup must apply the live password"

# --- Mật khẩu 1111 có sẵn trong ảnh từ lúc build --------------------------
# Đăng nhập thủ công SDDM (stack PAM `sddm` -> pam_unix) đòi hỏi /etc/shadow
# phải có hash mật khẩu, trong khi autologin (stack `sddm-autologin` ->
# pam_permit) thì không. Vì vậy mật khẩu phải được "nướng" vào ảnh lúc build
# bằng pacman hook, không được phụ thuộc duy nhất vào service lúc khởi động:
# nếu service hỏng, autologin vẫn đưa người dùng vào desktop nhưng đăng nhập
# lại bằng tay sẽ luôn bị báo access denied.
BUILD_HOOK="$AIROOTFS/etc/pacman.d/hooks/anios-live-user.hook"
[[ -s "$BUILD_HOOK" ]] || fail "anios-live-user.hook is missing"
grep -qF 'remove from airootfs' "$BUILD_HOOK" ||
  fail "anios-live-user.hook must carry the releng marker so it is removed after the build"
grep -qxF 'Target = shadow' "$BUILD_HOOK" ||
  fail "anios-live-user.hook must trigger when the shadow package is installed"
grep -qxF 'When = PostTransaction' "$BUILD_HOOK" ||
  fail "anios-live-user.hook must run after the pacman transaction"
grep -qxF 'Exec = /usr/local/lib/anios/create-live-user' "$BUILD_HOOK" ||
  fail "anios-live-user.hook must run create-live-user"
CREATE_LIVE_USER="$AIROOTFS/usr/local/lib/anios/create-live-user"
[[ -x "$CREATE_LIVE_USER" ]] || fail "create-live-user must be executable"
grep -qF 'useradd -u 1000' "$CREATE_LIVE_USER" ||
  fail "create-live-user must create the live user with standard UID 1000"
grep -qF 'password=1111' "$CREATE_LIVE_USER" ||
  fail "create-live-user must configure the requested live password"
grep -qF 'chpasswd' "$CREATE_LIVE_USER" ||
  fail "create-live-user must apply the live password"

PAM_LIVE="$AIROOTFS/etc/pam.d/anios-live"
[[ -s "$PAM_LIVE" ]] || fail "the AniOS PAM service for the lock screen is missing"
grep -qF 'pam_unix.so' "$PAM_LIVE" ||
  fail "the lock screen must authenticate with the live user's password"
! grep -qF 'pam_permit.so' "$PAM_LIVE" ||
  fail "the live lock screen must not bypass password authentication"

# --- Cài sẵn dotfile ------------------------------------------------------
SKEL="$AIROOTFS/usr/share/anios/skel"
for dotfile in \
  .bashrc .bash_profile .profile .gitconfig .vimrc .nanorc \
  .config/kitty/kitty.conf .config/fish/config.fish \
  .config/fastfetch/config.jsonc .config/MangoHud/MangoHud.conf \
  .config/gamemode.ini; do
  [[ -s "$SKEL/$dotfile" ]] || fail "cài sẵn dotfile bị thiếu: $dotfile"
done

# --- Cấu hình desktop -----------------------------------------------------
# Hyprland 0.55 trở lên đọc cấu hình Lua (hyprland.lua); định dạng hyprlang
# (.conf) đã bị thay thế, nên cả hai bản skel chỉ được phép có file .lua.
HYPR_CONF="$AIROOTFS/usr/share/anios/skel/.config/hypr/hyprland.lua"
[[ -s "$HYPR_CONF" ]] || fail "hyprland.lua is missing; Hyprland now reads the Lua config"
grep -qF '/usr/share/anios/wallpaper.png' "$HYPR_CONF" || fail "Hyprland must set the AniOS wallpaper"
grep -qF 'fcitx5 -d' "$HYPR_CONF" || fail "Hyprland must start fcitx5 for Vietnamese input"
grep -qF 'hl.dsp.exec_cmd("hyprlock")' "$HYPR_CONF" || fail "Hyprland must offer the lock screen"
grep -qF 'hl.exec_cmd("waybar")' "$HYPR_CONF" || fail "Hyprland must start the status bar"
grep -qF 'hl.dsp.exec_cmd(menu)' "$HYPR_CONF" || fail "Hyprland launcher keybind is missing"

# Cú pháp Lua sai sẽ đẩy Hyprland vào màn hình khẩn cấp, nên kiểm tra ngay
# khi máy dựng có sẵn trình thông dịch Lua (gói lua của Arch).
for hypr_lua in \
  "$AIROOTFS/usr/share/anios/skel/.config/hypr/hyprland.lua" \
  "$AIROOTFS/etc/skel/.config/hypr/hyprland.lua"; do
  [[ -s "$hypr_lua" ]] || fail "missing Hyprland config: $hypr_lua"
  [[ ! -e "${hypr_lua%.lua}.conf" ]] ||
    fail "obsolete Hyprland config ${hypr_lua%.lua}.conf: Hyprland now reads hyprland.lua"
  if command -v luac >/dev/null 2>&1; then
    luac -p "$hypr_lua" || fail "Lua syntax error in $hypr_lua"
  elif command -v lua >/dev/null 2>&1; then
    lua -e "assert(loadfile('$hypr_lua'))" || fail "Lua syntax error in $hypr_lua"
  fi
done

# hyprlock thoát ngay nếu không tìm thấy hyprlock.conf, nên phím tắt khoá màn
# hình chỉ có ý nghĩa khi file cấu hình đi kèm tồn tại.
HYPRLOCK_CONF="$AIROOTFS/usr/share/anios/skel/.config/hypr/hyprlock.conf"
[[ -s "$HYPRLOCK_CONF" ]] || fail "hyprlock.conf is missing; the lock keybind would do nothing"
grep -qF 'ignore_empty_input = false' "$HYPRLOCK_CONF" ||
  fail "the live lock screen must require a password"
grep -qF '/usr/share/anios/wallpaper.png' "$HYPRLOCK_CONF" ||
  fail "the lock screen must reuse the AniOS wallpaper"
grep -qF 'pam:module = anios-live' "$HYPRLOCK_CONF" ||
  fail "the lock screen must use the AniOS PAM service"

# Unikey phải là bộ gõ mặc định, nếu không người dùng phải tự thêm vào fcitx5.
FCITX_PROFILE="$AIROOTFS/usr/share/anios/skel/.config/fcitx5/profile"
[[ -s "$FCITX_PROFILE" ]] || fail "the fcitx5 profile for the live user is missing"
grep -qxF 'DefaultIM=unikey' "$FCITX_PROFILE" || fail "Unikey must be the default input method"
grep -qxF 'Name=unikey' "$FCITX_PROFILE" || fail "the Unikey input method is not registered in fcitx5"

# Bộ gõ chỉ được bật trong phiên của người dùng, không đặt ở /etc/environment:
# greeter SDDM chạy dưới tài khoản riêng và không nên nạp module fcitx5.
SESSION_WRAPPER="$AIROOTFS/usr/local/bin/anios-session"
grep -qF 'dbus-run-session' "$SESSION_WRAPPER" || fail "the session must run inside dbus-run-session"
for assignment in \
  'export GTK_IM_MODULE=fcitx' \
  'export QT_IM_MODULE=fcitx' \
  'export XMODIFIERS=@im=fcitx' \
  'export SDL_IM_MODULE=fcitx'; do
  grep -qxF "$assignment" "$SESSION_WRAPPER" || fail "anios-session is missing: $assignment"
done
[[ ! -e "$AIROOTFS/etc/environment" ]] ||
  fail "input-method variables must not leak into the SDDM greeter via /etc/environment"

[[ -s "$AIROOTFS/usr/share/applications/anios-setup.desktop" ]] || fail "the Immaterial Impulse shortcut is missing"
[[ -s "$AIROOTFS/usr/share/anios/skel/Desktop/README.txt" ]] || fail "the live desktop readme is missing"

# --- Quyền của script dựng ISO -------------------------------------------
[[ -x "$ROOT_DIR/scripts/build-iso.sh" ]] || fail "build script is not executable"
[[ -x "$ROOT_DIR/scripts/check-profile.sh" ]] || fail "check script is not executable"

pass "AniOS profile checks passed (ISO build still requires Arch Linux + archiso)"
