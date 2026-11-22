#!/usr/bin/env bash
# scripts/selftest-skel-single-source.sh — bảo vệ bất biến "một nguồn dotfile".
#
# Vì sao cần bài này:
#
#   Repo từng commit HAI bản giống hệt của bộ dotfile (1.526 file, 19 MiB mỗi
#   bản): profile/airootfs/etc/skel và profile/airootfs/usr/share/anios/skel.
#   Sửa một bản mà quên bản kia là hỏng âm thầm: mọi bài kiểm tra vẫn xanh
#   (vì chúng chỉ so sánh hai bản với nhau), nhưng máy live và máy đã cài chạy
#   hai bộ cấu hình khác nhau — /usr/share/anios/skel là nguồn cho cả
#   anios-live-home lẫn bộ cài Calamares, còn /etc/skel là mặc định của useradd.
#
#   Nay cây repo chỉ chứa MỘT nguồn: profile/shared/skel. Bản trong ảnh
#   (/usr/share/anios/skel, /etc/skel, /home/anios) đều là sản phẩm dựng.
#
#   Bài này khoá lại bất biến: cây repo chỉ được chứa MỘT nguồn, mọi bản sao bị
#   chặn, và thao tác stage phải chép trung thành (kể cả symlink và quyền thực
#   thi) — đồng thời phải chấp nhận nguồn khác để sinh bản đích theo đúng cây
#   đã qua remove.paths của edition (AniTails gỡ Steam.desktop).
#
# Chạy được trên mọi máy có bash, không cần Arch Linux, không cần root.
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC_SCRIPT="$ROOT_DIR/scripts/sync-skel.sh"
SOURCE_DIR="$ROOT_DIR/profile/shared/skel"

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/anios-skel-selftest.XXXXXX")"
cleanup() { rm -rf -- "$SANDBOX"; }
trap cleanup EXIT

failures=0
report_ok() { echo "  OK    $*"; }
report_fail() {
  echo "  FAIL  $*" >&2
  failures=$((failures + 1))
}

[[ -x "$SYNC_SCRIPT" ]] || { echo "FAIL: thiếu script $SYNC_SCRIPT" >&2; exit 1; }
bash -n "$SYNC_SCRIPT" || { echo "FAIL: lỗi cú pháp bash trong $SYNC_SCRIPT" >&2; exit 1; }

# --- 1. Repo thật: nguồn tồn tại và bản sao thứ hai không có ----------------
echo "--- 1. cây repo thật có đúng một nguồn dotfile ---"
if bash "$SYNC_SCRIPT" --check >/dev/null 2>&1; then
  report_ok "scripts/sync-skel.sh --check xanh trên repo thật"
else
  report_fail "scripts/sync-skel.sh --check báo lỗi trên repo thật"
fi

if [[ -d "$SOURCE_DIR" ]]; then
  report_ok "nguồn profile/shared/skel tồn tại"
else
  report_fail "nguồn profile/shared/skel không tồn tại"
fi

for mirror in profile/airootfs/etc/skel profile/airootfs/usr/share/anios/skel; do
  if [[ -e "$ROOT_DIR/$mirror" ]]; then
    report_fail "$mirror tồn tại: dotfile có nhiều nguồn và sẽ trôi lệch"
  else
    report_ok "$mirror không có trong cây repo"
  fi
done

# --print-source phải trỏ đúng nguồn, để build-iso.sh và bộ cài đặt không
# chỉ vào nhầm cây.
if [[ "$(bash "$SYNC_SCRIPT" --print-source)" == "$SOURCE_DIR" ]]; then
  report_ok "--print-source trỏ đúng profile/shared/skel"
else
  report_fail "--print-source không trỏ đúng nguồn"
fi

# --- 2. Bản sao thứ hai phải bị chặn ---------------------------------------
echo "--- 2. bản sao thứ hai bị chặn ---"
FAKE_REPO="$SANDBOX/repo"
mkdir -p -- "$FAKE_REPO/scripts" "$FAKE_REPO/profile/shared/skel/.config/hypr"
cp -- "$SYNC_SCRIPT" "$FAKE_REPO/scripts/sync-skel.sh"
# Nguồn giả: copy tối thiểu đủ các mục bắt buộc mà --check kiểm tra.
for rel in \
  '.config/hypr/hyprland.lua' \
  '.config/hypr/hyprland-minimal.lua' \
  '.config/hypr/hyprland-imi.lua' \
  '.config/hypr/hyprland/keybinds.lua' \
  '.config/hypr/hyprland/nvidia.lua' \
  '.config/hypr/hyprlock.conf' \
  '.config/waybar/config' \
  '.config/waybar/style.css' \
  '.config/quickshell/imi/shell.qml' \
  '.config/matugen/config.toml' \
  'Desktop/Steam.desktop' \
  'Desktop/README.txt' \
  '.bashrc'; do
  mkdir -p -- "$FAKE_REPO/profile/shared/skel/$(dirname -- "$rel")"
  printf 'placeholder %s\n' "$rel" >"$FAKE_REPO/profile/shared/skel/$rel"
done
# build-iso.sh và bộ cài đặt giả: --check chỉ grep, không chạy chúng.
printf '#!/bin/sh\nsync-skel.sh\n/usr/share/anios/skel\n' >"$FAKE_REPO/scripts/build-iso.sh"
mkdir -p -- "$FAKE_REPO/profile/installer/scripts"
printf '#!/bin/sh\nsource_skel="$LIVE_ROOT/usr/share/anios/skel"\n' \
  >"$FAKE_REPO/profile/installer/scripts/anios-installer-skel"

if bash "$FAKE_REPO/scripts/sync-skel.sh" --check >/dev/null 2>&1; then
  report_ok "repo giả (chưa có bản sao) vẫn được chấp nhận"
else
  report_fail "repo giả bị từ chối dù chưa có bản sao"
fi

mkdir -p -- "$FAKE_REPO/profile/airootfs/etc/skel"
if bash "$FAKE_REPO/scripts/sync-skel.sh" --check >/dev/null 2>&1; then
  report_fail "bản sao thứ hai (etc/skel) KHÔNG bị chặn"
else
  report_ok "bản sao thứ hai (etc/skel) bị chặn đúng như mong đợi"
fi

rm -rf -- "$FAKE_REPO/profile/airootfs/etc/skel"
mkdir -p -- "$FAKE_REPO/profile/airootfs/usr/share/anios/skel"
if bash "$FAKE_REPO/scripts/sync-skel.sh" --check >/dev/null 2>&1; then
  report_fail "bản sao thứ hai (usr/share/anios/skel) KHÔNG bị chặn"
else
  report_ok "bản sao thứ hai (usr/share/anios/skel) bị chặn đúng như mong đợi"
fi

# --- 3. Nguồn thiếu mục bắt buộc phải bị chặn -------------------------------
echo "--- 3. nguồn thiếu mục bắt buộc bị chặn ---"
rm -rf -- "$FAKE_REPO/profile/airootfs/usr/share/anios/skel"
rm -f -- "$FAKE_REPO/profile/shared/skel/.config/hypr/hyprlock.conf"
if bash "$FAKE_REPO/scripts/sync-skel.sh" --check >/dev/null 2>&1; then
  report_fail "nguồn thiếu hyprlock.conf KHÔNG bị chặn"
else
  report_ok "nguồn thiếu hyprlock.conf bị chặn"
fi

# --- 4. Stage chép trung thành ---------------------------------------------
echo "--- 4. --stage chép trung thành (file, symlink, quyền thực thi) ---"
STAGE_DEST="$SANDBOX/stage-dest"
bash "$SYNC_SCRIPT" --stage "$STAGE_DEST" >/dev/null

if [[ -f "$STAGE_DEST/.config/hypr/hyprland.lua" ]]; then
  report_ok "--stage tạo ra cây dotfile trong đích"
else
  report_fail "--stage không tạo ra cây dotfile trong đích"
fi

if diff -qr -- "$SOURCE_DIR" "$STAGE_DEST" >/dev/null 2>&1; then
  report_ok "cây staged giống hệt nguồn"
else
  report_fail "cây staged khác nguồn"
fi

# Symlink phải được giữ nguyên là symlink, không bị biến thành file thường.
SYMLINK_REL=".config/quickshell/imi/assets/icons/ai-openai-symbolic.svg"
if [[ -L "$SOURCE_DIR/$SYMLINK_REL" && -L "$STAGE_DEST/$SYMLINK_REL" ]]; then
  report_ok "symlink được giữ nguyên khi stage"
else
  report_fail "symlink không được giữ nguyên khi stage"
fi

# Quyền thực thi phải được giữ: script trong dotfile cần chạy được.
EXEC_REL=".config/hypr/hyprland/scripts/apply_saved_cursor.sh"
if [[ -x "$SOURCE_DIR/$EXEC_REL" && -x "$STAGE_DEST/$EXEC_REL" ]]; then
  report_ok "quyền thực thi được giữ khi stage"
else
  report_fail "quyền thực thi không được giữ khi stage"
fi

# --- 5. --stage với nguồn khác (cây đã qua remove.paths) -------------------
# Đây là hợp đồng mà build-iso.sh dựa vào: /etc/skel và /home/anios phải lấy từ
# cây ĐÃ bỏ Steam.desktop, không phải từ nguồn trong repo — nếu không, bản
# amnesic AniTails sẽ có lại shortcut của Steam.
echo "--- 5. --stage với nguồn khác giữ nguyên thay đổi của cây nguồn ---"
CUSTOM_SRC="$SANDBOX/custom-src"
mkdir -p -- "$CUSTOM_SRC/Desktop"
printf 'custom\n' >"$CUSTOM_SRC/Desktop/README.txt"
CUSTOM_DEST="$SANDBOX/custom-dest"
bash "$SYNC_SCRIPT" --stage "$CUSTOM_DEST" "$CUSTOM_SRC" >/dev/null

if [[ -f "$CUSTOM_DEST/Desktop/README.txt" ]] &&
  [[ ! -e "$CUSTOM_DEST/Desktop/Steam.desktop" ]]; then
  report_ok "--stage lấy đúng từ cây nguồn được chỉ định"
else
  report_fail "--stage không lấy đúng từ cây nguồn được chỉ định"
fi

if [[ -e "$CUSTOM_DEST/.config/hypr/hyprland.lua" ]]; then
  report_fail "--stage với nguồn khác vẫn chép nội dung của nguồn trong repo"
else
  report_ok "--stage với nguồn khác không trộn nội dung của nguồn trong repo"
fi

# --- 6. Tham số lạ phải bị từ chối -----------------------------------------
echo "--- 6. tham số lạ bị từ chối ---"
if bash "$SYNC_SCRIPT" --bogus >/dev/null 2>&1; then
  report_fail "tham số lạ KHÔNG bị từ chối"
else
  report_ok "tham số lạ bị từ chối"
fi

if bash "$SYNC_SCRIPT" --stage >/dev/null 2>&1; then
  report_fail "--stage thiếu đích KHÔNG bị từ chối"
else
  report_ok "--stage thiếu đích bị từ chối"
fi

if ((failures)); then
  echo "FAIL: $failures trường hợp sai trong bài tự kiểm tra" >&2
  exit 1
fi
echo "PASS: bộ dotfile của AniOS có đúng một nguồn và stage trung thành"
