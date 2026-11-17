#!/usr/bin/env bash
# Tự kiểm tra bước thêm tham số kernel NVIDIA vào MỌI cấu hình khởi động của ISO
# (grub.cfg, syslinux *.cfg, systemd-boot loader/entries/*.conf) trong
# scripts/build-iso.sh, mà không cần dựng ISO hay cài archiso.
#
# Vì sao có bài này: `options nvidia-drm modeset=1` trong /etc/modprobe.d chỉ tác
# dụng khi module được nạp. Card rời trên máy UEFI bị simpledrm/efiboot giữ màn hình
# từ trước; nếu nvidia-drm không giữ KMS sớm thì SDDM/Hyprland không có KMS device
# và "đăng nhập xong quay lại màn hình đăng nhập" (hoặc màn hình đen). Tham số kernel
# là lớp bảo hiểm cuối, và nó phải có trên cả mục menu BIOS lẫn UEFI — kể cả hai mục
# do khối lưu trữ bền vững sinh ra SAU đó (xem lời gọi trong build-iso.sh).
#
# Bài này nạp ĐÚNG hàm anios_add_nvidia_kernel_params() từ scripts/build-iso.sh nên
# sửa hàm là bài này thấy ngay.
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ISO="$ROOT_DIR/scripts/build-iso.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

[[ -f "$BUILD_ISO" ]] || fail "thiếu $BUILD_ISO"

fn_src="$(awk '/^anios_add_nvidia_kernel_params\(\) \{$/ { p = 1 } p { print } p && /^\}$/ { exit }' "$BUILD_ISO")"
[[ -n "$fn_src" ]] ||
  fail "scripts/build-iso.sh không còn hàm anios_add_nvidia_kernel_params() (khai báo ở đầu dòng)"
[[ "$(tail -n1 <<<"$fn_src")" == '}' ]] ||
  fail "không tìm thấy dấu '}' đóng hàm anios_add_nvidia_kernel_params() ở đầu dòng"
(( $(wc -l <<<"$fn_src") <= 60 )) ||
  fail "hàm anios_add_nvidia_kernel_params() dài bất thường: có thể dấu '}' đóng hàm nằm sai chỗ"
eval "$fn_src"

# build-iso.sh phải gọi hàm SAU khối lưu trữ bền vững và phải chốt lại.
grep -qF 'anios_add_nvidia_kernel_params "$BUILD_PROFILE"' "$BUILD_ISO" ||
  fail "build-iso.sh không gọi anios_add_nvidia_kernel_params cho profile đang dựng"
grep -qF "grep -qF 'nvidia_drm.modeset=1' \"\$boot_file\"" "$BUILD_ISO" ||
  fail "build-iso.sh không đối chiếu lại tham số NVIDIA sau khi vá cấu hình khởi động"
call_line="$(grep -nF 'anios_add_nvidia_kernel_params "$BUILD_PROFILE"' "$BUILD_ISO" | cut -d: -f1)"
persist_line="$(grep -nF '# --- Lưu trữ bền vững trên phần trống của USB' "$BUILD_ISO" | cut -d: -f1)"
(( call_line > persist_line )) ||
  fail "phải gọi hàm SAU khối lưu trữ bền vững, nếu không hai mục menu do khối đó sinh ra sẽ thiếu tham số"

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/anios-nvidia-params.XXXXXX")"
trap 'rm -rf -- "$SANDBOX"' EXIT

count_occurrences() { grep -oF "$2" "$1" | wc -l; }

# --- 1. GRUB (UEFI + BIOS) --------------------------------------------------
profile="$SANDBOX/grub"
mkdir -p "$profile/grub"
cat >"$profile/grub/grub.cfg" <<'GRUB'
set default=0
menuentry "AniOS Live (UEFI)" --id 'archlinux-efi' {
    linux /arch/boot/x86_64/vmlinuz-linux-zen archisobasedir=arch archisosearchuuid=ABC
    initrd /arch/boot/x86_64/initramfs-linux-zen.img
}
menuentry "AniOS Live (existing params)" --id 'archlinux-efi-2' {
    linux /arch/boot/x86_64/vmlinuz-linux-zen archisobasedir=arch nvidia_drm.modeset=1
}
GRUB
anios_add_nvidia_kernel_params "$profile" || fail "hàm trả lỗi trên grub.cfg hợp lệ"
[[ "$(count_occurrences "$profile/grub/grub.cfg" 'nvidia_drm.modeset=1')" == 2 ]] ||
  fail "mọi dòng linux phải có nvidia_drm.modeset=1 đúng một lần: $(cat "$profile/grub/grub.cfg")"
grep -qF 'archisosearchuuid=ABC nvidia_drm.modeset=1 nvidia_drm.fbdev=1' "$profile/grub/grub.cfg" ||
  fail "tham số phải được thêm vào CUỐI dòng linux của GRUB"
grep -qF 'set default=0' "$profile/grub/grub.cfg" ||
  fail "hàm không được làm mất các dòng khác của grub.cfg"
pass "GRUB entries get the NVIDIA kernel parameters"

# --- 2. Syslinux (BIOS) -----------------------------------------------------
profile="$SANDBOX/syslinux"
mkdir -p "$profile/syslinux"
cat >"$profile/syslinux/archiso_sys-linux.cfg" <<'SYSLINUX'
LABEL arch64
MENU LABEL AniOS Live
LINUX /arch/boot/x86_64/vmlinuz-linux-zen
INITRD /arch/boot/x86_64/initramfs-linux-zen.img
APPEND archisobasedir=arch archisosearchuuid=ABC copytoram=n
SYSLINUX
anios_add_nvidia_kernel_params "$profile" || fail "hàm trả lỗi trên syslinux hợp lệ"
grep -qE '^APPEND .*nvidia_drm\.modeset=1 nvidia_drm\.fbdev=1$' "$profile/syslinux/archiso_sys-linux.cfg" ||
  fail "dòng APPEND của Syslinux phải có tham số NVIDIA"
grep -qE '^LINUX ' "$profile/syslinux/archiso_sys-linux.cfg" ||
  fail "hàm không được sửa dòng LINUX của Syslinux"
pass "Syslinux APPEND gets the NVIDIA kernel parameters"

# --- 3. systemd-boot --------------------------------------------------------
profile="$SANDBOX/efiboot"
mkdir -p "$profile/efiboot/loader/entries"
cat >"$profile/efiboot/loader/entries/01-archiso-x86_64-linux.conf" <<'ENTRY'
title   AniOS Live
linux   /arch/boot/x86_64/vmlinuz-linux-zen
initrd  /arch/boot/x86_64/initramfs-linux-zen.img
options archisobasedir=arch archisosearchuuid=ABC
ENTRY
anios_add_nvidia_kernel_params "$profile" || fail "hàm trả lỗi trên entry systemd-boot hợp lệ"
grep -qE '^options .*nvidia_drm\.modeset=1 nvidia_drm\.fbdev=1$' \
  "$profile/efiboot/loader/entries/01-archiso-x86_64-linux.conf" ||
  fail "dòng options của systemd-boot phải có tham số NVIDIA"
pass "systemd-boot entries get the NVIDIA kernel parameters"

# --- 4. Chạy hai lần không nhân đôi tham số ---------------------------------
profile="$SANDBOX/idempotent"
mkdir -p "$profile/grub" "$profile/syslinux"
printf 'linux /arch/boot/x86_64/vmlinuz-linux-zen archisobasedir=arch\n' >"$profile/grub/grub.cfg"
printf 'APPEND archisobasedir=arch\n' >"$profile/syslinux/archiso_sys-linux.cfg"
anios_add_nvidia_kernel_params "$profile"
anios_add_nvidia_kernel_params "$profile"
[[ "$(count_occurrences "$profile/grub/grub.cfg" 'nvidia_drm.modeset=1')" == 1 ]] ||
  fail "chạy lại không được thêm tham số lần thứ hai vào grub.cfg"
[[ "$(count_occurrences "$profile/syslinux/archiso_sys-linux.cfg" 'nvidia_drm.modeset=1')" == 1 ]] ||
  fail "chạy lại không được thêm tham số lần thứ hai vào syslinux"
pass "adding the parameters is idempotent"

# --- 5. Profile không có cấu hình khởi động: không được chết ----------------
profile="$SANDBOX/empty"
mkdir -p "$profile"
anios_add_nvidia_kernel_params "$profile" || fail "profile không có boot config phải là no-op"
anios_add_nvidia_kernel_params "$SANDBOX/does-not-exist" 2>/dev/null &&
  fail "phải trả lỗi khi profile không tồn tại"
pass "missing boot configuration is a no-op"

echo "All boot-entry NVIDIA kernel parameter self-tests passed."
