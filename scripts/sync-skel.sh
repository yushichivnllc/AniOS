#!/usr/bin/env bash
# scripts/sync-skel.sh — nguồn duy nhất cho bộ dotfile (skeleton) của AniOS.
#
# Vì sao file này tồn tại:
#
#   Trước đây repo giữ HAI bản giống hệt của bộ dotfile:
#     profile/airootfs/etc/skel/                  (1.526 file, 19 MiB)
#     profile/airootfs/usr/share/anios/skel/      (1.526 file, 19 MiB)
#   và chúng chỉ khác nhau khi ai đó sửa một bản mà quên bản kia. Sửa one-sided
#   là kiểu hỏng âm thầm tệ nhất: mọi bài kiểm tra vẫn xanh, nhưng máy live và
#   máy đã cài chạy hai bộ cấu hình khác nhau (nguồn: `anios-installer-skel`
#   lấy từ /usr/share/anios/skel, còn `useradd` mặc định lấy từ /etc/skel).
#
#   Nay còn MỘT bản duy nhất trong cây repo:
#     profile/shared/skel/                        (nguồn)
#   và build-iso.sh SINH RA các bản đích trong ảnh:
#     /usr/share/anios/skel    (bản cài đặt lấy từ đây)
#     /etc/skel               (mặc định của useradd)
#     /home/anios             (tài khoản live)
#
#   Bản đích KHÔNG được commit: chúng là sản phẩm dựng, không phải nguồn. Nếu
#   ai đó tạo lại bản sao trong cây repo thì drift quay trở lại — chặn ở đây.
#
#   Điểm quan trọng: bản đích phải được sinh TỪ CÂY ĐÃ BIẾN ĐỔI của edition.
#   Ví dụ AniTails gỡ Desktop/Steam.desktop khỏi ảnh bằng remove.paths; nếu
#   /etc/skel được copy từ nguồn trong repo thì Steam.desktop sẽ quay lại ảnh
#   amnesic. Vì vậy `--stage` nhận cây nguồn (mặc định là nguồn trong repo) và
#   build-iso.sh truyền vào cây ĐÃ qua remove.paths.
#
# Cách dùng:
#   scripts/sync-skel.sh --check        kiểm tra các bất biến (dùng trong CI)
#   scripts/sync-skel.sh --stage DEST   sao chép nguồn sang DEST (dùng lúc dựng ISO)
#   scripts/sync-skel.sh --print-source in ra đường dẫn nguồn
#
# Mọi việc ở đây chạy được trên máy KHÔNG cần Arch Linux và không cần root.
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/profile/shared/skel"

# Những đường dẫn trong cây repo KHÔNG được chứa bản sao dotfile. Mọi bản sao
# đều là sản phẩm dựng; commit chúng là cách drift quay trở lại.
FORBIDDEN_MIRRORS=(
  "$ROOT_DIR/profile/airootfs/etc/skel"
  "$ROOT_DIR/profile/airootfs/usr/share/anios/skel"
)

fail() { echo "AniOS skel: $*" >&2; exit 1; }
info() { echo "AniOS skel: $*"; }

# Những mục phải có trong bộ dotfile. Đây là "hợp đồng" của skeleton: nếu một mục
# biến mất thì đó là thay đổi hành vi, không phải refactor.
required_paths=(
  '.config/hypr/hyprland.lua'
  '.config/hypr/hyprland-minimal.lua'
  '.config/hypr/hyprland-imi.lua'
  '.config/hypr/hyprland/keybinds.lua'
  '.config/hypr/hyprland/nvidia.lua'
  '.config/hypr/hyprlock.conf'
  '.config/waybar/config'
  '.config/waybar/style.css'
  '.config/quickshell/imi/shell.qml'
  '.config/matugen/config.toml'
  'Desktop/Steam.desktop'
  'Desktop/README.txt'
  '.bashrc'
)

check_single_source() {
  [[ -d "$SOURCE_DIR" ]] || fail "không tìm thấy bộ dotfile nguồn: $SOURCE_DIR"

  local rel
  for rel in "${required_paths[@]}"; do
    [[ -e "$SOURCE_DIR/$rel" ]] ||
      fail "bộ dotfile nguồn thiếu mục bắt buộc: $rel"
  done

  # Bản sao trong cây repo KHÔNG được tồn tại. Nếu nó xuất hiện lại (ví dụ ai
  # đó `cp -r` lại từ cây cũ), drift quay trở lại — chặn ở đây.
  local mirror
  for mirror in "${FORBIDDEN_MIRRORS[@]}"; do
    if [[ -e "$mirror" || -L "$mirror" ]]; then
      fail "${mirror#"$ROOT_DIR"/} đã tồn tại trong cây repo.
      Bản đó là sản phẩm dựng, không phải nguồn — nguồn duy nhất là
      profile/shared/skel. Xoá nó đi:  git rm -r ${mirror#"$ROOT_DIR"/}
      Nếu bạn vừa sửa dotfile, hãy sửa ở profile/shared/skel."
    fi
  done

  # build-iso.sh và bộ cài đặt phải lấy dotfile TỪ NGUỒN, không từ bản sao.
  local builder="$ROOT_DIR/scripts/build-iso.sh"
  local installer="$ROOT_DIR/profile/installer/scripts/anios-installer-skel"
  grep -qF 'sync-skel.sh' "$builder" ||
    fail "scripts/build-iso.sh không còn dùng scripts/sync-skel.sh"
  grep -qF 'source_skel="$LIVE_ROOT/usr/share/anios/skel"' "$installer" ||
    fail "bộ cài đặt không còn lấy dotfile từ /usr/share/anios/skel"

  info "nguồn dotfile duy nhất: profile/shared/skel"
  info "số file trong nguồn: $(find "$SOURCE_DIR" -type f | wc -l)"
}

stage_to() {
  local dest="$1" src="${2:-$SOURCE_DIR}"
  [[ -d "$src" ]] || fail "không tìm thấy bộ dotfile nguồn: $src"
  install -d -m 0755 -- "$dest"
  # `cp -a src/. dest/` giữ nguyên quyền và symlink; dấu chấm là bắt buộc để
  # nội dung nằm ở gốc dest chứ không nằm trong thư mục con tên "skel".
  cp -a -- "$src/." "$dest/"
  info "đã stage bộ dotfile vào $dest"
}

case "${1:---check}" in
  --check)
    check_single_source
    ;;
  --stage)
    [[ $# -ge 2 && $# -le 3 ]] || fail "dùng: $0 --stage DEST [SRC]"
    stage_to "$2" "${3:-}"
    ;;
  --print-source)
    printf '%s\n' "$SOURCE_DIR"
    ;;
  -h|--help)
    sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    ;;
  *)
    fail "tham số lạ: $1 (dùng --check | --stage DEST [SRC] | --print-source)"
    ;;
esac
