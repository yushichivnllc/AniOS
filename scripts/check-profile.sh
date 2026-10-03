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
  linux-zen arch-install-scripts btrfs-progs cryptsetup e2fsprogs efibootmgr gptfdisk \
  lvm2 parted shadow steam hyprland networkmanager waybar sddm hyprlock \
  qt6-declarative qt6-multimedia qt6-multimedia-ffmpeg qt6-5compat \
  gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly \
  fcitx5 fcitx5-unikey ibus ibus-unikey xf86-video-fbdev xf86-video-vesa \
  udisks2 thunar-volman gvfs rsync fastfetch \
  xorg-xwayland ttf-nerd-fonts-symbols firefox ffmpeg mpv gnome-disk-utility flatpak curl wget unzip \
  pipewire pipewire-audio pipewire-alsa pipewire-pulse wireplumber alsa-utils libpulse rtkit \
  quickshell matugen kirigami syntax-highlighting qt6-positioning qt6-virtualkeyboard \
  qt6-imageformats kimageformats libavif qt6-quicktimeline qt6-sensors qt6-tools qt6-translations \
  kdialog ttf-jetbrains-mono-nerd adw-gtk-theme upower libqalculate hyprpicker hyprsunset cava wtype ripgrep eza gnome-keyring \
  python python-pip nodejs npm wine winetricks flatpak \
  base-devel jre-openjdk qt5-base ttf-liberation; do
  grep -qxF "$package" "$ROOT_DIR/profile/packages.x86_64" || fail "required package missing: $package"
done
! grep -qxF linux "$ROOT_DIR/profile/packages.x86_64" || fail "manifest must not request the generic linux kernel"
! grep -qxF greetd "$ROOT_DIR/profile/packages.x86_64" || fail "greetd must be removed when using SDDM"
! grep -qxF greetd-tuigreet "$ROOT_DIR/profile/packages.x86_64" || fail "greetd-tuigreet must be removed when using SDDM"
# wlogout is AUR-only, so pacstrap cannot resolve it from the official Arch
# repositories. The Quickshell session screen already provides the logout menu.
! grep -qxF wlogout "$ROOT_DIR/profile/packages.x86_64" || fail "wlogout is AUR-only; use the built-in Quickshell session menu"
# packages.x86_64 được pacstrap đọc trực tiếp nên CHỈ được chứa gói của kho chính
# thức. Gói AUR phải nằm trong profile/packages.aur.x86_64, nơi
# scripts/anios-aur-build.sh dựng chúng bằng makepkg bên trong chroot.
for aur_only in calamares yay yay-bin coccoc-browser-stable legacy-launcher; do
  ! grep -qxF "$aur_only" "$ROOT_DIR/profile/packages.x86_64" ||
    fail "$aur_only only exists in the AUR; pacstrap cannot resolve it. Move it to profile/packages.aur.x86_64"
done
KEYBINDS="$AIROOTFS/usr/share/anios/skel/.config/hypr/hyprland/keybinds.lua"
for keybinds in "$KEYBINDS" "$AIROOTFS/etc/skel/.config/hypr/hyprland/keybinds.lua"; do
  grep -qF 'hl.dsp.global("quickshell:sessionToggle")' "$keybinds" ||
    fail "Ctrl+Alt+Delete must open the built-in Quickshell session menu: $keybinds"
  ! grep -qF 'wlogout' "$keybinds" ||
    fail "keybinds must not depend on the AUR-only wlogout package: $keybinds"
done

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
  '["/usr/local/bin/anios-boot-choice"]="0:0:755"' \
  '["/usr/local/bin/anios-setup"]="0:0:755"' \
  '["/usr/local/bin/anios-switch-desktop"]="0:0:755"' \
  '["/usr/local/bin/anios-switch-im"]="0:0:755"' \
  '["/usr/local/bin/anios-audio-setup"]="0:0:755"' \
  '["/usr/local/bin/anios-audio-check"]="0:0:755"' \
  '["/usr/local/bin/anios-persist"]="0:0:755"' \
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
done < <(find "$ROOT_DIR/scripts" "$AIROOTFS/usr/local" \
  "$ROOT_DIR/profile/installer/scripts" -type f -print0 2>/dev/null)

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
  "$AIROOTFS/etc/udev/rules.d/60-anios-usb-readahead.rules" \
  "$AIROOTFS/etc/systemd/system.conf.d/90-anios.conf" \
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

# Theme GRUB Evangelion (Ayanami) từ Aleph1-9012/Evangelion (1080p) dùng khi mở AniOS.
GRUB_AYANAMI_DIR="$AIROOTFS/usr/share/grub/themes/ayanami"
for file in theme.txt background.png UPSTREAM LICENSE NOTICE.md \
  fonts/ayanami-1080p-menu.pf2 fonts/ayanami-1080p-timer.pf2 fonts/terminal.pf2 \
  icons/evangelion-index-01.png icons/evangelion-index-02.png; do
  [[ -s "$GRUB_AYANAMI_DIR/$file" ]] ||
    fail "Evangelion Ayanami GRUB theme asset is missing: $file"
done
grep -qF 'Evangelion ayanami-1080p-menu Regular 38' "$GRUB_AYANAMI_DIR/theme.txt" ||
  fail "Evangelion Ayanami GRUB theme.txt must configure the Ayanami menu font"
[[ -x "$AIROOTFS/etc/grub.d/99_anios_evangelion" ]] ||
  fail "etc/grub.d/99_anios_evangelion must be executable"
[[ -x "$AIROOTFS/usr/local/bin/anios-update" ]] ||
  fail "usr/local/bin/anios-update must be executable"

grep -qxF 'Exec=/usr/local/bin/anios-session' "$AIROOTFS/usr/share/wayland-sessions/anios.desktop" ||
  fail "AniOS SDDM session must start anios-session"
grep -qxF 'TryExec=/usr/local/bin/anios-session' "$AIROOTFS/usr/share/wayland-sessions/anios.desktop" ||
  fail "AniOS SDDM session must advertise anios-session as TryExec"
[[ -x "$AIROOTFS/usr/local/bin/anios-session" ]] || fail "anios-session must be executable"
[[ -x "$AIROOTFS/usr/local/bin/anios-setup" ]] || fail "anios-setup must be executable"
[[ -x "$AIROOTFS/usr/local/bin/anios-persist" ]] || fail "anios-persist must be executable"
# Ổ lưu dữ liệu trên USB: nhãn phải khớp giữa công cụ tạo phân vùng và menu khởi động.
grep -qF 'LABEL=ANIOS_PERSIST' "$AIROOTFS/usr/local/bin/anios-persist" ||
  fail "anios-persist must label the storage partition ANIOS_PERSIST"
# Sober (Flatpak org.vinegarhq.Sober): cài sẵn bằng hook lúc dựng, có launcher tự cài dự phòng.
[[ -x "$AIROOTFS/usr/local/bin/anios-sober" ]] || fail "anios-sober must be executable"
grep -qF 'org.vinegarhq.Sober' "$AIROOTFS/usr/local/bin/anios-sober" || fail "anios-sober must launch org.vinegarhq.Sober"
grep -qF 'flatpak install --system --noninteractive -y flathub org.vinegarhq.Sober' "$ROOT_DIR/scripts/build-iso.sh" ||
  fail "build-iso.sh must bake Sober into the image"
[[ -s "$AIROOTFS/etc/skel/Desktop/Sober.desktop" ]] || fail "the Sober desktop shortcut is missing"
# Seanime: server nướng sẵn ở /opt/seanime, chạy bằng service, và Firefox luôn mở
# giao diện web của nó (trang chủ + trang khởi động).
SEANIME_UNIT="$AIROOTFS/usr/lib/systemd/system/anios-seanime.service"
[[ -s "$SEANIME_UNIT" ]] || fail "anios-seanime.service is missing"
grep -qxF 'ExecStart=/opt/seanime/seanime --datadir /home/anios/.config/Seanime' "$SEANIME_UNIT" ||
  fail "anios-seanime.service must run /opt/seanime/seanime"
[[ -L "$AIROOTFS/etc/systemd/system/multi-user.target.wants/anios-seanime.service" ]] ||
  fail "anios-seanime.service is not enabled"
FIREFOX_POLICY="$AIROOTFS/etc/firefox/policies/policies.json"
[[ -s "$FIREFOX_POLICY" ]] || fail "Firefox policies.json is missing"
grep -qF '"URL": "http://127.0.0.1:43211/"' "$FIREFOX_POLICY" ||
  fail "Firefox homepage must be the Seanime web UI (http://127.0.0.1:43211/)"
grep -qF '"StartPage": "homepage"' "$FIREFOX_POLICY" ||
  fail "Firefox must open the homepage on every start"
grep -qF 'seanime-${SEANIME_VERSION}_Linux_x86_64.tar.gz' "$ROOT_DIR/scripts/build-iso.sh" ||
  fail "build-iso.sh must download the Seanime server"
PERSIST_UNIT="$AIROOTFS/usr/lib/systemd/system/anios-persist.service"
[[ -s "$PERSIST_UNIT" ]] || fail "anios-persist.service is missing"
grep -qxF 'ExecStart=/usr/local/bin/anios-persist auto' "$PERSIST_UNIT" ||
  fail "anios-persist.service must run 'anios-persist auto'"
[[ -L "$AIROOTFS/etc/systemd/system/multi-user.target.wants/anios-persist.service" ]] ||
  fail "anios-persist.service is not enabled"
grep -qF 'copytoram=n' "$ROOT_DIR/scripts/build-iso.sh" ||
  fail "build-iso.sh must disable copytoram so the system is not loaded into RAM"
grep -qF 'cow_label=ANIOS_PERSIST' "$ROOT_DIR/scripts/build-iso.sh" ||
  fail "build-iso.sh must add cow_label=ANIOS_PERSIST boot entries"
[[ -x "$AIROOTFS/usr/local/bin/anios-switch-desktop" ]] || fail "anios-switch-desktop must be executable"
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
  .config/gamemode.ini \
  .config/quickshell/imi/shell.qml \
  .config/quickshell/imi/assets/images/default_wallpaper.png \
  .config/matugen/config.toml \
  .config/immaterial-impulse/config.json \
  .config/immaterial-impulse/plugin-state.json \
  .config/anios/desktop-mode \
  .local/state/quickshell/user/generated/colors.json \
  .local/state/quickshell/user/generated/color.txt \
  .local/state/quickshell/user/generated/wallpaper/path.txt \
  .config/starship.toml \
  .config/Kvantum/kvantum.kvconfig \
  .local/share/icons/immaterial-impulse.png; do
  [[ -s "$SKEL/$dotfile" ]] || fail "cài sẵn dotfile bị thiếu: $dotfile"
done
grep -qxF 'imi' "$SKEL/.config/anios/desktop-mode" ||
  fail "Immaterial Impulse (imi) must be the default desktop mode in .config/anios/desktop-mode"

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

# Chặn cấu hình cũ, rồi kiểm tra toàn bộ module và nạp thử cả hai desktop.
# luac -p riêng file chính không bắt được lỗi kiểu dữ liệu/tên option của hl.
for hypr_lua in \
  "$AIROOTFS/usr/share/anios/skel/.config/hypr/hyprland.lua" \
  "$AIROOTFS/etc/skel/.config/hypr/hyprland.lua"; do
  [[ -s "$hypr_lua" ]] || fail "missing Hyprland config: $hypr_lua"
  [[ ! -e "${hypr_lua%.lua}.conf" ]] ||
    fail "obsolete Hyprland config ${hypr_lua%.lua}.conf: Hyprland now reads hyprland.lua"
done
if command -v "${LUA:-lua}" >/dev/null 2>&1; then
  "$ROOT_DIR/scripts/check-hyprland.sh" || fail "Hyprland Lua validation failed"
else
  echo "WARN: skipping Hyprland Lua checks; install Lua or set LUA=/path/to/lua" >&2
fi

# --- Âm thanh của phiên live ---------------------------------------------
# Ảnh live không tự có dàn âm thanh chạy sẵn: unit người dùng của PipeWire chỉ
# được bật nhờ scriptlet `systemctl --global enable` của gói, mà scriptlet đó
# chạy trong chroot lúc pacstrap và hoàn toàn có thể không để lại symlink nào.
# Vì vậy chính profile phải bật sẵn chúng, nếu không phiên live câm hoàn toàn.
USER_UNITS="$AIROOTFS/etc/systemd/user"
AUDIO_DROPIN="$USER_UNITS/default.target.d/10-anios-audio.conf"
[[ -s "$AUDIO_DROPIN" ]] ||
  fail "the live audio default.target drop-in is missing: etc/systemd/user/default.target.d/10-anios-audio.conf"
for want in pipewire.service pipewire-pulse.service wireplumber.service anios-audio-setup.service; do
  grep -q "Wants=.*${want}" "$AUDIO_DROPIN" ||
    fail "the audio drop-in must pull in ${want}"
done
grep -qxF 'After=pipewire.service pipewire-pulse.service wireplumber.service' "$AUDIO_DROPIN" ||
  fail "the audio drop-in must start after the PipeWire units"

check_unit_link() {
  local link="$USER_UNITS/$1" want="$2"
  [[ -L "$link" ]] ||
    fail "missing enabled audio user unit: etc/systemd/user/$1"
  [[ "$(readlink "$link")" == "$want" ]] ||
    fail "etc/systemd/user/$1 points at $(readlink "$link") instead of $want"
}
check_unit_link "default.target.wants/pipewire.service" "/usr/lib/systemd/user/pipewire.service"
check_unit_link "default.target.wants/pipewire-pulse.service" "/usr/lib/systemd/user/pipewire-pulse.service"
check_unit_link "default.target.wants/anios-audio-setup.service" "/etc/systemd/user/anios-audio-setup.service"
check_unit_link "sockets.target.wants/pipewire.socket" "/usr/lib/systemd/user/pipewire.socket"
check_unit_link "sockets.target.wants/pipewire-pulse.socket" "/usr/lib/systemd/user/pipewire-pulse.socket"
check_unit_link "pipewire.service.wants/wireplumber.service" "/usr/lib/systemd/user/wireplumber.service"
# Alias mà pipewire-pulse.service mong đợi (Wants=pipewire-session-manager.service).
check_unit_link "pipewire-session-manager.service" "/usr/lib/systemd/user/wireplumber.service"

AUDIO_UNIT="$USER_UNITS/anios-audio-setup.service"
[[ -s "$AUDIO_UNIT" ]] || fail "the AniOS live audio setup user unit is missing"
grep -qxF 'ExecStart=/usr/local/bin/anios-audio-setup' "$AUDIO_UNIT" ||
  fail "the audio setup unit must run anios-audio-setup"
grep -qxF 'WantedBy=default.target' "$AUDIO_UNIT" ||
  fail "the audio setup unit must be started with the user session"

AUDIO_SETUP="$AIROOTFS/usr/local/bin/anios-audio-setup"
AUDIO_CHECK="$AIROOTFS/usr/local/bin/anios-audio-check"
[[ -x "$AUDIO_SETUP" ]] || fail "anios-audio-setup must be executable"
[[ -x "$AUDIO_CHECK" ]] || fail "anios-audio-check must be executable"
grep -qF 'systemctl --user start' "$AUDIO_SETUP" ||
  fail "anios-audio-setup must start the PipeWire user units"
grep -qF 'pgrep -x pipewire' "$AUDIO_SETUP" ||
  fail "anios-audio-setup must fall back to running PipeWire without systemd --user"
grep -qF 'wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.5' "$AUDIO_SETUP" ||
  fail "anios-audio-setup must lift the default sink out of its muted default state"
grep -qF -- '--notify' "$AUDIO_SETUP" ||
  fail "anios-audio-setup must support --notify for the desktop session"
grep -qF -- '--force' "$AUDIO_SETUP" ||
  fail "anios-audio-setup must support --force to rebuild the audio stack"
grep -qF 'speaker-test' "$AUDIO_CHECK" ||
  fail "anios-audio-check must be able to play a test tone"
grep -qF 'anios-audio-setup --force' "$AUDIO_CHECK" ||
  fail "anios-audio-check must point users at anios-audio-setup --force"

# Dàn âm thanh phải được dựng ngay khi vào phiên, và người dùng phải có đường
# chẩn đoán trong desktop chứ không chỉ trong tài liệu.
grep -qF '/usr/local/bin/anios-audio-setup --notify' "$HYPR_CONF" ||
  fail "Hyprland must start the AniOS audio setup when the session begins"
grep -qF 'anios-audio-check' "$HYPR_CONF" ||
  fail "Hyprland must offer a shortcut for the audio check tool"
grep -qF 'anios-audio-check' "$AIROOTFS/usr/share/anios/skel/Desktop/README.txt" ||
  fail "the live desktop readme must document anios-audio-check"

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
[[ -s "$AIROOTFS/usr/share/wayland-sessions/anios-imi.desktop" ]] || fail "the Immaterial Impulse Wayland session is missing"
[[ -s "$AIROOTFS/usr/share/wayland-sessions/anios-minimal.desktop" ]] || fail "the Minimal Wayland session is missing"
[[ -s "$AIROOTFS/usr/share/anios/skel/Desktop/README.txt" ]] || fail "the live desktop readme is missing"

# --- Overlay không được đè lên file do gói pacman sở hữu ------------------
# mkarchiso chép profile/airootfs vào work/<arch>/airootfs TRƯỚC khi pacstrap cài
# gói (docs/README.profile.rst của archiso). File overlay nào nằm sẵn ở đường dẫn
# mà một gói sở hữu sẽ làm pacman dừng với:
#   error: failed to commit transaction (conflicting files)
#   <gói>: .../work/x86_64/airootfs/<đường dẫn> exists in filesystem
#   ==> ERROR: Failed to install packages to new root
# Ngoại lệ duy nhất là các file "backup" của gói (ví dụ /etc/passwd, /etc/shadow
# của gói filesystem) mà chính archiso dựa vào để tạo tài khoản live.
#
# Với âm thanh: gói pipewire-alsa tự cài /etc/alsa/conf.d/99-pipewire-default.conf
# (trỏ ALSA mặc định về PipeWire) và pipewire-audio tự cài
# /etc/alsa/conf.d/50-pipewire.conf. AniOS không được ship lại những file đó —
# chỉ cần hai gói này nằm trong manifest là bảo đảm đã đủ.
#
# Lưu ý khi kiểm tra ảnh live: hai file /etc/alsa/conf.d/*.conf đó là SYMLINK
# TUYỆT ĐỐI trỏ về /usr/share/alsa/alsa.conf.d/ (PKGBUILD của pipewire dùng
# `ln -st`). `unsquashfs -cat` không đi theo symlink tuyệt đối, nên mọi bước
# đọc chúng trong airootfs.sfs phải dùng scripts/check-live-audio.sh.
for owned_path in \
  etc/alsa/conf.d/99-pipewire-default.conf \
  etc/alsa/conf.d/50-pipewire.conf \
  usr/share/alsa/alsa.conf.d/50-pipewire.conf \
  usr/share/alsa/alsa.conf.d/99-pipewire-default.conf \
  usr/share/pipewire/pipewire.conf \
  usr/share/pipewire/pipewire-pulse.conf \
  usr/share/wireplumber/wireplumber.conf; do
  [[ ! -e "$AIROOTFS/$owned_path" && ! -L "$AIROOTFS/$owned_path" ]] ||
    fail "overlay must not ship $owned_path: a pacman package owns that path, so pacstrap aborts with 'conflicting files'. Put AniOS settings in a file no package owns (e.g. etc/alsa/conf.d/99-anios-*.conf) or drop it and rely on the package."
done
# Hai gói này chính là thứ bảo đảm ALSA trỏ về PipeWire trong ảnh live.
for audio_package in pipewire-alsa pipewire-audio; do
  grep -qxF "$audio_package" "$ROOT_DIR/profile/packages.x86_64" ||
    fail "ALSA-to-PipeWire routing needs the $audio_package package in the manifest"
done

# --- Quyền của script dựng ISO -------------------------------------------
[[ -x "$ROOT_DIR/scripts/build-iso.sh" ]] || fail "build script is not executable"
[[ -x "$ROOT_DIR/scripts/check-profile.sh" ]] || fail "check script is not executable"

# --- Bước kiểm tra âm thanh của ảnh live ---------------------------------
# Script này đọc airootfs.sfs sau khi dựng. Nó PHẢI tự đi theo symlink:
# `unsquashfs -cat` dừng với "failed to resolve symbolic link" và exit code 2
# khi gặp symlink tuyệt đối, mà /etc/alsa/conf.d/*.conf (pipewire-alsa,
# pipewire-audio) lẫn các symlink *.wants/* do systemd enable tạo ra đều là
# symlink tuyệt đối. Bài tự kiểm tra chứng minh điều đó mà không cần dựng ISO.
LIVE_AUDIO_CHECK="$ROOT_DIR/scripts/check-live-audio.sh"
LIVE_AUDIO_SELFTEST="$ROOT_DIR/scripts/selftest-check-live-audio.sh"
[[ -x "$LIVE_AUDIO_CHECK" ]] ||
  fail "live audio checker is missing or not executable: scripts/check-live-audio.sh"
[[ -x "$LIVE_AUDIO_SELFTEST" ]] ||
  fail "live audio selftest is missing or not executable: scripts/selftest-check-live-audio.sh"
grep -qF 'check-live-audio.sh' "$ROOT_DIR/.github/workflows/build-iso.yml" ||
  fail "the ISO build workflow must verify the live audio stack with scripts/check-live-audio.sh"
grep -qF 'sfs_resolve' "$LIVE_AUDIO_CHECK" ||
  fail "scripts/check-live-audio.sh must follow symlinks itself; unsquashfs -cat cannot read the absolute symlinks pipewire-alsa installs"
grep -qF 'libpulse' "$LIVE_AUDIO_CHECK" ||
  fail "scripts/check-live-audio.sh must verify the libpulse package (provides pactl)"
grep -qF 'usr/share/alsa/alsa.conf.d/99-pipewire-default.conf' "$LIVE_AUDIO_CHECK" ||
  fail "scripts/check-live-audio.sh must verify usr/share/alsa/alsa.conf.d/99-pipewire-default.conf"
if grep -nE '\|[[:space:]]*head([[:space:]]|$)' "$LIVE_AUDIO_CHECK" | grep -vE ':[[:space:]]*#'; then
  fail "scripts/check-live-audio.sh must not pipe into head under set -o pipefail (causes SIGPIPE / exit code 141)"
fi
grep -qF 'selftest-check-live-audio.sh' "$ROOT_DIR/.github/workflows/profile-check.yml" ||
  fail "the profile workflow must run scripts/selftest-check-live-audio.sh"

# --- Gói AUR được dựng và cài sẵn lúc build --------------------------------
# pacman không cài được AUR, nên calamares, yay, coccoc-browser-stable và legacy-launcher
# phải được makepkg dựng BÊN TRONG chroot airootfs (scripts/anios-aur-build.sh,
# gọi từ hook customize_airootfs.sh mà scripts/build-iso.sh sinh ra). Nhóm kiểm tra
# dưới đây khoá lại những quyết định dễ bị phá khi sửa tay.
AUR_MANIFEST="$ROOT_DIR/profile/packages.aur.x86_64"
AUR_BUILDER="$ROOT_DIR/scripts/anios-aur-build.sh"
AUR_SELFCHECK="$ROOT_DIR/scripts/selftest-anios-aur-build.sh"
LIVE_AUR_CHECK="$ROOT_DIR/scripts/check-live-aur.sh"
LIVE_AUR_SELFCHECK="$ROOT_DIR/scripts/selftest-check-live-aur.sh"
BUILD_ISO="$ROOT_DIR/scripts/build-iso.sh"

[[ -s "$AUR_MANIFEST" ]] || fail "AUR manifest is missing: profile/packages.aur.x86_64"
for aur_pkg in calamares yay coccoc-browser-stable legacy-launcher; do
  grep -qE "^${aur_pkg}(=[^[:space:]]+)?([[:space:]]|#|$)" "$AUR_MANIFEST" ||
    fail "the AUR manifest must bake $aur_pkg into the live image"
done
# Mỗi dòng của manifest là một tên gói, kèm "=phiên bản" nếu muốn chốt bản đã thử.
# scripts/anios-aur-build.sh cũng chặn dòng sai, nhưng chặn ở đây thì nhanh hơn
# nhiều so với chờ một lượt dựng ISO.
if grep -nEv '^[[:space:]]*($|#|[A-Za-z0-9@._+-]+(=[^[:space:]]+)?([[:space:]]+#.*)?$)' "$AUR_MANIFEST"; then
  fail "invalid line in the AUR manifest"
fi

# Gói AUR cần thư viện của kho chính thức, và pacstrap phải cài chúng TRƯỚC khi
# makepkg chạy: jre-openjdk cung cấp java-runtime cho legacy-launcher, qt5-base và
# ttf-liberation cho Cốc Cốc, base-devel + git cho chính makepkg.
for runtime_dep in jre-openjdk qt5-base ttf-liberation base-devel git; do
  grep -qxF "$runtime_dep" "$ROOT_DIR/profile/packages.x86_64" ||
    fail "the AUR packages need $runtime_dep from the official repositories in packages.x86_64"
done
# `go` chỉ là makedepend của yay: script dựng gói tự cài rồi gỡ như gói mồ côi.
# Nằm trong manifest thì nó ở lại ảnh live và làm ISO nặng thêm vài trăm MB.
! grep -qxF go "$ROOT_DIR/profile/packages.x86_64" ||
  fail "go is only a build-time makedepend of yay; keep it out of packages.x86_64"

for aur_script in "$AUR_BUILDER" "$AUR_SELFCHECK" "$LIVE_AUR_CHECK" "$LIVE_AUR_SELFCHECK"; do
  [[ -x "$aur_script" ]] || fail "missing or not executable: ${aur_script#"$ROOT_DIR/"}"
done

# makepkg từ chối chạy bằng root, nhưng KHÔNG vì thế mà cấp sudo cho tài khoản
# dựng gói: phụ thuộc do script cài bằng quyền root sẵn có trong chroot, gói dựng
# xong cũng do root cài bằng pacman -U.
grep -qE 'runuser|setpriv' "$AUR_BUILDER" ||
  fail "the AUR builder must drop privileges (runuser/setpriv): makepkg refuses to run as root"
grep -q 'userdel' "$AUR_BUILDER" ||
  fail "the AUR builder must delete its temporary build account so it never ships in the image"
grep -qF -- '--asexplicit' "$AUR_BUILDER" ||
  fail "the AUR builder must install built packages with pacman -U --asexplicit"
grep -qF 'SRCINFO' "$AUR_BUILDER" ||
  fail "the AUR builder must read dependencies from SRCINFO instead of running PKGBUILD as root"
grep -qF -- '--asdeps' "$AUR_BUILDER" ||
  fail "the AUR builder must install build dependencies with --asdeps so they can be removed as orphans"
grep -qxF 'BUILD_TOOLS=(base-devel git)' "$AUR_BUILDER" ||
  fail "the AUR builder must install base-devel and git: the releng profile ships neither"
if grep -nE 'etc/sudoers|NOPASSWD' "$AUR_BUILDER" | grep -vE ':[[:space:]]*#'; then
  fail "the AUR builder must not create sudoers rules or NOPASSWD rights"
fi
if grep -nE '(^|[|&;])[[:space:]]*sudo[[:space:]]' "$AUR_BUILDER" | grep -vE ':[[:space:]]*#'; then
  fail "the AUR builder must not run commands through sudo"
fi
# Một gói dựng hỏng phải làm dừng bản dựng, nếu không ISO sẽ thiếu gói mà CI vẫn
# xanh (đúng lý do scripts/selftest-anios-aur-build.sh tồn tại).
grep -qF 'AUR_FAILED' "$AUR_BUILDER" ||
  fail "the AUR builder must report and fail on packages it could not build"

# build-iso.sh phải sinh hook của mkarchiso, có lối thoát --no-aur, và phải đối
# chiếu pacman DB của airootfs SAU khi dựng: hook customize_airootfs.sh bị archiso
# đánh dấu deprecated, nếu nó biến mất thì mkarchiso vẫn báo thành công và cho ra
# một ISO thiếu gói AUR.
grep -qF -- '--no-aur' "$BUILD_ISO" ||
  fail "build-iso.sh must offer --no-aur for machines that cannot reach the AUR"
grep -qF 'customize_airootfs.sh' "$BUILD_ISO" ||
  fail "build-iso.sh must generate the airootfs/root/customize_airootfs.sh hook that builds the AUR packages"
grep -qF 'packages.aur.x86_64' "$BUILD_ISO" ||
  fail "build-iso.sh must stage the AUR manifest into the temporary build profile"
grep -qF 'anios-aur-build.sh' "$BUILD_ISO" ||
  fail "build-iso.sh must stage scripts/anios-aur-build.sh into the temporary build profile"
grep -qF -- '--sysroot' "$BUILD_ISO" ||
  fail "build-iso.sh must verify the AUR packages against the airootfs pacman database after the build"
grep -qF 'aniosbuild' "$BUILD_ISO" ||
  fail "build-iso.sh must refuse an image that still contains the temporary AUR build account"

# Hook và thư mục dựng gói chỉ được sinh ra lúc build. Nếu nằm sẵn trong
# profile/airootfs thì mkarchiso chép chúng vào ảnh TRƯỚC pacstrap và chúng ở lại
# trong ảnh live vĩnh viễn.
[[ ! -e "$AIROOTFS/root/customize_airootfs.sh" ]] ||
  fail "profile/airootfs must not ship root/customize_airootfs.sh; build-iso.sh generates it per build"
[[ ! -e "$AIROOTFS/root/.anios-aur" ]] ||
  fail "profile/airootfs must not ship root/.anios-aur; build-iso.sh stages it per build"
if [[ -e "$AIROOTFS/etc/passwd" ]]; then
  ! grep -qF 'aniosbuild' "$AIROOTFS/etc/passwd" ||
    fail "the overlay must not contain the temporary AUR build account"
fi

# CI phải chạy cả hai bài tự kiểm tra (chúng bắt lỗi trong vài giây, không cần
# Arch Linux) và phải soi ảnh live sau khi dựng.
for aur_selfcheck in selftest-anios-aur-build.sh selftest-check-live-aur.sh; do
  grep -qF "$aur_selfcheck" "$ROOT_DIR/.github/workflows/profile-check.yml" ||
    fail "the profile workflow must run scripts/$aur_selfcheck"
done
grep -qF 'check-live-aur.sh' "$ROOT_DIR/.github/workflows/build-iso.yml" ||
  fail "the ISO build workflow must verify the live image with scripts/check-live-aur.sh"
# Thư mục trong var/lib/pacman/local có dạng <tên>-<pkgver>-<pkgrel> (không có
# hậu tố -<arch>; chỉ file .pkg.tar.zst mới có -<arch>). Nếu regex đòi
# -(x86_64|any|i686)$ thì mọi gói trong pacman DB thật đều bị báo THIẾU.
! grep -qE 'x86_64\|any\|i686' "$LIVE_AUR_CHECK" ||
  fail "check-live-aur.sh must match var/lib/pacman/local/<pkgname>-<pkgver>-<pkgrel> without an -<arch> suffix"

# Bước kiểm tra cuối của build-iso.sh ("không có luật sudo NOPASSWD nào lọt vào
# ảnh") chỉ được tính luật ĐANG CÓ HIỆU LỰC. Gói sudo của Arch ship /etc/sudoers
# kèm dòng ví dụ đã comment `# %wheel ALL=(ALL:ALL) NOPASSWD: ALL`, nên một lệnh
# grep thô chữ NOPASSWD luôn khớp: bản dựng ~25 phút chết ở bước cuối trên một ảnh
# hoàn toàn sạch. Khoá lại để lỗi đó không quay lại sau một lần sửa tay.
SUDOERS_SELFTEST="$ROOT_DIR/scripts/selftest-build-iso-sudoers.sh"
[[ -x "$SUDOERS_SELFTEST" ]] ||
  fail "missing or not executable: scripts/selftest-build-iso-sudoers.sh"
grep -qF 'selftest-build-iso-sudoers.sh' "$ROOT_DIR/.github/workflows/profile-check.yml" ||
  fail "the profile workflow must run scripts/selftest-build-iso-sudoers.sh"
grep -qE '^sudoers_nopasswd_rules\(\) \{$' "$BUILD_ISO" ||
  fail "build-iso.sh must define sudoers_nopasswd_rules(): a raw grep for NOPASSWD matches the commented example in the stock /etc/sudoers"
grep -qF 'sudoers_nopasswd_rules "$airootfs_dir"' "$BUILD_ISO" ||
  fail "build-iso.sh must check the built image for leaked NOPASSWD rules with sudoers_nopasswd_rules"

# --- Calamares installer ---------------------------------------------------
INSTALLER_ROOT="$ROOT_DIR/profile/installer"
INSTALLER_SELFTEST="$ROOT_DIR/scripts/selftest-installer.sh"
TARGET_MANIFEST="$ROOT_DIR/profile/install/packages.x86_64"
BOOT_CHOICE="$AIROOTFS/usr/local/bin/anios-boot-choice"

[[ -x "$BOOT_CHOICE" ]] || fail "Live ISO boot chooser is missing or not executable"
[[ -x "$INSTALLER_SELFTEST" ]] || fail "installer self-test is missing or not executable"
grep -qF 'selftest-installer.sh' "$ROOT_DIR/.github/workflows/profile-check.yml" ||
  fail "the profile workflow must run scripts/selftest-installer.sh"
grep -qF 'anios-boot-choice' "$AIROOTFS/usr/share/anios/skel/.config/hypr/hyprland.lua" ||
  fail "the AniOS graphical session must open the Live ISO / installer choice"
grep -qF 'ANIOS_LIVE' "$AIROOTFS/usr/local/bin/anios-session" ||
  fail "anios-session must gate the welcome chooser to the Live ISO only"
grep -qxF 'calamares' "$AUR_MANIFEST" || fail "Calamares must be built into the Live ISO"
[[ -s "$TARGET_MANIFEST" ]] || fail "the curated target package manifest is missing"
for target_package in base linux-zen grub sddm networkmanager lib32-mesa; do
  grep -qxF "$target_package" "$TARGET_MANIFEST" ||
    fail "the target installer manifest is missing $target_package"
done
for installer_file in \
  "$INSTALLER_ROOT/calamares/settings.conf" \
  "$INSTALLER_ROOT/calamares/modules/packagechooser-grub.conf" \
  "$INSTALLER_ROOT/calamares/modules/packagechooser-sddm.conf" \
  "$INSTALLER_ROOT/calamares/modules/packagechooser-dotfiles.conf" \
  "$INSTALLER_ROOT/calamares/modules/services-systemd.conf" \
  "$INSTALLER_ROOT/scripts/anios-installer-pacstrap" \
  "$INSTALLER_ROOT/scripts/anios-installer-skel" \
  "$INSTALLER_ROOT/scripts/anios-installer-finalize" \
  "$INSTALLER_ROOT/licenses/Grubphemous-LICENSE" \
  "$INSTALLER_ROOT/licenses/Grubphemous-README.md"; do
  [[ -s "$installer_file" ]] || fail "installer component is missing: ${installer_file#"$ROOT_DIR/"}"
done
for script in "$INSTALLER_ROOT"/scripts/*; do
  [[ -x "$script" ]] || fail "installer helper is not executable: ${script#"$ROOT_DIR/"}"
  bash -n "$script" || fail "shell syntax error: ${script#"$ROOT_DIR/"}"
done
grep -qF 'gorgeous-grubphemous' "$INSTALLER_ROOT/scripts/anios-installer-finalize" ||
  fail "the GRUB finalizer must accept the Gorgeous-GRUB selection"
! grep -qF 'catppuccin-mocha' "$INSTALLER_ROOT/scripts/anios-installer-finalize" ||
  fail "the GRUB finalizer still selects the obsolete Catppuccin option"
grep -qF 'install_calamares_configuration' "$AUR_BUILDER" ||
  fail "the AUR hook must stage AniOS Calamares configuration after package install"
grep -qF 'modules/packagechooser-grub.conf' "$AUR_BUILDER" ||
  fail "the AUR hook must verify AniOS packagechooser module configurations"
for staged_path in \
  'previews/grub-gorgeous.png' \
  'previews/qylock.png' \
  'previews/wallpaper.png' \
  'upstream/grubphemous' \
  'packages.x86_64'; do
  grep -qF "$staged_path" "$BUILD_ISO" ||
    fail "build-iso.sh does not stage installer asset $staged_path"
done
[[ -x "$AIROOTFS/usr/local/bin/anios-session" ]] || fail "anios-session must be executable"

grep -qF 'END4_COMMIT="547836f1b01a45445cfbbcd92b206d1b5ceee4d9"' \
  "$INSTALLER_ROOT/scripts/anios-end4-setup" ||
  fail "end-4 upstream revision must be pinned to the verified commit"
grep -qF 'exec ./setup install' "$INSTALLER_ROOT/scripts/anios-end4-setup" ||
  fail "end-4 must run only its interactive install command after user consent"
grep -qF '[[ $EUID -ne 0 ]]' "$INSTALLER_ROOT/scripts/anios-end4-setup" ||
  fail "end-4 setup must never run as root"

pass "AniOS profile and installer checks passed (ISO build still requires Arch Linux + archiso)"
