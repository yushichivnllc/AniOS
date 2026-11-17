#!/usr/bin/env bash
# Tự kiểm tra profile/airootfs/usr/local/bin/anios-dmesg-check.
#
# Bài này khoá hai điều quan trọng:
#   1. Lỗi firmware ACPI (_DSM khai báo trùng) và dòng "RAS: Correctable Errors
#      collector initialized" phải được xếp vào nhóm VÔ HẠI và KHÔNG được làm
#      công cụ trả mã thoát 1 — nếu không, người dùng lại đi sửa một thứ không
#      hỏng và bỏ qua lỗi thật.
#   2. Segfault / OOM / lỗi ổ đĩa / GPU treo phải được báo là CẦN SỬA, kèm tên
#      chương trình bị crash và lệnh tra cứu core dump.
# Chạy hoàn toàn trên tệp giả, không cần root hay dmesg thật.
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT_DIR/profile/airootfs/usr/local/bin/anios-dmesg-check"
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

[[ -x "$CHECK" ]] || fail "anios-dmesg-check must exist and be executable"
bash -n "$CHECK" || fail "anios-dmesg-check has a syntax error"

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

# run_check <file> [args...]: chạy công cụ trên tệp giả, in stdout, trả mã thoát.
run_check() {
  local file="$1"
  shift
  ANIOS_DMESG_FILE="$file" "$CHECK" "$@" 2>&1
}

# --- 1. Đúng dmesg của máy B760 + RTX 3070 mà người dùng gửi -----------------
user_log="$TMP/user.log"
cat >"$user_log" <<'EOF'
[Tue Nov 17 23:50:13 2026] RAS: Correctable Errors collector initialized.
[Tue Nov 17 23:50:29 2026] ACPI BIOS Error (bug): Failure creating named object [\_SB.PC00.PEG1.PEGP._DSM.USRG], AE_ALREADY_EXISTS (20260408/dsfield-184)
[Tue Nov 17 23:50:29 2026] ACPI Error: AE_ALREADY_EXISTS, CreateBufferField failure (20260408/dswload2-477)
[Tue Nov 17 23:50:29 2026] ACPI Error: Aborting method \_SB.PC00.PEG1.PEGP._DSM due to previous error (AE_ALREADY_EXISTS) (20260408/psparse-543)
[Tue Nov 17 23:50:29 2026] nvidia 0000:01:00.0: enabling device (0000 -> 0003)
[Wed Nov 18 00:20:33 2026] hyprland-update[25021]: segfault at cc ip 00007faba83f7111 sp 00007fff52320f20 error 6 in libwayland-client.so.0.26.0[6111,7faba83f4000+7000] likely on CPU 19 (core 31, socket 0)
EOF
status=0
out="$(run_check "$user_log")" || status=$?
(( status == 1 )) || fail "a segfault must exit 1, got $status"
grep -qF '[VÔ HẠI]' <<<"$out" || fail "ACPI BIOS errors must be classified as harmless"
grep -qF 'AE_ALREADY_EXISTS' <<<"$out" || fail "must explain the ACPI _DSM duplicate-object bug"
grep -qF 'RAS: Correctable Errors collector initialized' <<<"$out" || fail "must list the RAS line as noise"
grep -qF '[CẦN SỬA]' <<<"$out" || fail "the segfault must be reported as a real problem"
grep -qF 'Chương trình bị crash: hyprland-update' <<<"$out" ||
  fail "must name the crashin program (hyprland-update)"
grep -qF 'coredumpctl info hyprland-update' <<<"$out" ||
  fail "must give the exact coredumpctl command"
grep -qF 'libwayland-client' <<<"$out" || fail "must show the crashing line as an example"
pass "the user's dmesg: ACPI noise explained, segfault reported"

# --- 2. Chỉ có dòng vô hại: mã thoát 0, không có nhóm CẦN SỬA ----------------
clean_log="$TMP/clean.log"
cat >"$clean_log" <<'EOF'
[Tue Nov 17 23:50:13 2026] RAS: Correctable Errors collector initialized.
[Tue Nov 17 23:50:29 2026] ACPI BIOS Error (bug): Failure creating named object [\_SB.PC00.PEG1.PEGP._DSM.USRG], AE_ALREADY_EXISTS (20260408/dsfield-184)
[Wed Nov 18 00:00:00 2026] r8169 0000:04:00.0 enp4s0: Link is Up - 1Gbps/Full - flow control rx/tx
EOF
status=0
out="$(run_check "$clean_log")" || status=$?
(( status == 0 )) || fail "harmless firmware noise must exit 0, got $status"
! grep -qF '[CẦN SỬA]' <<<"$out" || fail "harmless noise must not be reported as a failure: $out"
grep -qF 'không có lỗi thật' <<<"$out" || fail "must conclude that nothing needs fixing"
pass "firmware-only log exits 0"

# --- 3. OOM: phải báo hết RAM, kèm tiến trình bị kill ------------------------
oom_log="$TMP/oom.log"
cat >"$oom_log" <<'EOF'
[Wed Nov 18 01:00:00 2026] Out of memory: Killed process 4242 (firefox) total-vm:9123456kB, anon-rss:8123456kB
EOF
status=0
out="$(run_check "$oom_log")" || status=$?
(( status == 1 )) || fail "an OOM kill must exit 1, got $status"
grep -qF '[CẦN SỬA]' <<<"$out" || fail "OOM must be a real problem"
grep -qF 'zramctl' <<<"$out" || fail "OOM advice must mention zram/RAM"
pass "OOM kill reported"

# --- 4. GPU treo và lỗi ổ đĩa: hai nhóm lỗi thật khác nhau -------------------
fatal_log="$TMP/fatal.log"
cat >"$fatal_log" <<'EOF'
[Wed Nov 18 02:00:00 2026] NVRM: Xid (PCI:0000:01:00): 79, pid=1234, GPU has fallen off the bus.
[Wed Nov 18 02:10:00 2026] blk_update_request: I/O error, dev sda, sector 12345 op 0x0:(READ)
EOF
status=0
out="$(run_check "$fatal_log" 2>&1)" || status=$?
(( status == 1 )) || fail "GPU/disk errors must exit 1, got $status"
grep -qF 'GPU treo' <<<"$out" || fail "must name the GPU hang"
grep -qF 'Lỗi đọc/ghi ổ đĩa' <<<"$out" || fail "must name the disk error"
grep -qF 'smartctl' <<<"$out" || fail "disk advice must mention SMART"
pass "GPU hang and disk error reported separately"

# --- 5. --quiet: ẩn nhóm VÔ HẠI, vẫn giữ nhóm cần sửa ------------------------
out="$(run_check "$user_log" --quiet)" || true
! grep -qF '[VÔ HẠI]' <<<"$out" || fail "--quiet must hide harmless groups"
grep -qF '[CẦN SỬA]' <<<"$out" || fail "--quiet must keep real problems"

# --- 6. Nhật ký không có gì đáng chú ý: thoát 0 ------------------------------
plain_log="$TMP/plain.log"
printf '[Wed Nov 18 03:00:00 2026] EXT4-fs (sda2): mounted filesystem with ordered data mode\n' \
  >"$plain_log"
status=0
run_check "$plain_log" >/dev/null || status=$?
(( status == 0 )) || fail "a clean log must exit 0, got $status"

# --- 7. Tệp không đọc được: lỗi rõ ràng, mã thoát 2 -------------------------
status=0
ANIOS_DMESG_FILE="$TMP/does-not-exist" "$CHECK" >/dev/null 2>&1 || status=$?
(( status == 2 )) || fail "an unreadable source must exit 2, got $status"

# --- 8. --help --------------------------------------------------------------
"$CHECK" --help | grep -qF 'anios-dmesg-check' || fail "--help must describe itself"

pass "options, clean log and error paths"
echo "All anios-dmesg-check self-tests passed."
