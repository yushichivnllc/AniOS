#!/usr/bin/env bash
# Tự kiểm tra profile/airootfs/usr/local/lib/anios/gpu-env.sh: anios-session chỉ
# được đặt biến NVIDIA (GBM/GLX/VA-API) khi có card NVIDIA VÀ nvidia-drm đang nạp,
# phải phân biệt máy chỉ-NVIDIA với máy hybrid (iGPU xuất hình), và phải báo được
# trường hợp nvidia-drm chạy mà modeset=0 (Hyprland không khởi động được).
# Chạy bằng cây sysfs giả, không cần GPU hay Arch Linux.
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
GPU_ENV="$ROOT_DIR/profile/airootfs/usr/local/lib/anios/gpu-env.sh"
SESSION="$ROOT_DIR/profile/airootfs/usr/local/bin/anios-session"
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

[[ -r "$GPU_ENV" ]] || fail "missing $GPU_ENV"
bash -n "$GPU_ENV" || fail "gpu-env.sh has a syntax error"
grep -qF '. /usr/local/lib/anios/gpu-env.sh' "$SESSION" ||
  fail "anios-session must source /usr/local/lib/anios/gpu-env.sh"
grep -qF 'anios_export_gpu_env' "$SESSION" ||
  fail "anios-session must call anios_export_gpu_env"

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

# make_gpu <root> <vendor> <class>: tạo một thiết bị PCI giả.
make_gpu() {
  local root="$1" vendor="$2" class="$3" dev
  dev="$1/bus/pci/devices/0000:$(printf '%02d' "$(find "$root/bus/pci/devices" -maxdepth 1 -mindepth 1 | wc -l)"):00.0"
  mkdir -p -- "$dev"
  printf '%s\n' "$vendor" >"$dev/vendor"
  printf '%s\n' "$class" >"$dev/class"
}

# run_case <name> <expected> <setup-fn>
# expected là chuỗi 9 trường; dùng "*" cho trường không cần so sánh chính xác
# (modeset chỉ có hoặc không).
run_case() {
  local name="$1" expect="$2" setup="$3" root="$TMP/$1" out field
  mkdir -p -- "$root/bus/pci/devices"
  "$setup" "$root"
  out="$(
    env -i PATH="$PATH" ANIOS_SYSFS_ROOT="$root" bash -c '
      set -Eeuo pipefail
      . "$1"
      anios_export_gpu_env
      printf "%s|%s|%s|%s|%s|%s|%s|%s|%s\n" \
        "${GBM_BACKEND:-}" "${__GLX_VENDOR_LIBRARY_NAME:-}" "${LIBVA_DRIVER_NAME:-}" \
        "${NVD_BACKEND:-}" "${XDG_SESSION_TYPE:-}" "${ANIOS_GPU:-}" \
        "${ANIOS_NVIDIA_MODESET:-}" "${__NV_PRIME_RENDER_OFFLOAD:-}" "${__VK_LAYER_NV_optimus:-}"
    ' _ "$GPU_ENV" 2>/dev/null
  )"
  [[ "$out" == "$expect" ]] || fail "$name: expected '$expect', got '$out'"
  pass "$name"
}

# --- Các dạng phần cứng -----------------------------------------------------
rtx_modeset() { make_gpu "$1" 0x10de 0x030000; mkdir -p "$1/module/nvidia_drm/parameters"; printf 'Y\n' >"$1/module/nvidia_drm/parameters/modeset"; }
rtx_modeset_off() { make_gpu "$1" 0x10de 0x030000; mkdir -p "$1/module/nvidia_drm/parameters"; printf 'N\n' >"$1/module/nvidia_drm/parameters/modeset"; }
rtx_no_driver() { make_gpu "$1" 0x10de 0x030000; }
intel_only() { make_gpu "$1" 0x8086 0x030000; mkdir -p "$1/module/nvidia_drm/parameters"; printf 'Y\n' >"$1/module/nvidia_drm/parameters/modeset"; }
nvidia_audio_only() { make_gpu "$1" 0x10de 0x040300; mkdir -p "$1/module/nvidia_drm/parameters"; printf 'Y\n' >"$1/module/nvidia_drm/parameters/modeset"; }
rtx_nouveau() { make_gpu "$1" 0x10de 0x030000; mkdir -p -- "$1/module/nouveau"; }

# Hybrid: iGPU Intel là card chính (boot_vga=1), NVIDIA rời chỉ render.
hybrid_igpu_primary() {
  make_gpu "$1" 0x8086 0x030000
  printf '1\n' >"$1/bus/pci/devices/0000:00:00.0/boot_vga"
  make_gpu "$1" 0x10de 0x030000
  printf '0\n' >"$1/bus/pci/devices/0000:01:00.0/boot_vga"
  mkdir -p "$1/module/nvidia_drm/parameters"; printf 'Y\n' >"$1/module/nvidia_drm/parameters/modeset"
}

# Hybrid nhưng BIOS đã tắt iGPU/đặt NVIDIA làm card chính (boot_vga=1): phải
# dùng đầy đủ biến NVIDIA, y như máy chỉ có NVIDIA.
hybrid_nvidia_primary() {
  make_gpu "$1" 0x8086 0x030000
  printf '0\n' >"$1/bus/pci/devices/0000:00:00.0/boot_vga"
  make_gpu "$1" 0x10de 0x030000
  printf '1\n' >"$1/bus/pci/devices/0000:01:00.0/boot_vga"
  mkdir -p "$1/module/nvidia_drm/parameters"; printf 'Y\n' >"$1/module/nvidia_drm/parameters/modeset"
}

NVIDIA_ENV='nvidia-drm|nvidia|nvidia|direct|wayland|nvidia|1||'
EMPTY_ENV='||||||||'

run_case rtx-with-nvidia-drm "$NVIDIA_ENV" rtx_modeset
run_case rtx-without-nvidia-drm "$EMPTY_ENV" rtx_no_driver
run_case intel-only-with-module-loaded "$EMPTY_ENV" intel_only
run_case nvidia-audio-function-only "$EMPTY_ENV" nvidia_audio_only
run_case rtx-running-nouveau "$EMPTY_ENV" rtx_nouveau
# modeset=0: vẫn đặt biến (driver đúng) nhưng phải đánh dấu để chẩn đoán biết
# rằng Hyprland sẽ không khởi động được.
run_case rtx-without-modeset \
  'nvidia-drm|nvidia|nvidia|direct|wayland|nvidia|0||' rtx_modeset_off
# Hybrid: KHÔNG được đặt GBM/GLX/LIBVA (iGPU xuất hình bằng Mesa), chỉ PRIME.
run_case hybrid-igpu-primary \
  '||||wayland|nvidia-hybrid|1|1|NVIDIA_only' hybrid_igpu_primary
run_case hybrid-nvidia-primary "$NVIDIA_ENV" hybrid_nvidia_primary

# --- Cảnh báo modeset phải ra stderr ----------------------------------------
root="$TMP/warning"
mkdir -p "$root/bus/pci/devices"
rtx_modeset_off "$root"
err="$(env -i PATH="$PATH" ANIOS_SYSFS_ROOT="$root" bash -c '. "$1"; anios_export_gpu_env' _ \
  "$GPU_ENV" 2>&1 >/dev/null || true)"
grep -qF 'modeset=0' <<<"$err" || fail "modeset=0 must print a warning with the fix command"
grep -qF 'anios-gpu-doctor --fix' <<<"$err" || fail "modeset warning must name anios-gpu-doctor --fix"
pass "modeset warning"

echo "All GPU environment self-tests passed."
