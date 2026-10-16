#!/usr/bin/env bash
# Tự kiểm tra profile/airootfs/usr/local/lib/anios/gpu-env.sh: anios-session chỉ
# được đặt biến NVIDIA (GBM/GLX/VA-API) khi có card NVIDIA VÀ nvidia-drm đang nạp.
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
  local root="$1" vendor="$2" class="$3" dev="$1/bus/pci/devices/0000:01:00.0"
  mkdir -p -- "$dev"
  printf '%s\n' "$vendor" >"$dev/vendor"
  printf '%s\n' "$class" >"$dev/class"
}

# run_case <name> <expect_nvidia:0|1> <setup-fn>
run_case() {
  local name="$1" expect="$2" setup="$3" root="$TMP/$1" out
  mkdir -p -- "$root/bus/pci/devices"
  "$setup" "$root"
  out="$(
    env -i PATH="$PATH" ANIOS_SYSFS_ROOT="$root" bash -c '
      set -Eeuo pipefail
      . "$1"
      anios_export_gpu_env
      printf "%s|%s|%s|%s\n" "${GBM_BACKEND:-}" "${__GLX_VENDOR_LIBRARY_NAME:-}" \
        "${LIBVA_DRIVER_NAME:-}" "${ANIOS_GPU:-}"
    ' _ "$GPU_ENV"
  )"
  if [[ "$expect" == 1 ]]; then
    [[ "$out" == "nvidia-drm|nvidia|nvidia|nvidia" ]] ||
      fail "$name: expected NVIDIA env, got '$out'"
  else
    [[ "$out" == "|||" ]] || fail "$name: expected no GPU env, got '$out'"
  fi
  pass "$name"
}

rtx_with_driver() { make_gpu "$1" 0x10de 0x030000; mkdir -p -- "$1/module/nvidia_drm"; }
rtx_no_driver() { make_gpu "$1" 0x10de 0x030000; }
intel_only() { make_gpu "$1" 0x8086 0x030000; mkdir -p -- "$1/module/nvidia_drm"; }
nvidia_audio_only() { make_gpu "$1" 0x10de 0x040300; mkdir -p -- "$1/module/nvidia_drm"; }
rtx_nouveau() { make_gpu "$1" 0x10de 0x030000; mkdir -p -- "$1/module/nouveau"; }

run_case rtx-with-nvidia-drm 1 rtx_with_driver
run_case rtx-without-nvidia-drm 0 rtx_no_driver
run_case intel-only-with-module-loaded 0 intel_only
run_case nvidia-audio-function-only 0 nvidia_audio_only
run_case rtx-running-nouveau 0 rtx_nouveau

echo "All GPU environment self-tests passed."
