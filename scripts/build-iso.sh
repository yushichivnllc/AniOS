#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/out"
WORK_DIR="$ROOT_DIR/work"
CLEAN_WORK=0
SKIP_CHECKS=0
# Giữ nguyên tham số gốc để khi tự gọi lại bằng sudo không mất tuỳ chọn nào.
ORIG_ARGS=("$@")

usage() {
  cat <<'EOF'
Usage: sudo ./scripts/build-iso.sh [--output DIR] [--work DIR] [--clean] [--skip-checks]

Build AniOS from Archiso's installed releng profile. Requires an up-to-date
Arch Linux x86_64 host, archiso, network access, and root privileges.

  --clean        delete the work directory first, so the image is built from
                 scratch instead of reusing a previous airootfs
  --skip-checks  do not run scripts/check-profile.sh before building
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
    --clean)
      CLEAN_WORK=1
      shift
      ;;
    --skip-checks)
      SKIP_CHECKS=1
      shift
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
    exec sudo -- "$0" ${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"}
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

# Chặn lỗi profile ngay trên máy dựng thay vì chờ tới giữa lượt dựng ISO hàng
# chục phút (CI cũng chạy đúng script này ở bước riêng).
if (( ! SKIP_CHECKS )); then
  bash "$ROOT_DIR/scripts/check-profile.sh"
fi

# --clean: dựng lại từ đầu. mkarchiso tái sử dụng work dir (các file đánh dấu
# base._make_* khiến bước đã chạy bị bỏ qua), nên đây là cách chắc chắn nhất để
# loại bỏ mọi tàn dư của profile cũ.
if (( CLEAN_WORK )); then
  if [[ -z "$WORK_DIR" || "$WORK_DIR" == / || "$WORK_DIR" == "$ROOT_DIR" ]]; then
    echo "Refusing to delete work directory: $WORK_DIR" >&2
    exit 2
  fi
  echo "Removing work directory: $WORK_DIR"
  rm -rf -- "$WORK_DIR"
fi

mkdir -p -- "$OUT_DIR" "$WORK_DIR"

# mkarchiso chép profile/airootfs vào work/<arch>/airootfs TRƯỚC khi pacstrap cài
# gói. Vì vậy một file overlay nằm ở đường dẫn do gói pacman sở hữu sẽ khiến
# pacman dừng với "failed to commit transaction (conflicting files)".
#
# Danh sách dưới đây là những đường dẫn từng nằm trong overlay của AniOS nhưng
# lại thuộc sở hữu của gói, và đã được gỡ khỏi profile. Nếu work dir được dùng
# lại thì bản sao của lần dựng trước vẫn còn đó, không gói nào sở hữu, và lượt
# dựng kế tiếp chết đúng chỗ đó — nên phải dọn trước. Chỉ xoá khi pacman DB trong
# airootfs xác nhận file chưa thuộc gói nào; nếu gói đã cài file đó rồi thì xoá
# sẽ làm hỏng ảnh.
removed_overlay_paths=(
  'etc/alsa/conf.d/99-pipewire-default.conf' # gói pipewire-alsa tự cài file này
)

# $1: thư mục airootfs, $2: đường dẫn tuyệt đối bên trong ảnh
airootfs_package_owns() {
  local root="$1" rel="${2#/}"
  [[ -d "$root/var/lib/pacman/local" ]] || return 1
  grep -qsxF -- "$rel" "$root"/var/lib/pacman/local/*/files
}

cleanup_removed_overlay_paths() {
  local airootfs rel target
  for airootfs in "$WORK_DIR"/*/airootfs; do
    [[ -d "$airootfs" ]] || continue
    for rel in "${removed_overlay_paths[@]}"; do
      target="$airootfs/$rel"
      [[ -e "$target" || -L "$target" ]] || continue
      if airootfs_package_owns "$airootfs" "/$rel"; then
        echo "Keeping $rel (already owned by a package installed in $airootfs)"
      else
        echo "Removing stale overlay file left by an older build: $target"
        rm -f -- "$target"
      fi
    done
  done
}
cleanup_removed_overlay_paths

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
insert_permission "/usr/local/bin/anios-switch-desktop" "0:0:755"
insert_permission "/usr/local/bin/anios-session" "0:0:755"
insert_permission "/usr/local/bin/anios-switch-im" "0:0:755"
insert_permission "/usr/local/bin/anios-audio-setup" "0:0:755"
insert_permission "/usr/local/bin/anios-audio-check" "0:0:755"
insert_permission "/usr/local/lib/anios/create-live-user" "0:0:755"
insert_permission "/usr/local/lib/anios/live-home-setup" "0:0:755"

for entry in \
  '["/etc/sudoers.d/10-anios-live"]="0:0:440"' \
  '["/usr/local/bin/anios-setup"]="0:0:755"' \
  '["/usr/local/bin/anios-switch-desktop"]="0:0:755"' \
  '["/usr/local/bin/anios-session"]="0:0:755"' \
  '["/usr/local/bin/anios-switch-im"]="0:0:755"' \
  '["/usr/local/bin/anios-audio-setup"]="0:0:755"' \
  '["/usr/local/bin/anios-audio-check"]="0:0:755"' \
  '["/usr/local/lib/anios/create-live-user"]="0:0:755"' \
  '["/usr/local/lib/anios/live-home-setup"]="0:0:755"'; do
  grep -qF "$entry" "$BUILD_PROFILE/profiledef.sh" ||
    { echo "Failed to declare file_permissions entry: $entry" >&2; exit 1; }
done

printf 'Building AniOS ISO\n  Profile: %s\n  Work:    %s\n  Output:  %s\n' "$BUILD_PROFILE" "$WORK_DIR" "$OUT_DIR"

# mkarchiso in lỗi của pacman lẫn trong hàng chục nghìn dòng tải gói, nên giữ lại
# log để khi thất bại còn chỉ đúng nguyên nhân và cách sửa.
build_log="$WORK_DIR/mkarchiso.log"
echo "  Log:     $build_log"

report_file_conflicts() {
  local log="$1"
  grep -q 'exists in filesystem' "$log" 2>/dev/null || return 0
  cat >&2 <<'EOF'

The build stopped because files in the airootfs overlay collide with files owned
by pacman packages. mkarchiso copies profile/airootfs into work/<arch>/airootfs
BEFORE pacstrap installs packages, so pacman refuses to overwrite a file that no
package owns:

EOF
  grep -E '^[^[:space:]]+: .* exists in filesystem$' "$log" | sed 's/^/  /' >&2 || true
  cat >&2 <<'EOF'

Fix: keep AniOS settings in a file no package owns -- for example
etc/alsa/conf.d/99-anios-*.conf instead of etc/alsa/conf.d/99-pipewire-default.conf,
which pipewire-alsa installs itself -- then rebuild. If the file is only a leftover
from an older build inside a reused work directory, rebuild with --clean.
EOF
}

set +e
mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "$BUILD_PROFILE" 2>&1 | tee -- "$build_log"
build_status=${PIPESTATUS[0]}
set -e

if (( build_status != 0 )); then
  report_file_conflicts "$build_log"
  exit "$build_status"
fi
