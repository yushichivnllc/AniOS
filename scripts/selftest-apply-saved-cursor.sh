#!/usr/bin/env bash
# Tự kiểm tra script áp theme con trỏ lúc Hyprland khởi động
# (profile/airootfs/.../hypr/hyprland/scripts/apply_saved_cursor.sh) mà không cần
# Arch Linux, không cần Hyprland và không cần phiên đồ hoạ.
#
# Lỗi từng xảy ra: cấu hình shell lưu theme "Bibata-Modern-Classic" (mặc định cũ
# của Immaterial Impulse) trong khi ảnh live không cài theme đó. `hyprctl setcursor`
# với một theme không tồn tại KHÔNG phải lệnh vô hại: Hyprland đưa tên đó cho
# libXcursor, không có thư mục theme nào khớp nên XCursorManager::loadTheme() báo
# "XCursor failed finding any shapes in theme" và giữ danh sách shape rỗng. Compositor
# mất con trỏ của chính nó, cứ chuyển qua lại giữa con trỏ rỗng đó và surface từng
# ứng dụng tự đặt — người dùng thấy con trỏ nhấp nháy/đổi hình liên tục.
#
# Script thật gọi `hyprctl`, nên ở đây thay bằng bản giả có ghi nhật ký lời gọi,
# rồi chạy đúng script đó với ANIOS_CURSOR_ICON_ROOTS trỏ vào cây icon giả.
#
# Các kịch bản được kiểm tra:
#   1. chưa có config                    → Adwaita 24 (theme ảnh live có cài)
#   2. config lưu theme đã cài + size     → dùng đúng lựa chọn của người dùng
#   3. config lưu theme KHÔNG cài         → rơi về Adwaita, không gọi setcursor với theme thiếu
#   4. config là JSON hỏng                → không chết, dùng Adwaita 24
#   5. config nằm ở thư mục legacy        → vẫn đọc được (illogical-impulse)
#   6. size sai kiểu / bằng 0             → giữ 24
#   7. không cài theme nào                → exit 0 và KHÔNG gọi hyprctl
#   8. theme định dạng hyprcursor         → được nhận là đã cài
#   9. hai bản skel                       → giống hệt nhau từng byte
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_REL='.config/hypr/hyprland/scripts/apply_saved_cursor.sh'
SCRIPT="$ROOT_DIR/profile/airootfs/usr/share/anios/skel/$SCRIPT_REL"
SCRIPT_TWIN="$ROOT_DIR/profile/airootfs/etc/skel/$SCRIPT_REL"

[[ -x "$SCRIPT" ]] || { echo "FAIL: thiếu hoặc không chạy được $SCRIPT" >&2; exit 1; }
bash -n "$SCRIPT" || { echo "FAIL: lỗi cú pháp bash trong $SCRIPT" >&2; exit 1; }

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/anios-cursor-selftest.XXXXXX")"
cleanup() { rm -rf -- "$SANDBOX"; }
trap cleanup EXIT

FAKE_BIN="$SANDBOX/bin"
FAKE_HOME="$SANDBOX/home"
ICON_ROOTS="$SANDBOX/icons"
mkdir -p -- "$FAKE_BIN" "$FAKE_HOME" "$ICON_ROOTS/usr-share-icons"

failures=0
report_ok() { echo "  OK    $*"; }
report_fail() {
  echo "  FAIL  $*" >&2
  [[ -s "$SANDBOX/out.txt" ]] && sed 's/^/        /' "$SANDBOX/out.txt" >&2
  failures=$((failures + 1))
}

# --- hyprctl giả: ghi lại đúng lời gọi rồi trả "ok" --------------------------
cat >"$FAKE_BIN/hyprctl" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${FAKE_HYPRCTL_LOG:?}"
echo "ok"
FAKE
chmod +x "$FAKE_BIN/hyprctl"

# --- cây icon giả: mỗi theme là một thư mục thật sự có payload ----------------
install_xcursor_theme() {
  mkdir -p -- "$ICON_ROOTS/$1/Adwaita/cursors"
  : >"$ICON_ROOTS/$1/Adwaita/cursors/left_ptr"
}
install_hyprcursor_theme() {
  mkdir -p -- "$ICON_ROOTS/$1/Volantes"
  : >"$ICON_ROOTS/$1/Volantes/manifest.toml"
}

# --- chạy script thật trong môi trường giả -----------------------------------
LAST_STATUS=0
run_script() {
  : >"$SANDBOX/calls.txt"
  LAST_STATUS=0
  HOME="$FAKE_HOME" \
  XDG_DATA_HOME="$FAKE_HOME/.local/share" \
  ANIOS_CURSOR_ICON_ROOTS="$ICON_ROOTS/usr-share-icons:$FAKE_HOME/.icons" \
  FAKE_HYPRCTL_LOG="$SANDBOX/calls.txt" \
  PATH="$FAKE_BIN:$PATH" \
    bash "$SCRIPT" >"$SANDBOX/out.txt" 2>&1 || LAST_STATUS=$?
}

write_config() { # $1 = đường dẫn file config, $2 = nội dung JSON
  mkdir -p -- "$(dirname -- "$1")"
  printf '%s\n' "$2" >"$1"
}

expect_call() { # $1 = lời gọi hyprctl mong đợi, $2 = mô tả
  local actual
  actual="$(cat "$SANDBOX/calls.txt" 2>/dev/null || true)"
  if [[ "$actual" == "$1" ]]; then
    report_ok "$2"
  else
    report_fail "$2 (mong đợi '$1', nhận được '$actual')"
  fi
}

expect_no_call() { # $1 = mô tả
  local actual
  actual="$(cat "$SANDBOX/calls.txt" 2>/dev/null || true)"
  if [[ -z "$actual" ]]; then
    report_ok "$1"
  else
    report_fail "$1 (vẫn gọi: $actual)"
  fi
}

reset_home() {
  rm -rf -- "$FAKE_HOME"
  mkdir -p -- "$FAKE_HOME"
}

CONFIG_JSON="$FAKE_HOME/.config/immaterial-impulse/config.json"
LEGACY_JSON="$FAKE_HOME/.config/illogical-impulse/config.json"

echo "--- 1. chưa có config: dùng theme ảnh live cài sẵn ---"
reset_home
install_xcursor_theme usr-share-icons
run_script
expect_call 'setcursor Adwaita 24' "mặc định là Adwaita 24"
[[ "$LAST_STATUS" -eq 0 ]] && report_ok "exit 0" || report_fail "exit $LAST_STATUS"

echo "--- 2. người dùng đã chọn theme có thật ---"
reset_home
install_xcursor_theme usr-share-icons
install_hyprcursor_theme usr-share-icons
write_config "$CONFIG_JSON" '{"hyprland":{"cursor":{"theme":"Volantes","size":32}}}'
run_script
expect_call 'setcursor Volantes 32' "giữ đúng lựa chọn đã lưu"

echo "--- 3. config lưu theme không được cài (lỗi gây nhấp nháy) ---"
reset_home
install_xcursor_theme usr-share-icons
write_config "$CONFIG_JSON" '{"hyprland":{"cursor":{"theme":"Bibata-Modern-Classic","size":24}}}'
run_script
expect_call 'setcursor Adwaita 24' "rơi về Adwaita thay vì setcursor một theme không tồn tại"
grep -q "not installed" "$SANDBOX/out.txt" &&
  report_ok "ghi log cho biết theme đã lưu không được cài" ||
  report_fail "không ghi log khi theme đã lưu không được cài"

echo "--- 4. config là JSON hỏng ---"
reset_home
install_xcursor_theme usr-share-icons
write_config "$CONFIG_JSON" '{"hyprland":{"cursor":'
run_script
[[ "$LAST_STATUS" -eq 0 ]] && report_ok "không chết vì JSON hỏng" || report_fail "exit $LAST_STATUS với JSON hỏng"
expect_call 'setcursor Adwaita 24' "vẫn áp Adwaita 24"

echo "--- 5. config ở thư mục legacy illogical-impulse ---"
reset_home
install_xcursor_theme usr-share-icons
write_config "$LEGACY_JSON" '{"hyprland":{"cursor":{"theme":"Adwaita","size":48}}}'
run_script
expect_call 'setcursor Adwaita 48' "đọc được config legacy"

echo "--- 6. size sai kiểu hoặc bằng 0 ---"
reset_home
install_xcursor_theme usr-share-icons
write_config "$CONFIG_JSON" '{"hyprland":{"cursor":{"theme":"Adwaita","size":"to"}}}'
run_script
expect_call 'setcursor Adwaita 24' "size không phải số thì giữ 24"
write_config "$CONFIG_JSON" '{"hyprland":{"cursor":{"theme":"Adwaita","size":0}}}'
run_script
expect_call 'setcursor Adwaita 24' "size 0 thì giữ 24"

echo "--- 7. ảnh không cài theme nào ---"
reset_home
rm -rf -- "$ICON_ROOTS/usr-share-icons"
mkdir -p -- "$ICON_ROOTS/usr-share-icons"
write_config "$CONFIG_JSON" '{"hyprland":{"cursor":{"theme":"Adwaita","size":24}}}'
run_script
[[ "$LAST_STATUS" -eq 0 ]] && report_ok "exit 0 khi không có theme nào" || report_fail "exit $LAST_STATUS"
expect_no_call "không gọi hyprctl: giữ con trỏ mặc định của compositor"

echo "--- 8. theme hyprcursor (chỉ có manifest) cũng được nhận ---"
reset_home
install_hyprcursor_theme usr-share-icons
write_config "$CONFIG_JSON" '{"hyprland":{"cursor":{"theme":"Volantes","size":24}}}'
run_script
expect_call 'setcursor Volantes 24' "manifest.toml đủ để coi là theme đã cài"

echo "--- 9. hai bản skel phải giống hệt nhau ---"
if diff -q -- "$SCRIPT" "$SCRIPT_TWIN" >/dev/null; then
  report_ok "etc/skel và usr/share/anios/skel cùng một nội dung"
else
  report_fail "hai bản skel của apply_saved_cursor.sh khác nhau"
fi

if ((failures)); then
  echo "FAIL: $failures trường hợp sai trong bài tự kiểm tra" >&2
  exit 1
fi
echo "PASS: apply_saved_cursor.sh không bao giờ setcursor một theme chưa được cài"
