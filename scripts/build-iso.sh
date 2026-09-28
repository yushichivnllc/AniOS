#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/out"
WORK_DIR="$ROOT_DIR/work"

usage() {
  cat <<'EOF'
Usage: sudo ./scripts/build-iso.sh [--output DIR] [--work DIR]

Build AniOS from Archiso's installed releng profile. Requires an up-to-date
Arch Linux x86_64 host, archiso, network access, and root privileges.
EOF
}

while (($#)); do
  case "$1" in
    -o|--output)
      (($# >= 2)) || { echo "Missing directory after $1" >&2; exit 2; }
      OUT_DIR="$2"
      shift 2
      ;;
    -w|--work)
      (($# >= 2)) || { echo "Missing directory after $1" >&2; exit 2; }
      WORK_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    exec sudo -- "$0" --output "$OUT_DIR" --work "$WORK_DIR"
  fi
  echo "Run this script as root (mkarchiso needs elevated privileges)." >&2
  exit 1
fi

RELENG_DIR="/usr/share/archiso/configs/releng"
if [[ ! -d "$RELENG_DIR" ]] || ! command -v mkarchiso >/dev/null 2>&1; then
  echo "archiso is missing. On Arch Linux, install it with: pacman -S archiso" >&2
  exit 1
fi

for required in "$ROOT_DIR/profile/packages.x86_64" "$ROOT_DIR/profile/airootfs"; do
  [[ -e "$required" ]] || { echo "Missing AniOS profile component: $required" >&2; exit 1; }
done

mkdir -p -- "$OUT_DIR" "$WORK_DIR"
BUILD_PROFILE="$(mktemp -d "${TMPDIR:-/tmp}/anios-profile.XXXXXX")"
cleanup() { rm -rf -- "$BUILD_PROFILE"; }
trap cleanup EXIT

cp -a -- "$RELENG_DIR/." "$BUILD_PROFILE/"

# The ISO boots only the zen kernel. Keep the standard releng package set,
# except for its generic kernel, then append AniOS additions without duplicates.
awk '$0 != "linux"' "$BUILD_PROFILE/packages.x86_64" > "$BUILD_PROFILE/packages.x86_64.tmp"
mv -- "$BUILD_PROFILE/packages.x86_64.tmp" "$BUILD_PROFILE/packages.x86_64"
cat "$ROOT_DIR/profile/packages.x86_64" >> "$BUILD_PROFILE/packages.x86_64"
awk 'NF && !seen[$0]++' "$BUILD_PROFILE/packages.x86_64" > "$BUILD_PROFILE/packages.x86_64.tmp"
mv -- "$BUILD_PROFILE/packages.x86_64.tmp" "$BUILD_PROFILE/packages.x86_64"

# Archiso's stock boot entries name the generic kernel. Rewrite every supported
# bootloader entry (including fallback initramfs names) for linux-zen.
for boot_dir in efiboot grub syslinux; do
  if [[ -d "$BUILD_PROFILE/$boot_dir" ]]; then
    find "$BUILD_PROFILE/$boot_dir" -type f \
      \( -name '*.conf' -o -name '*.cfg' \) -print0 |
      xargs -0r sed -i -E \
        's/(vmlinuz|initramfs)-linux(-fallback)?([.]|[[:space:]]|$)/\1-linux-zen\2\3/g'
  fi
done
for boot_dir in efiboot grub syslinux; do
  if [[ -d "$BUILD_PROFILE/$boot_dir" ]] &&
    grep -R -nE '(vmlinuz-linux|initramfs-linux(-fallback)?)([./[:space:]]|$)' "$BUILD_PROFILE/$boot_dir"; then
    echo "A boot entry still points at the generic linux kernel in $boot_dir" >&2
    exit 1
  fi
done

# Menu khởi động là thứ đầu tiên người dùng nhìn thấy, nên nó cũng mang tên
# AniOS thay vì tên của profile releng.
for boot_dir in efiboot grub syslinux; do
  if [[ -d "$BUILD_PROFILE/$boot_dir" ]]; then
    find "$BUILD_PROFILE/$boot_dir" -type f \
      \( -name '*.conf' -o -name '*.cfg' \) -print0 |
      xargs -0r sed -i -E \
        -e 's/Arch Linux install medium/AniOS Live/g' \
        -e 's/Arch Linux live medium/AniOS Live/g' \
        -e 's/^(MENU TITLE )Arch Linux$/\1AniOS/'
  fi
done
for boot_dir in efiboot grub syslinux; do
  [[ -d "$BUILD_PROFILE/$boot_dir" ]] || continue
  if grep -R -nE 'Arch Linux (install|live) medium' "$BUILD_PROFILE/$boot_dir"; then
    echo "A boot menu entry still carries Arch Linux wording in $boot_dir" >&2
    exit 1
  fi
  # Nếu releng đổi cách đặt tên mục menu, sed ở trên không còn khớp: dừng lại
  # để người bảo trì cập nhật quy tắc thay vì phát hành ISO thiếu thương hiệu.
  if ! grep -R -q 'AniOS' "$BUILD_PROFILE/$boot_dir"; then
    echo "Boot menu in $boot_dir does not mention AniOS; update the rebranding rules in build-iso.sh" >&2
    exit 1
  fi
done

# Mặc định Archiso chỉ cấp 256 MB RAM cho lớp ghi (cow) của hệ live, nên
# `pacman -Syyu` hết chỗ giữa chừng. Tăng lên 4G (tmpfs chỉ dùng RAM khi cần).
for boot_dir in efiboot grub syslinux; do
  [[ -d "$BUILD_PROFILE/$boot_dir" ]] || continue
  find "$BUILD_PROFILE/$boot_dir" -type f \( -name '*.conf' -o -name '*.cfg' \) -print0 |
    xargs -0r sed -i -E '/archisobasedir=/ { /cow_spacesize=/! s/[[:space:]]*$/ cow_spacesize=4G/ }'
done

cp -a -- "$ROOT_DIR/profile/airootfs/." "$BUILD_PROFILE/airootfs/"

# Releng có cấu hình autologin root trên tty1 (getty@tty1.service.d/autologin.conf).
# Xoá cấu hình này để tty1 không bị agetty chiếm dụng, giúp SDDM khởi chạy
# bình thường trên VT1 mà không bị xung đột.
rm -rf -- "$BUILD_PROFILE/airootfs/etc/systemd/system/getty@tty1.service.d"

# Ảnh thương hiệu nằm ngoài airootfs để repository gọn: wallpaper cho desktop và
# màn hình đăng nhập, splash cho menu khởi động Syslinux của profile releng.
for asset in "$ROOT_DIR/profile/branding/wallpaper.png" \
  "$ROOT_DIR/profile/branding/syslinux-splash.png"; do
  [[ -s "$asset" ]] ||
    { echo "Missing AniOS artwork: $asset (run scripts/make-branding-assets.sh)" >&2; exit 1; }
done
install -D -m 0644 -- "$ROOT_DIR/profile/branding/wallpaper.png" \
  "$BUILD_PROFILE/airootfs/usr/share/anios/wallpaper.png"
if [[ -d "$BUILD_PROFILE/syslinux" ]]; then
  install -m 0644 -- "$ROOT_DIR/profile/branding/syslinux-splash.png" \
    "$BUILD_PROFILE/syslinux/splash.png"
fi

# Tài khoản live đã có sẵn cấu hình đọc được ngay trong ảnh nén: nếu
# anios-live-home.service gặp trục trặc, desktop vẫn khởi động bình thường.
install -d -m 0755 -- "$BUILD_PROFILE/airootfs/home/anios"
cp -a -- "$BUILD_PROFILE/airootfs/usr/share/anios/skel/." \
  "$BUILD_PROFILE/airootfs/home/anios/"

install -d -m 0755 -- "$BUILD_PROFILE/airootfs/etc/skel"
cp -a -- "$BUILD_PROFILE/airootfs/usr/share/anios/skel/." \
  "$BUILD_PROFILE/airootfs/etc/skel/"

# Steam is in Arch's official multilib repository. Enable it only in the
# temporary build profile; the live image's own pacman.conf is configured too.
enable_multilib() {
  local config="$1"
  [[ -f "$config" ]] || return 0
  if ! grep -qE '^[[:space:]]*\[multilib\][[:space:]]*$' "$config"; then
    cat >> "$config" <<'EOF'

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
  else
    sed -i '/^[[:space:]]*\[multilib\][[:space:]]*$/,/^[[:space:]]*$/ s/^[[:space:]]*#//' "$config"
  fi
}
enable_multilib "$BUILD_PROFILE/pacman.conf"
RUNTIME_PACMAN_CONF="$BUILD_PROFILE/airootfs/etc/pacman.conf"
if [[ ! -f "$RUNTIME_PACMAN_CONF" ]]; then
  install -D -m 0644 "$BUILD_PROFILE/pacman.conf" "$RUNTIME_PACMAN_CONF"
fi
enable_multilib "$RUNTIME_PACMAN_CONF"

# Mirrorlist của hệ live do reflector.service điền lúc khởi động; nếu reflector
# lỗi (mạng chậm, timeout) file vẫn toàn dòng comment và pacman -Syyu báo
# "no servers configured". Thêm mirror dự phòng sau Include cho mọi kho.
sed -i -E '/^[[:space:]]*Include[[:space:]]*=[[:space:]]*\/etc\/pacman.d\/mirrorlist/ a\
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch\
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch' "$RUNTIME_PACMAN_CONF"
grep -q 'geo.mirror.pkgbuild.com' "$RUNTIME_PACMAN_CONF" ||
  { echo "Failed to add fallback mirrors to live pacman.conf" >&2; exit 1; }

# Preserve Archiso's current boot modes and other profile settings, changing
# only the identity strings that are stable across releng profile revisions.
sed -i \
  -e 's/^iso_name=.*/iso_name="anios"/' \
  -e 's/^iso_label=.*/iso_label="ANIOS_$(date +%Y%m)"/' \
  -e 's|^iso_publisher=.*|iso_publisher="AniOS Project <https://github.com/yushichivnllc/AniOS>"|' \
  -e 's/^iso_application=.*/iso_application="AniOS Arch Linux Live Gaming Desktop"/' \
  -e 's/^iso_version=.*/iso_version="$(date +%Y.%m.%d)"/' \
  "$BUILD_PROFILE/profiledef.sh"

# mkarchiso chép airootfs bằng `cp --no-preserve=ownership,mode`, nên bit thực
# thi của script và quyền 0440 của file sudoers bị mất trong chroot. Muốn giữ
# thì phải khai báo lại trong file_permissions của profile (đúng như releng
# làm cho /etc/shadow hay /usr/local/bin/choose-mirror).
insert_permission() {
  local path="$1" permissions="$2"
  sed -i "/^file_permissions=(/a\\  [\"${path}\"]=\"${permissions}\"" "$BUILD_PROFILE/profiledef.sh"
}
insert_permission "/etc/sudoers.d/10-anios-live" "0:0:440"
insert_permission "/usr/local/bin/anios-setup" "0:0:755"
insert_permission "/usr/local/bin/anios-session" "0:0:755"
insert_permission "/usr/local/bin/anios-switch-im" "0:0:755"
insert_permission "/usr/local/lib/anios/create-live-user" "0:0:755"
insert_permission "/usr/local/lib/anios/live-home-setup" "0:0:755"

for entry in \
  '["/etc/sudoers.d/10-anios-live"]="0:0:440"' \
  '["/usr/local/bin/anios-setup"]="0:0:755"' \
  '["/usr/local/bin/anios-session"]="0:0:755"' \
  '["/usr/local/bin/anios-switch-im"]="0:0:755"' \
  '["/usr/local/lib/anios/create-live-user"]="0:0:755"' \
  '["/usr/local/lib/anios/live-home-setup"]="0:0:755"'; do
  grep -qF "$entry" "$BUILD_PROFILE/profiledef.sh" ||
    { echo "Failed to declare file_permissions entry: $entry" >&2; exit 1; }
done

printf 'Building AniOS ISO\n  Profile: %s\n  Work:    %s\n  Output:  %s\n' "$BUILD_PROFILE" "$WORK_DIR" "$OUT_DIR"
mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "$BUILD_PROFILE"
