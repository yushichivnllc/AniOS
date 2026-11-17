#!/usr/bin/env bash
# Tự kiểm tra profile/airootfs/usr/local/bin/anios-session — lớp mỏng nằm giữa SDDM
# và Hyprland, nơi đã xảy ra lỗi "không vào được giao diện":
#   * cờ --safe phải tới được cấu hình Hyprland qua ANIOS_SAFE;
#   * Hyprland thoát ngay với mã lỗi thì phải tự thử lại một lần ở chế độ an toàn;
#   * Hyprland thoát bình thường (Super+Shift+E) thì KHÔNG được chạy lại;
#   * nhật ký phiên phải ghi hồ sơ GPU + mã thoát để `anios-gpu-doctor` đọc được.
#
# dbus-run-session và Hyprland được thay bằng bản giả, mỗi lượt chạy ghi lại môi
# trường và mã thoát mong muốn. Không cần Wayland, GPU hay D-Bus thật.
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SESSION="$ROOT_DIR/profile/airootfs/usr/local/bin/anios-session"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

[[ -x "$SESSION" ]] || fail "anios-session must be executable"
bash -n "$SESSION" || fail "anios-session has a syntax error"

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

SHIMS="$TMP/bin"
mkdir -p "$SHIMS"

cat >"$SHIMS/dbus-run-session" <<'EOF'
#!/usr/bin/env bash
# Bỏ qua phần quản lý D-Bus: chỉ chạy đúng lệnh phía sau "--".
while [[ $# -gt 0 && "$1" != "--" ]]; do shift; done
shift || true
exec "$@"
EOF

cat >"$SHIMS/Hyprland" <<'EOF'
#!/usr/bin/env bash
{
  printf 'ANIOS_SAFE=%s\n' "${ANIOS_SAFE:-}"
  printf 'ANIOS_GPU=%s\n' "${ANIOS_GPU:-}"
  printf 'ANIOS_DESKTOP=%s\n' "${ANIOS_DESKTOP:-}"
  printf 'XDG_SESSION_TYPE=%s\n' "${XDG_SESSION_TYPE:-}"
} >>"$ANIOS_TEST_ENV_LOG"
# Số lần đã chạy quyết định mã thoát: "1 0" = chết rồi lên được ở chế độ an toàn.
count=$(( $(cat "$ANIOS_TEST_COUNT" 2>/dev/null || echo 0) + 1 ))
printf '%s\n' "$count" >"$ANIOS_TEST_COUNT"
exit_code="$(sed -n "${count}p" "$ANIOS_TEST_EXIT_CODES")"
[[ -n "$exit_code" ]] || exit_code=0
exit "$exit_code"
EOF
chmod +x "$SHIMS/dbus-run-session" "$SHIMS/Hyprland"

# run_session <name> <exit-codes> [tham số của anios-session...]
run_session() {
  local name="$1" codes="$2"
  shift 2
  export ANIOS_TEST_ENV_LOG="$TMP/$name.env"
  export ANIOS_TEST_COUNT="$TMP/$name.count"
  export ANIOS_TEST_EXIT_CODES="$TMP/$name.codes"
  : >"$ANIOS_TEST_ENV_LOG"
  printf '%s\n' $codes >"$ANIOS_TEST_EXIT_CODES"
  rm -f "$ANIOS_TEST_COUNT"
  env -i PATH="$SHIMS:/usr/bin:/bin" HOME="$TMP/$name-home" \
    ANIOS_TEST_ENV_LOG="$ANIOS_TEST_ENV_LOG" \
    ANIOS_TEST_COUNT="$ANIOS_TEST_COUNT" \
    ANIOS_TEST_EXIT_CODES="$ANIOS_TEST_EXIT_CODES" \
    "${SESSION}" "$@"
  # `env -i` không mang biến của shell gọi, nên mã thoát lấy từ $? của env.
}

mkdir -p "$TMP/home"

# --- 1. Phiên bình thường: không cờ, Hyprland thoát 0 ----------------------
status=0
run_session normal '0' || status=$?
(( status == 0 )) || fail "a clean exit must return 0, got $status"
grep -qxF 'ANIOS_SAFE=' "$TMP/normal.env" ||
  fail "the normal session must not set ANIOS_SAFE"
[[ "$(cat "$TMP/normal.count")" == 1 ]] || fail "a clean exit must not start Hyprland twice"
pass "normal session starts Hyprland once"

# --- 2. --safe: ANIOS_SAFE=1 tới được cấu hình ------------------------------
status=0
run_session safe '0' --safe || status=$?
(( status == 0 )) || fail "--safe must still return the compositor status"
grep -qxF 'ANIOS_SAFE=1' "$TMP/safe.env" ||
  fail "--safe must export ANIOS_SAFE=1 for hyprland/nvidia.lua"
pass "--safe reaches the Hyprland configuration"

# --- 3. --minimal + --safe cùng lúc ----------------------------------------
status=0
run_session minimal '0' --minimal --safe || status=$?
(( status == 0 )) || fail "--minimal --safe must succeed"
grep -qxF 'ANIOS_DESKTOP=minimal' "$TMP/minimal.env" ||
  fail "--minimal must select the Minimal desktop"
grep -qxF 'ANIOS_SAFE=1' "$TMP/minimal.env" ||
  fail "--safe after --minimal must still be honoured"
pass "--minimal and --safe combine"

# --- 4. Hyprland chết ngay: tự lùi về chế độ an toàn ----------------------
status=0
run_session retry '1 0' || status=$?
(( status == 0 )) || fail "the safe-mode retry must return the retry status, got $status"
[[ "$(cat "$TMP/retry.count")" == 2 ]] ||
  fail "a fast failure must be retried exactly once (runs: $(cat "$TMP/retry.count"))"
grep -qxF 'ANIOS_SAFE=' "$TMP/retry.env" || fail "the first attempt must not be a safe session"
grep -qxF 'ANIOS_SAFE=1' "$TMP/retry.env" || fail "the retry must be a safe session"
grep -qF 'retrying in safe mode' "$TMP/retry-home/.local/share/anios/session.log" ||
  fail "the retry must be recorded in the session log"
grep -qF 'exited with status 1' "$TMP/retry-home/.local/share/anios/session.log" ||
  fail "the session log must keep the compositor exit status"
pass "fast failure falls back to the safe session"

# --- 5. Hyprland chết cả hai lần: thoát với mã lỗi, không lặp vô hạn -------
status=0
run_session double '1 1' || status=$?
(( status == 1 )) || fail "a failing safe session must return its status, got $status"
[[ "$(cat "$TMP/double.count")" == 2 ]] ||
  fail "there must be at most one retry (runs: $(cat "$TMP/double.count"))"
pass "a failing session is not retried forever"

# --- 6. Phiên đã là --safe mà Hyprland chết: không thử lại ----------------
status=0
run_session safe_only '1' --safe || status=$?
(( status == 1 )) || fail "a failing --safe session must return its status, got $status"
[[ "$(cat "$TMP/safe_only.count")" == 1 ]] ||
  fail "an explicit --safe session must not retry itself"
pass "explicit --safe sessions do not retry"

echo "All anios-session self-tests passed."
