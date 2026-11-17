#!/usr/bin/env bash
# Tự kiểm tra "chế độ quán net": /usr/local/lib/anios/cafe.sh + /usr/local/bin/anios-cafe.
#
# Khoá lại những điều tuyệt đối không được sai, vì đây là script XOÁ DỮ LIỆU:
#   1. Chỉ xoá trong thư mục nhà, chỉ những đường dẫn trong danh sách; từ chối
#      đường dẫn tuyệt đối và '..'; symlink trỏ ra ngoài chỉ mất chính symlink.
#   2. Không đụng tới dotfiles Hyprland, ~/Desktop, nhật ký phiên của AniOS.
#   3. Mặc định KHÔNG xoá gì: phải bật chế độ (`anios-cafe on` / ANIOS_CAFE_ENABLE=1
#      / tham số nhân anios.cafe=1) thì mới dọn.
#   4. Watchdog chỉ khởi động lại máy đúng một lần mỗi lần boot, và chỉ khi bật.
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT_DIR/profile/airootfs/usr/local/bin/anios-cafe"
LIB="$ROOT_DIR/profile/airootfs/usr/local/lib/anios/cafe.sh"
SESSION="$ROOT_DIR/profile/airootfs/usr/local/bin/anios-session"
ETC_CONF="$ROOT_DIR/profile/airootfs/etc/anios/net-cafe.conf"
UNIT="$ROOT_DIR/profile/airootfs/etc/systemd/system/anios-cafe-watchdog.service"
TIMER="$ROOT_DIR/profile/airootfs/etc/systemd/system/anios-cafe-watchdog.timer"
TIMER_WANTS="$ROOT_DIR/profile/airootfs/etc/systemd/system/timers.target.wants/anios-cafe-watchdog.timer"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

for file in "$CLI" "$LIB" "$ETC_CONF" "$UNIT" "$TIMER" "$SESSION"; do
  [[ -s "$file" ]] || fail "missing: ${file#"$ROOT_DIR"/}"
done
[[ -x "$CLI" ]] || fail "anios-cafe must be executable"
[[ -L "$TIMER_WANTS" ]] || fail "anios-cafe-watchdog.timer must be enabled (timers.target.wants symlink)"
bash -n "$CLI" || fail "anios-cafe has a syntax error"
bash -n "$LIB" || fail "cafe.sh has a syntax error"
bash -n "$ETC_CONF" || fail "net-cafe.conf has a syntax error"
grep -qF 'WantedBy=timers.target' "$TIMER" || fail "timer must be installable into timers.target"
grep -qF 'anios-cafe watchdog' "$UNIT" || fail "service must run 'anios-cafe watchdog'"

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
HOME_DIR="$TMP/home"
STATE_DIR="$HOME_DIR/.local/state/anios"
OUTSIDE="$TMP/outside"
mkdir -p "$HOME_DIR"/{.config/google-chrome,.config/hypr,.local/share/anios,.local/share/Steam/steamapps,Desktop,Downloads,Documents,.cache/mozilla}
mkdir -p "$OUTSIDE"
printf 'profile\n' >"$HOME_DIR/.config/google-chrome/History"
printf 'conf\n' >"$HOME_DIR/.config/hypr/hyprland.lua"
printf 'log\n' >"$HOME_DIR/.local/share/anios/session.log"
printf 'game\n' >"$HOME_DIR/.local/share/Steam/steamapps/libraryfolders.vdf"
printf 'shortcut\n' >"$HOME_DIR/Desktop/Steam.desktop"
printf 'download\n' >"$HOME_DIR/Downloads/setup.exe"
printf 'doc\n' >"$HOME_DIR/Documents/note.txt"
printf 'cookie\n' >"$HOME_DIR/.cache/mozilla/cookies.sqlite"
printf 'important\n' >"$OUTSIDE/keep.txt"
ln -s "$OUTSIDE" "$HOME_DIR/.steam"          # symlink trỏ ra ngoài home
CONF="$TMP/net-cafe.conf"
CMDLINE="$TMP/cmdline"
: >"$CMDLINE"

# run_lib <snippet>: chạy một đoạn bash trong môi trường giả lập.
run_lib() {
  env -i PATH="$PATH" HOME="$HOME_DIR" \
    ANIOS_CAFE_HOME="$HOME_DIR" \
    ANIOS_CAFE_ETC_CONF="$CONF" \
    ANIOS_CAFE_CMDLINE_FILE="$CMDLINE" \
    ANIOS_CAFE_STATE_DIR="$STATE_DIR" \
    ANIOS_CAFE_RUN_DIR="$TMP/run" \
    bash -c "set -Eeuo pipefail; . \"\$1\"; shift; $1" _ "$LIB"
}

# --- 1. Đường dẫn không an toàn phải bị từ chối ------------------------------
status=0
env -i PATH="$PATH" ANIOS_CAFE_HOME="$HOME_DIR" bash -c '
  set -Eeuo pipefail
  . "$1"
  for bad in "" "/etc/passwd" "../etc/passwd" "Downloads/../../etc" ; do
    if _anios_cafe_safe_path "$bad" >/dev/null; then
      echo "unsafe path accepted: $bad" >&2
      exit 1
    fi
  done
  _anios_cafe_safe_path "Downloads" >/dev/null
' _ "$LIB" || status=$?
(( status == 0 )) || fail "unsafe paths must be rejected (exit $status)"
pass "unsafe paths rejected"

# --- 2. Mặc định TẮT: không xoá gì ------------------------------------------
printf 'ANIOS_CAFE_ENABLE=0\n' >"$CONF"
run_lib '
  anios_cafe_load_config
  [[ "$ANIOS_CAFE_ENABLE" == 0 ]] || { echo "enable default broken" >&2; exit 1; }
  [[ "$ANIOS_CAFE_WIPE_ON_START" == 0 ]] || { echo "wipe must follow the master switch" >&2; exit 1; }
' || fail "disabled config must leave the flags off"
[[ -f "$HOME_DIR/Downloads/setup.exe" ]] || fail "disabled mode must not delete anything"
pass "off by default"

# --- 3. Tham số nhân anios.cafe=1 bật được ----------------------------------
printf 'BOOT_IMAGE=/vmlinuz root=/dev/sda1 anios.cafe=1 quiet\n' >"$CMDLINE"
run_lib '
  anios_cafe_load_config
  [[ "$ANIOS_CAFE_ENABLE" == 1 ]] || { echo "cmdline must enable the mode" >&2; exit 1; }
  [[ "$ANIOS_CAFE_WIPE_ON_START" == 1 ]] || { echo "sub-switch must follow cmdline" >&2; exit 1; }
' || fail "anios.cafe=1 on the kernel command line must enable the mode"
: >"$CMDLINE"
pass "kernel parameter anios.cafe=1"

# --- 4. --dry-run không xoá gì, và liệt kê đúng mục -------------------------
printf 'ANIOS_CAFE_ENABLE=1\n' >"$CONF"
dry_out="$(env -i PATH="$PATH" HOME="$HOME_DIR" ANIOS_CAFE_HOME="$HOME_DIR" \
  ANIOS_CAFE_ETC_CONF="$CONF" ANIOS_CAFE_CMDLINE_FILE="$CMDLINE" \
  ANIOS_CAFE_STATE_DIR="$STATE_DIR" \
  "$CLI" clean --dry-run 2>&1)" || fail "clean --dry-run must succeed"
grep -qF 'SẼ XOÁ .config/google-chrome' <<<"$dry_out" || fail "dry-run must list the browser profile"
grep -qF 'SẼ DỌN Downloads' <<<"$dry_out" || fail "dry-run must list the emptied directories"
[[ -f "$HOME_DIR/Downloads/setup.exe" && -f "$HOME_DIR/.config/google-chrome/History" ]] ||
  fail "dry-run must not delete anything"
pass "dry-run lists without deleting"

# --- 5. Dọn thật: xoá đúng, giữ đúng ----------------------------------------
run_lib 'anios_cafe_load_config; anios_cafe_clean 0 >/dev/null' || fail "clean must succeed"
for gone in .config/google-chrome .local/share/Steam .cache/mozilla .steam; do
  [[ -e "$HOME_DIR/$gone" || -L "$HOME_DIR/$gone" ]] && fail "must be removed: $gone"
done
for kept in .config/hypr/hyprland.lua .local/share/anios/session.log Desktop/Steam.desktop; do
  [[ -e "$HOME_DIR/$kept" ]] || fail "must be kept: $kept"
done
[[ -d "$HOME_DIR/Downloads" ]] || fail "Downloads must still exist (only its contents are removed)"
[[ -z "$(ls -A "$HOME_DIR/Downloads")" ]] || fail "Downloads must be empty after cleaning"
[[ -z "$(ls -A "$HOME_DIR/Documents")" ]] || fail "Documents must be empty after cleaning"
[[ -f "$OUTSIDE/keep.txt" ]] || fail "a symlink pointing outside HOME must not delete the target"
pass "clean removes customer data and keeps the desktop"

# --- 6. CLI: on/off ghi cấu hình người dùng, --system cần root ----------------
printf 'ANIOS_CAFE_ENABLE=0\n' >"$CONF"
user_env() {
  env -i PATH="$PATH" HOME="$HOME_DIR" ANIOS_CAFE_HOME="$HOME_DIR" \
    ANIOS_CAFE_ETC_CONF="$CONF" ANIOS_CAFE_CMDLINE_FILE="$CMDLINE" \
    ANIOS_CAFE_STATE_DIR="$STATE_DIR" "$@"
}
user_env "$CLI" on >/dev/null || fail "anios-cafe on must succeed"
grep -qxF 'ANIOS_CAFE_ENABLE=1' "$HOME_DIR/.config/anios/net-cafe.conf" ||
  fail "anios-cafe on must write the user config"
# Ghi ra biến rồi mới grep: `grep -q` thoát sớm làm lệnh ghi bị SIGPIPE, và với
# `pipefail` cả pipeline sẽ "thất bại" dù nội dung đã đúng.
status_out="$(user_env "$CLI" status 2>&1)"
grep -qF 'BẬT' <<<"$status_out" || fail "status must report the mode as on"
user_env "$CLI" off >/dev/null || fail "anios-cafe off must succeed"
grep -qxF 'ANIOS_CAFE_ENABLE=0' "$HOME_DIR/.config/anios/net-cafe.conf" ||
  fail "anios-cafe off must rewrite the user config"
if (( EUID != 0 )); then
  status=0
  user_env "$CLI" on --system >/dev/null 2>&1 || status=$?
  (( status == 1 )) || fail "on --system without root must exit 1, got $status"
fi
pass "on/off and the root guard"

# --- 7. clean từ chối khi Steam/trình duyệt vẫn chạy (trừ --force) -----------
SHIMS="$TMP/shims"
mkdir -p "$SHIMS"
printf '#!/usr/bin/env bash\nexit 0\n' >"$SHIMS/pgrep"
chmod 0755 "$SHIMS/pgrep"
status=0
env -i PATH="$SHIMS:$PATH" HOME="$HOME_DIR" ANIOS_CAFE_HOME="$HOME_DIR" \
  ANIOS_CAFE_ETC_CONF="$CONF" ANIOS_CAFE_CMDLINE_FILE="$CMDLINE" \
  ANIOS_CAFE_STATE_DIR="$STATE_DIR" "$CLI" clean >/dev/null 2>&1 || status=$?
(( status == 3 )) || fail "clean must refuse (exit 3) while Steam is running, got $status"
printf 'ANIOS_CAFE_ENABLE=1\nANIOS_CAFE_REBOOT_ON_CRASH=1\n' >"$CONF"
env -i PATH="$SHIMS:$PATH" HOME="$HOME_DIR" ANIOS_CAFE_HOME="$HOME_DIR" \
  ANIOS_CAFE_ETC_CONF="$CONF" ANIOS_CAFE_CMDLINE_FILE="$CMDLINE" \
  ANIOS_CAFE_STATE_DIR="$STATE_DIR" "$CLI" clean --force >/dev/null 2>&1 ||
  fail "clean --force must proceed while apps are running"
pass "clean refuses while apps run, --force overrides"

# --- 8. Watchdog: chỉ reboot khi bật, đúng ngưỡng, một lần mỗi lần boot ------
REBOOT_LOG="$TMP/reboot.log"
printf '#!/usr/bin/env bash\nprintf "reboot\\n" >>"%s"\n' "$REBOOT_LOG" >"$TMP/fake-reboot"
chmod 0755 "$TMP/fake-reboot"
mkdir -p "$STATE_DIR"
: >"$STATE_DIR/session-failures"
now="$(date +%s)"
printf '%s\n%s\n%s\n' "$now" "$now" "$now" >"$STATE_DIR/session-failures"

watchdog_env() {
  env -i PATH="$PATH" HOME="$TMP/root-home" ANIOS_CAFE_HOME="$HOME_DIR" \
    ANIOS_CAFE_ETC_CONF="$CONF" ANIOS_CAFE_CMDLINE_FILE="$CMDLINE" \
    ANIOS_CAFE_STATE_DIR="$STATE_DIR" ANIOS_CAFE_RUN_DIR="$TMP/run" \
    ANIOS_CAFE_REBOOT_CMD="$TMP/fake-reboot" "$CLI" watchdog
}
: >"$REBOOT_LOG"
watchdog_env >/dev/null 2>&1 || fail "watchdog must exit 0"
grep -qxF 'reboot' "$REBOOT_LOG" || fail "watchdog must reboot after the threshold when enabled"
: >"$REBOOT_LOG"
watchdog_env >/dev/null 2>&1 || fail "second watchdog run must exit 0"
[[ ! -s "$REBOOT_LOG" ]] || fail "watchdog must reboot at most once per boot"
[[ ! -s "$STATE_DIR/session-failures" ]] || fail "watchdog must clear the failure counter before rebooting"

printf 'ANIOS_CAFE_ENABLE=1\nANIOS_CAFE_REBOOT_ON_CRASH=0\n' >"$CONF"
rm -rf "$TMP/run"
printf '%s\n%s\n%s\n' "$now" "$now" "$now" >"$STATE_DIR/session-failures"
: >"$REBOOT_LOG"
watchdog_env >/dev/null 2>&1 || fail "watchdog must exit 0 when auto-reboot is off"
[[ ! -s "$REBOOT_LOG" ]] || fail "watchdog must not reboot when ANIOS_CAFE_REBOOT_ON_CRASH=0"

printf 'ANIOS_CAFE_ENABLE=1\nANIOS_CAFE_REBOOT_ON_CRASH=1\n' >"$CONF"
rm -rf "$TMP/run"
printf '%s\n' "$((now - 3600))" >"$STATE_DIR/session-failures"
: >"$REBOOT_LOG"
watchdog_env >/dev/null 2>&1
[[ ! -s "$REBOOT_LOG" ]] || fail "old failures outside the window must not trigger a reboot"
pass "watchdog thresholds, window and one-reboot-per-boot"

# --- 9. anios-session dùng đúng thư viện ------------------------------------
grep -qF 'ANIOS_CAFE_LIB:-/usr/local/lib/anios/cafe.sh' "$SESSION" ||
  fail "anios-session must source the net cafe library"
grep -qF 'anios_cafe_clean' "$SESSION" || fail "anios-session must clean at session start"
grep -qF 'anios_cafe_record_failure' "$SESSION" ||
  fail "anios-session must record fast failures for the watchdog"
pass "anios-session integration"

# --- 10. Chạy thật anios-session: dọn dữ liệu + đếm phiên chết --------------
# Đây là bài duy nhất chứng minh phần tích hợp, không chỉ từng hàm rời: một phiên
# Hyprland "chết ngay" phải (a) dọn dữ liệu khách trước khi compositor khởi động,
# (b) để lại bộ đếm cho watchdog, và (c) không được làm hỏng cơ chế thử lại chế độ
# an toàn sẵn có của anios-session.
mkdir -p "$TMP/session-bin" "$HOME_DIR/.config/google-chrome" "$HOME_DIR/Downloads"
printf '#!/usr/bin/env bash\nshift  # bỏ "--"\nexec "$@"\n' >"$TMP/session-bin/dbus-run-session"
printf '#!/usr/bin/env bash\nexit 1\n' >"$TMP/session-bin/Hyprland"
chmod 0755 "$TMP/session-bin/dbus-run-session" "$TMP/session-bin/Hyprland"
printf 'cookie\n' >"$HOME_DIR/.config/google-chrome/Cookies"
printf 'file khách\n' >"$HOME_DIR/Downloads/game.exe"
printf 'ANIOS_CAFE_ENABLE=1\n' >"$CONF"
# Bước 6 đã ghi 'off' vào cấu hình người dùng, mà file người dùng đè file /etc:
# bỏ nó để mô phỏng đúng cảnh "quán bật bằng --system".
rm -f "$HOME_DIR/.config/anios/net-cafe.conf"
rm -rf "$STATE_DIR" "$TMP/run"
set +e
env -i PATH="$TMP/session-bin:$PATH" HOME="$HOME_DIR" \
  ANIOS_CAFE_LIB="$LIB" ANIOS_CAFE_HOME="$HOME_DIR" \
  ANIOS_CAFE_ETC_CONF="$CONF" ANIOS_CAFE_CMDLINE_FILE="$CMDLINE" \
  ANIOS_CAFE_STATE_DIR="$STATE_DIR" \
  bash "$SESSION" >"$TMP/session.out" 2>&1
session_status=$?
set -e
[[ ! -e "$HOME_DIR/.config/google-chrome" ]] ||
  fail "anios-session must wipe the previous customer's browser profile"
[[ -z "$(ls -A "$HOME_DIR/Downloads")" ]] || fail "anios-session must empty Downloads"
(( session_status != 0 )) || fail "a dying Hyprland must be reported through the exit status"
failures="$(wc -l <"$STATE_DIR/session-failures" 2>/dev/null || echo 0)"
(( failures >= 1 )) ||
  fail "anios-session must record the fast failure for the watchdog (got: $failures)"
grep -qF 'net-cafe: wiped' "$HOME_DIR/.local/share/anios/session.log" ||
  fail "the wipe must be recorded in the session log"
grep -qF 'net-cafe: fast failure recorded' "$HOME_DIR/.local/share/anios/session.log" ||
  fail "the failure counter must be recorded in the session log"
grep -qF 'retrying in safe mode' "$HOME_DIR/.local/share/anios/session.log" ||
  fail "the net cafe accounting must not break the existing safe-mode retry"
pass "anios-session wipes the previous customer and records fast failures"

echo "All anios-cafe self-tests passed."
