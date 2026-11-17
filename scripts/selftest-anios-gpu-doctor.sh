#!/usr/bin/env bash
# Tự kiểm tra profile/airootfs/usr/local/bin/anios-gpu-doctor trên cây giả: đây là
# công cụ người dùng chạy từ TTY khi Hyprland không lên hình, nên nó phải
#   * bắt được modeset=0, thiếu modprobe.d/mkinitcpio drop-in;
#   * không báo động giả trên một máy NVIDIA đã cấu hình đúng;
#   * với --fix thì ghi đúng nội dung cần thiết, gọi mkinitcpio và giữ nguyên
#     những dòng khác trong /etc/default/grub.
# Không cần GPU, Arch Linux hay quyền root (ANIOS_ETC_ROOT trỏ vào cây tạm).
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DOCTOR="$ROOT_DIR/profile/airootfs/usr/local/bin/anios-gpu-doctor"
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

[[ -x "$DOCTOR" ]] || fail "anios-gpu-doctor must exist and be executable"
bash -n "$DOCTOR" || fail "anios-gpu-doctor has a syntax error"
command -v shellcheck >/dev/null 2>&1 && shellcheck -s bash "$DOCTOR" ||
  true

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

# make_gpu <root> <vendor>: một card hiển thị giả, driver nvidia.
make_gpu() {
  local root="$1" vendor="$2" dev="$1/sysfs/bus/pci/devices/0000:01:00.0"
  mkdir -p -- "$dev" "$root/sysfs/bus/pci"
  printf '%s\n' "$vendor" >"$dev/vendor"
  printf '0x030000\n' >"$dev/class"
  printf '1\n' >"$dev/boot_vga"
  mkdir -p -- "$root/sysfs/bus/pci/drivers/nvidia"
  ln -sfn ../../drivers/nvidia "$dev/driver"
}

# make_drm <root> <fb-name>: card đã có KMS device thật (card1/renderD128) và
# framebuffer do nvidia-drm giữ, tức trạng thái khoẻ mạnh.
make_drm() {
  local root="$1" fb="${2:-nvidia-drmdrmfb}"
  mkdir -p -- "$root/dev/dri" "$root/sysfs/class/graphics/fb0"
  : >"$root/dev/dri/card1"
  : >"$root/dev/dri/renderD128"
  printf '%s\n' "$fb" >"$root/sysfs/class/graphics/fb0/name"
}

# make_vmd <root>: "RAID bus controller" Intel đang dùng driver vmd (RST bật).
make_vmd() {
  local dev="$1/sysfs/bus/pci/devices/0000:00:0e.0"
  mkdir -p -- "$dev" "$1/sysfs/bus/pci/drivers/vmd"
  printf '0x8086\n' >"$dev/vendor"
  printf '0x010400\n' >"$dev/class"
  ln -sfn ../../drivers/vmd "$dev/driver"
}

load_modules() {
  local root="$1" modeset="$2"
  mkdir -p -- "$root/sysfs/module/nvidia" "$root/sysfs/module/nvidia_drm/parameters"
  printf '%s\n' "$modeset" >"$root/sysfs/module/nvidia_drm/parameters/modeset"
}

write_good_config() {
  local etc="$1"
  install -d -- "$etc/modprobe.d" "$etc/mkinitcpio.conf.d" "$etc/default"
  cat >"$etc/modprobe.d/anios-nvidia.conf" <<'EOF'
blacklist nouveau
options nvidia-drm modeset=1 fbdev=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1 NVreg_TemporaryFilePath=/var/tmp
EOF
  printf 'MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)\n' \
    >"$etc/mkinitcpio.conf.d/10-anios-nvidia.conf"
  cat >"$etc/default/grub" <<'EOF'
GRUB_DEFAULT=0
GRUB_CMDLINE_LINUX_DEFAULT="quiet nvidia_drm.modeset=1 nvidia_drm.fbdev=1"
GRUB_DISABLE_OS_PROBER=false
EOF
  printf 'BOOT_IMAGE=/vmlinuz-linux-zen root=/dev/nvme0n1p2 nvidia_drm.modeset=1 nvidia_drm.fbdev=1\n' \
    >"$etc/cmdline"
}

# PATH shims: ghi lại lời gọi thay vì tác động lên máy chạy test.
SHIMS="$TMP/shims"
mkdir -p "$SHIMS"
for command_name in mkinitcpio grub-mkconfig systemctl; do
  cat >"$SHIMS/$command_name" <<EOF
#!/usr/bin/env bash
printf '%s %s\n' "$command_name" "\$*" >>"\$ANIOS_TEST_CALLS"
exit 0
EOF
  chmod +x "$SHIMS/$command_name"
done
export ANIOS_TEST_CALLS="$TMP/calls.log"
: >"$ANIOS_TEST_CALLS"

run_doctor() {
  local root="$1"
  shift
  env -i PATH="$SHIMS:/usr/local/bin:/usr/bin:/bin" HOME="$root/home" \
    ANIOS_SYSFS_ROOT="$root/sysfs" \
    ANIOS_DEV_ROOT="$root/dev" \
    ANIOS_ETC_ROOT="$root/etc" \
    ANIOS_PROC_CMDLINE="$root/etc/cmdline" \
    ANIOS_SESSION_LOG="$root/home/session.log" \
    ANIOS_BOOT_DIR="$root/boot" \
    ANIOS_TEST_CALLS="$ANIOS_TEST_CALLS" \
    "$DOCTOR" "$@"
}

# --- 1. Máy NVIDIA-only đã cấu hình đúng: không được báo lỗi -----------------
healthy="$TMP/healthy"
mkdir -p "$healthy/home"
make_gpu "$healthy" 0x10de
load_modules "$healthy" Y
make_drm "$healthy"
write_good_config "$healthy/etc"
out="$(run_doctor "$healthy")" || fail "healthy NVIDIA host must exit 0 (output: $out)"
grep -qF 'modeset=1' <<<"$out" || fail "healthy host must report modeset=1"
grep -qF '[fail]' <<<"$out" && fail "healthy host must not report failures: $out"
pass "healthy NVIDIA-only host"

# --- 2. modeset=0 + thiếu file: phải báo lỗi, mã thoát 1 --------------------
broken="$TMP/broken"
mkdir -p "$broken/home"
make_gpu "$broken" 0x10de
load_modules "$broken" N
status=0
out="$(run_doctor "$broken")" || status=$?
(( status == 1 )) || fail "a broken NVIDIA host must exit 1, got $status"
grep -qF 'modeset=' <<<"$out" || fail "missing modeset diagnostics"
grep -qF 'anios-gpu-doctor --fix' <<<"$out" || fail "must point at --fix"
grep -qF '10-anios-nvidia.conf' <<<"$out" || fail "must name the missing mkinitcpio drop-in"
pass "broken NVIDIA host reports modeset=0 and missing files"

# --- 3. nouveau đang giữ card: chẩn đoán phải nói đúng ----------------------
nouveau="$TMP/nouveau"
mkdir -p "$nouveau/home"
dev="$nouveau/sysfs/bus/pci/devices/0000:01:00.0"
mkdir -p "$dev" "$nouveau/sysfs/bus/pci/drivers/nouveau"
printf '0x10de\n' >"$dev/vendor"
printf '0x030000\n' >"$dev/class"
ln -sfn "$nouveau/sysfs/bus/pci/drivers/nouveau" "$dev/driver"
write_good_config "$nouveau/etc"
status=0
out="$(run_doctor "$nouveau")" || status=$?
(( status == 1 )) || fail "nouveau host must exit 1, got $status"
grep -qF "nouveau" <<<"$out" || fail "must name nouveau"
pass "nouveau host diagnostics"

# --- 3b. Card chỉ còn /dev/fb0 của efifb (đúng như lshw của máy B760) ---------
# Đây là trạng thái người dùng hay gặp nhất: modeset=1 nhưng driver chưa nhận card,
# nên lshw in "/dev/fb0" thay vì "/dev/dri/card1". Chẩn đoán phải nói ra điều đó.
fbroot="$TMP/fbonly"
mkdir -p "$fbroot/home" "$fbroot/dev/dri"
make_gpu "$fbroot" 0x10de
load_modules "$fbroot" Y
write_good_config "$fbroot/etc"
mkdir -p "$fbroot/sysfs/class/graphics/fb0"
printf 'efifb\n' >"$fbroot/sysfs/class/graphics/fb0/name"
status=0
out="$(run_doctor "$fbroot")" || status=$?
(( status == 1 )) || fail "a host with only efifb must exit 1, got $status"
grep -qF '/dev/dri/card*' <<<"$out" || fail "must report the missing KMS device"
grep -qF "efifb" <<<"$out" || fail "must name efifb as the framebuffer owner"
grep -qF 'video=efifb:off' <<<"$out" || fail "must explain how to take the framebuffer from efifb"
pass "host with only efifb gets a KMS diagnosis"

# --- 3c. Intel VMD/RST: cảnh báo ổ NVMe bị giấu, và --fix ghi drop-in vmd -----
vmdroot="$TMP/vmd"
mkdir -p "$vmdroot/home" "$vmdroot/dev/dri"
make_gpu "$vmdroot" 0x10de
load_modules "$vmdroot" Y
make_drm "$vmdroot"
make_vmd "$vmdroot"
write_good_config "$vmdroot/etc"
status=0
out="$(run_doctor "$vmdroot")" || status=$?
(( status == 1 )) || fail "a VMD host without the vmd drop-in must exit 1, got $status"
grep -qF 'VMD' <<<"$out" || fail "must warn about Intel VMD/RST"
grep -qF '20-anios-vmd.conf' <<<"$out" || fail "must name the missing vmd drop-in"
run_doctor "$vmdroot" --fix >/dev/null || fail "--fix must fix the VMD configuration"
grep -qxF 'MODULES+=(vmd)' "$vmdroot/etc/mkinitcpio.conf.d/20-anios-vmd.conf" ||
  fail "--fix must append vmd with MODULES+= (not overwrite the NVIDIA list)"
grep -qxF 'MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)' \
  "$vmdroot/etc/mkinitcpio.conf.d/10-anios-nvidia.conf" ||
  fail "--fix must keep the NVIDIA module list when adding vmd"
pass "Intel VMD/RST diagnosis and vmd drop-in"

# --- 4. --fix: ghi modprobe + drop-in + GRUB, gọi mkinitcpio -----------------
fixroot="$TMP/fixroot"
mkdir -p "$fixroot/home" "$fixroot/boot/grub"
make_gpu "$fixroot" 0x10de
load_modules "$fixroot" N
install -d "$fixroot/etc/default"
cat >"$fixroot/etc/default/grub" <<'EOF'
GRUB_DEFAULT=0
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_TIMEOUT=5
EOF
printf 'BOOT_IMAGE=/vmlinuz-linux-zen root=/dev/nvme0n1p2\n' >"$fixroot/etc/cmdline"
: >"$ANIOS_TEST_CALLS"
out="$(run_doctor "$fixroot" --fix)" || fail "--fix must exit 0 when it fixed the configuration: $out"

grep -qxF 'blacklist nouveau' "$fixroot/etc/modprobe.d/anios-nvidia.conf" ||
  fail "--fix must write 'blacklist nouveau'"
grep -qxF 'options nvidia-drm modeset=1 fbdev=1' "$fixroot/etc/modprobe.d/anios-nvidia.conf" ||
  fail "--fix must enable nvidia-drm modeset"
grep -qF 'NVreg_PreserveVideoMemoryAllocations=1' "$fixroot/etc/modprobe.d/anios-nvidia.conf" ||
  fail "--fix must keep video memory across suspend (frame buffer is 12 GB on an RTX 3060)"
grep -qxF 'MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)' \
  "$fixroot/etc/mkinitcpio.conf.d/10-anios-nvidia.conf" ||
  fail "--fix must ship nvidia modules in the initramfs"
grep -qF 'nvidia_drm.modeset=1' "$fixroot/etc/default/grub" ||
  fail "--fix must add the NVIDIA kernel parameters to GRUB"
grep -qxF 'GRUB_TIMEOUT=5' "$fixroot/etc/default/grub" ||
  fail "--fix must not drop unrelated GRUB lines"
grep -qF 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash nvidia_drm.modeset=1 nvidia_drm.fbdev=1"' \
  "$fixroot/etc/default/grub" || fail "--fix must append to the existing kernel command line"
grep -q '^mkinitcpio -P$' "$ANIOS_TEST_CALLS" ||
  fail "--fix must rebuild the initramfs (mkinitcpio -P)"
grep -q '^grub-mkconfig' "$ANIOS_TEST_CALLS" ||
  fail "--fix must refresh grub.cfg when GRUB is the boot loader"
pass "--fix writes a complete NVIDIA configuration"

# --- 5. --fix chạy hai lần: lần hai không được nhân đôi dòng ----------------
run_doctor "$fixroot" --fix >/dev/null || fail "the second --fix must succeed"
[[ "$(grep -cxF 'blacklist nouveau' "$fixroot/etc/modprobe.d/anios-nvidia.conf")" == 1 ]] ||
  fail "--fix must be idempotent"
[[ "$(grep -c 'nvidia_drm.modeset=1' "$fixroot/etc/default/grub")" == 1 ]] ||
  fail "--fix must add the kernel parameters only once"
pass "--fix is idempotent"

# --- 6. --fix không có quyền root và không có cây giả: từ chối rõ ràng ------
if (( EUID != 0 )); then
  status=0
  out="$(env -i PATH="$PATH" HOME="$TMP" "$DOCTOR" --fix 2>&1)" || status=$?
  (( status == 2 )) || fail "--fix without root must exit 2, got $status"
  grep -qF 'quyền root' <<<"$out" || fail "--fix without root must explain that root is required"
  pass "--fix refuses to run without root"
fi

echo "All anios-gpu-doctor self-tests passed."
