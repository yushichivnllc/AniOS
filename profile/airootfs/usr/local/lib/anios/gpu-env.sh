# shellcheck shell=bash
# Biến môi trường cho GPU NVIDIA trong phiên Hyprland. File này được SOURCE bởi
# /usr/local/bin/anios-session (không chạy trực tiếp, nên không cần bit thực thi).
#
# Vì sao phải phân biệt máy "chỉ NVIDIA" với máy "NVIDIA + iGPU":
#
#   * GBM_BACKEND=nvidia-drm và LIBVA_DRIVER_NAME=nvidia là chỉ dẫn cho
#     compositor/app biết dùng ĐÚNG driver của card đang xuất hình. Trên máy
#     hybrid (Intel/AMD xuất hình, NVIDIA rời để render), đặt hai biến này là
#     cách nhanh nhất để Hyprland chết ngay khi khởi tạo GPU: Aquamarine mở
#     /dev/dri/card0 của iGPU nhưng lại nạp backend GBM của NVIDIA
#     ("Failed to create a GBM allocator" / màn hình đen) rồi thoát về SDDM.
#     Trước đây gpu-env.sh đặt chúng cho MỌI máy có card NVIDIA, kể cả máy
#     hybrid — đó là lỗi "không vào được giao diện Hyprland" trên máy có iGPU.
#   * Trên máy chỉ có NVIDIA (hoặc NVIDIA là card boot_vga của firmware), không
#     đặt thì driver proprietary không được chọn và Hyprland rơi về llvmpipe
#     (rất chậm, nhiều app Qt/Electron trắng xoá).
#
# Chỉ đặt biến khi cả hai điều kiện đúng:
#   1. có thiết bị PCI NVIDIA (vendor 0x10de) làm card đồ hoạ (class 0x03xxxx);
#   2. module nvidia-drm đang nạp (driver proprietary đã chạy).
# Nếu driver không nạp (ví dụ nouveau), không đặt gì, để Mesa tự chọn như trước.
#
# ANIOS_SYSFS_ROOT (mặc định /sys) chỉ để bài tự kiểm tra trỏ tới cây sysfs giả.

_anios_sysfs_root() {
  printf '%s\n' "${ANIOS_SYSFS_ROOT:-/sys}"
}

# _anios_display_devices <vendor>: in ra đường dẫn các thiết bị PCI hiển thị
# (class 0x03xxxx) của một vendor. Trả về 1 nếu không có thiết bị nào.
_anios_display_devices() {
  local wanted="$1" sysfs dev vendor class
  sysfs="$(_anios_sysfs_root)"
  for dev in "$sysfs"/bus/pci/devices/*; do
    [[ -r "$dev/vendor" && -r "$dev/class" ]] || continue
    vendor="$(<"$dev/vendor")"
    class="$(<"$dev/class")"
    if [[ "$vendor" == "$wanted" && "$class" == 0x03* ]]; then
      printf '%s\n' "$dev"
    fi
  done
}

anios_has_nvidia_gpu() {
  [[ -n "$(_anios_display_devices 0x10de | head -n1)" ]]
}

# Có GPU tích hợp/khác loại không phải NVIDIA (Intel 0x8086, AMD 0x1002).
anios_has_other_gpu() {
  [[ -n "$(_anios_display_devices 0x8086 | head -n1)" ]] && return 0
  [[ -n "$(_anios_display_devices 0x1002 | head -n1)" ]] && return 0
  return 1
}

# Card NVIDIA có phải card mà firmware chọn để xuất hình lúc POST (boot_vga=1)?
# Máy để iGPU làm card chính (Optimus bật) thì boot_vga thuộc về iGPU, còn máy
# đã tắt iGPU trong BIOS hoặc desktop chỉ cắm màn hình vào card rời thì NVIDIA
# giữ boot_vga. Không đọc được thuộc tính này (kernel cũ/sysfs giả) thì coi như
# không phải card chính — an toàn hơn là ép backend NVIDIA lên một iGPU.
_anios_nvidia_is_boot_vga() {
  local sysfs dev
  sysfs="$(_anios_sysfs_root)"
  for dev in $(_anios_display_devices 0x10de); do
    [[ -r "$dev/boot_vga" ]] || continue
    [[ "$(<"$dev/boot_vga")" == 1 ]] && return 0
  done
  return 1
}

# _anios_drm_card_for_pci <pci-id>: in ra node /dev/dri/cardN của đúng thiết bị PCI
# đó, nếu nhân đã tạo node ấy. Trả về 1 khi không tìm thấy.
#
# Dùng để đặt AQ_DRM_DEVICES: trên máy UEFI, `simpledrm` có thể đã tạo
# /dev/dri/card0 TRƯỚC khi nvidia-drm tạo card1. Aquamarine (compositor của
# Hyprland) chọn card theo thứ tự liệt kê, nên nó có thể mở card của simpledrm —
# card không có output thật và không dựng được EGL — rồi thoát ngay, đưa người
# dùng về lại SDDM. Chỉ định thẳng node của card NVIDIA loại bỏ hoàn toàn khả năng
# đó, và cũng là cách Hyprland khuyến nghị cho máy nhiều card.
# ANIOS_DEV_ROOT chỉ để bài tự kiểm tra trỏ tới cây /dev giả.
_anios_drm_card_for_pci() {
  local wanted="$1" sysfs dev_root card name target
  sysfs="$(_anios_sysfs_root)"
  dev_root="${ANIOS_DEV_ROOT:-/dev}"
  for card in "$sysfs"/class/drm/*; do
    name="${card##*/}"
    [[ "$name" =~ ^card[0-9]+$ ]] || continue
    [[ -e "$card/device" ]] || continue
    target="$(readlink -f -- "$card/device" 2>/dev/null || true)"
    [[ "${target##*/}" == "$wanted" ]] || continue
    [[ -e "$dev_root/dri/$name" ]] || continue
    printf '%s\n' "$dev_root/dri/$name"
    return 0
  done
  return 1
}

# nvidia-drm đã bật kernel mode-setting chưa? Wayland (Hyprland) KHÔNG chạy được
# nếu modeset=0: nvidia-drm không cung cấp KMS device nên Aquamarine không mở
# được GPU. Trả về 1 khi chưa bật hoặc không đọc được.
anios_nvidia_modeset_enabled() {
  local param="$(_anios_sysfs_root)/module/nvidia_drm/parameters/modeset"
  [[ -r "$param" ]] || return 1
  [[ "$(<"$param")" == [Yy1] ]]
}

anios_export_gpu_env() {
  local sysfs
  sysfs="$(_anios_sysfs_root)"
  [[ -d "$sysfs/module/nvidia_drm" ]] || return 0
  anios_has_nvidia_gpu || return 0

  if anios_nvidia_modeset_enabled; then
    export ANIOS_NVIDIA_MODESET=1
  else
    export ANIOS_NVIDIA_MODESET=0
    # Không tự sửa được từ phiên người dùng (cần root + initramfs), nhưng phải
    # để lại dấu vết: `anios-gpu-doctor` đọc biến này và in đúng cách sửa, còn
    # anios-session ghi nó vào nhật ký phiên.
    printf '%s\n' \
      'AniOS: nvidia-drm đang chạy nhưng modeset=0 — Hyprland sẽ không khởi động được.' \
      '       Chạy `sudo anios-gpu-doctor --fix` rồi khởi động lại.' >&2
  fi

  export XDG_SESSION_TYPE=wayland

  if anios_has_other_gpu && ! _anios_nvidia_is_boot_vga; then
    # Hybrid Optimus: iGPU (Mesa) lo compositor, NVIDIA chỉ render khi được yêu
    # cầu. Đây là cấu hình mặc định tốt nhất cho laptop/máy có iGPU.
    export ANIOS_GPU=nvidia-hybrid
    export __NV_PRIME_RENDER_OFFLOAD=1
    export __VK_LAYER_NV_optimus=NVIDIA_only
    return 0
  fi

  # Máy chỉ có NVIDIA (hoặc NVIDIA là card chính): buộc toàn bộ stack Wayland
  # dùng driver proprietary. NVD_BACKEND=direct là bắt buộc để vaapi/nvidia
  # giải mã video bằng GPU; thiếu nó, Firefox/mpv rơi về CPU (giật khi xem
  # video 1080p/4K trong quán net).
  export ANIOS_GPU=nvidia
  export GBM_BACKEND=nvidia-drm
  export __GLX_VENDOR_LIBRARY_NAME=nvidia
  export LIBVA_DRIVER_NAME=nvidia
  export NVD_BACKEND=direct

  # Ghim compositor vào đúng card của NVIDIA. Không tìm ra node (sysfs bị giới
  # hạn, hoặc driver chưa tạo node) thì KHÔNG đặt gì để compositor tự chọn như
  # trước — đặt bừa một đường dẫn không tồn tại sẽ làm Hyprland chết ngay.
  local pci nvidia_card=""
  while read -r pci; do
    [[ -n "$pci" ]] || continue
    if nvidia_card="$(_anios_drm_card_for_pci "${pci##*/}")"; then
      break
    fi
    nvidia_card=""
  done < <(_anios_display_devices 0x10de)
  if [[ -n "$nvidia_card" ]]; then
    export AQ_DRM_DEVICES="$nvidia_card"
  fi
}
