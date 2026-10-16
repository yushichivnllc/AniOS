# shellcheck shell=bash
# Biến môi trường cho GPU NVIDIA trong phiên Hyprland. File này được SOURCE bởi
# /usr/local/bin/anios-session (không chạy trực tiếp, nên không cần bit thực thi).
#
# Chỉ đặt biến khi cả hai điều kiện đúng:
#   1. có thiết bị PCI NVIDIA (vendor 0x10de) làm card đồ hoạ (class 0x03xxxx);
#   2. module nvidia-drm đang nạp (driver proprietary đã chạy).
# Nếu driver không nạp (ví dụ nouveau), không đặt gì, để Mesa tự chọn như trước.
#
# ANIOS_SYSFS_ROOT (mặc định /sys) chỉ để bài tự kiểm tra trỏ tới cây sysfs giả.

anios_has_nvidia_gpu() {
  local sysfs="${ANIOS_SYSFS_ROOT:-/sys}" dev vendor class
  for dev in "$sysfs"/bus/pci/devices/*; do
    [[ -r "$dev/vendor" && -r "$dev/class" ]] || continue
    vendor="$(<"$dev/vendor")"
    class="$(<"$dev/class")"
    if [[ "$vendor" == 0x10de && "$class" == 0x03* ]]; then
      return 0
    fi
  done
  return 1
}

anios_export_gpu_env() {
  local sysfs="${ANIOS_SYSFS_ROOT:-/sys}"
  [[ -d "$sysfs/module/nvidia_drm" ]] || return 0
  anios_has_nvidia_gpu || return 0

  export LIBVA_DRIVER_NAME=nvidia
  export __GLX_VENDOR_LIBRARY_NAME=nvidia
  export GBM_BACKEND=nvidia-drm
  export ANIOS_GPU=nvidia
}
