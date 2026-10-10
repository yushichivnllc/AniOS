#!/usr/bin/env bash
# Tự kiểm tra bước "đối chiếu gói AUR trong pacman DB của airootfs" ở cuối
# scripts/build-iso.sh mà không cần dựng ISO, không cần Arch, không cần root.
#
# Vì sao có bài này: bước đó từng là `pacman -Qq --sysroot <airootfs>`. Với
# --sysroot pacman nạp thêm sync DB của sysroot nên mỗi gói lại in ra
#
#     warning: database file for 'core' does not exist (use '-Sy' to download)
#
# dù truy vấn -Q không cần sync DB: một lượt dựng in hàng chục dòng cảnh báo vô
# nghĩa ngay trước dòng kết quả thật. Cách sửa là đọc thẳng
# var/lib/pacman/local/<tên>-<pkgver>-<pkgrel> — đúng cái mà pkglist trên ISO
# cũng được sinh ra từ đó, và đúng cách scripts/check-live-aur.sh đang dùng.
#
# Bài này nạp ĐÚNG hai hàm anios_airootfs_db_entries() và
# anios_report_aur_packages() từ scripts/build-iso.sh (không chép lại logic, nên
# sửa hàm là bài này thấy ngay) rồi chạy trên các cây airootfs giả:
#
#   1. đủ gói AUR             -> in đúng "tên pkgver-pkgrel", trả về 0
#   2. thiếu một gói AUR      -> trả về 1 và điền AUR_MISSING_PACKAGES
#   3. gói trùng tiền tố      -> "yay" không được khớp nhầm "yay-bin" (và ngược lại)
#   4. pkgver có dấu ':'      -> epoch vẫn tách đúng tên gói
#   5. file lạ trong DB       -> bị bỏ qua, không sinh gói ma
#   6. không có pacman DB     -> mọi gói đều báo thiếu, glob không nổ
#   7. tên gói có dấu '.'     -> khớp theo nghĩa đen, không phải regex
#   8. không còn pacman --sysroot -> nguyên nhân của loạt cảnh báo đã bị bỏ
#
# Chạy: ./scripts/selftest-iso-aur-verify.sh
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ISO="$ROOT_DIR/scripts/build-iso.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

# Nạp đúng hai hàm từ build-iso.sh (giữ nguyên tên để sửa hàm là bài này thấy).
load_functions() {
  local name start end
  for name in anios_airootfs_db_entries anios_report_aur_packages; do
    start="$(grep -n "^${name}() {" "$BUILD_ISO" | cut -d: -f1)" ||
      fail "build-iso.sh no longer defines ${name}()"
    end="$(awk -v from="$start" 'NR > from && /^}/ { print NR; exit }' "$BUILD_ISO")" ||
      fail "cannot find the end of ${name}()"
    sed -n "${start},${end}p" "$BUILD_ISO"
  done
}

# shellcheck source=/dev/null
eval "$(load_functions)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Tạo pacman DB giả: mỗi gói là một thư mục <tên>-<pkgver>-<pkgrel>.
make_db() {
  local root="$1"
  shift
  mkdir -p "$root/var/lib/pacman/local"
  local entry
  for entry in "$@"; do
    mkdir -p "$root/var/lib/pacman/local/$entry"
  done
}

# Chạy hàm trong shell HIỆN TẠI (không phải $()): AUR_MISSING_PACKAGES phải còn
# lại được, đúng như lúc build-iso.sh gọi. Đầu ra để trong $REPORT_FILE, mã lỗi
# trong $REPORT_RC.
REPORT_FILE="$WORK/report.txt"
REPORT_RC=0
run_report() {
  REPORT_RC=0
  anios_report_aur_packages "$@" >"$REPORT_FILE" || REPORT_RC=$?
}

AUR_PKGNAMES=(calamares yay coccoc-browser-stable legacy-launcher)

# --- 1. Đủ gói AUR ---------------------------------------------------------
full="$WORK/full"
make_db "$full" \
  "calamares-3.4.2-2" \
  "yay-13.0.1-1" \
  "coccoc-browser-stable-152.0.7977.124-1" \
  "legacy-launcher-latest-1" \
  "linux-zen-6.16.9.zen1-1"
AUR_MISSING_PACKAGES=()
run_report "$full" "${AUR_PKGNAMES[@]}"
[[ "$REPORT_RC" -eq 0 ]] || fail "đủ gói mà hàm trả về $REPORT_RC"
[[ "$(grep -c . <"$REPORT_FILE")" -eq 4 ]] || fail "phải báo đúng 4 gói: $(cat "$REPORT_FILE")"
grep -qxF "AUR package baked into the image: calamares 3.4.2-2" "$REPORT_FILE" ||
  fail "thiếu dòng calamares: $(cat "$REPORT_FILE")"
grep -qxF "AUR package baked into the image: yay 13.0.1-1" "$REPORT_FILE" ||
  fail "thiếu dòng yay: $(cat "$REPORT_FILE")"
grep -qxF "AUR package baked into the image: legacy-launcher latest-1" "$REPORT_FILE" ||
  fail "thiếu dòng legacy-launcher: $(cat "$REPORT_FILE")"
pass "báo cáo đủ 4 gói AUR kèm phiên bản"

# --- 2. Thiếu một gói AUR --------------------------------------------------
partial="$WORK/partial"
make_db "$partial" "calamares-3.4.2-2" "yay-13.0.1-1" "coccoc-browser-stable-152.0.7977.124-1"
AUR_MISSING_PACKAGES=()
run_report "$partial" "${AUR_PKGNAMES[@]}"
[[ "$REPORT_RC" -eq 1 ]] || fail "thiếu gói phải trả về 1, nhận được $REPORT_RC"
[[ "${AUR_MISSING_PACKAGES[*]}" == "legacy-launcher" ]] ||
  fail "AUR_MISSING_PACKAGES sai: ${AUR_MISSING_PACKAGES[*]:-<rỗng>}"
grep -qxF "AUR package baked into the image: yay 13.0.1-1" "$REPORT_FILE" ||
  fail "gói có trong DB vẫn phải được báo: $(cat "$REPORT_FILE")"
pass "gói thiếu được liệt kê, gói còn lại vẫn được báo"

# --- 3. Tiền tố tên gói không được khớp nhầm -------------------------------
prefix="$WORK/prefix"
make_db "$prefix" "yay-bin-13.0.1-1" "calamares-3.4.2-2" "legacy-launcher-latest-1" \
  "coccoc-browser-stable-152.0.7977.124-1"
AUR_MISSING_PACKAGES=()
run_report "$prefix" "${AUR_PKGNAMES[@]}"
[[ "$REPORT_RC" -eq 1 ]] || fail "yay-bin không được coi là yay"
[[ "${AUR_MISSING_PACKAGES[*]}" == "yay" ]] ||
  fail "yay-bin khớp nhầm thành yay: ${AUR_MISSING_PACKAGES[*]:-<rỗng>}"
pass "yay-bin không bị coi là yay"

# --- 4. pkgver có dấu ':' (epoch) ------------------------------------------
epoch="$WORK/epoch"
make_db "$epoch" "calamares-2:3.4.2-2" "yay-13.0.1-1" \
  "coccoc-browser-stable-152.0.7977.124-1" "legacy-launcher-latest-1"
AUR_MISSING_PACKAGES=()
run_report "$epoch" "${AUR_PKGNAMES[@]}"
[[ "$REPORT_RC" -eq 0 ]] || fail "pkgver kiểu epoch làm báo thiếu oan"
grep -qxF "AUR package baked into the image: calamares 2:3.4.2-2" "$REPORT_FILE" ||
  fail "pkgver có epoch bị tách sai: $(cat "$REPORT_FILE")"
pass "pkgver kiểu epoch (2:3.4.2) được tách đúng"

# --- 5. File lạ trong DB không sinh gói ma ---------------------------------
junk="$WORK/junk"
make_db "$junk" "calamares-3.4.2-2" "yay-13.0.1-1" "coccoc-browser-stable-152.0.7977.124-1" \
  "legacy-launcher-latest-1"
touch "$junk/var/lib/pacman/local/khong-phai-thu-muc"
mkdir -p "$junk/var/lib/pacman/local/db.lck" # thư mục rỗng cũng không phải gói
AUR_MISSING_PACKAGES=()
run_report "$junk" "${AUR_PKGNAMES[@]}"
[[ "$REPORT_RC" -eq 0 ]] || fail "file/thư mục lạ trong pacman DB làm báo thiếu oan"
[[ -z "${AUR_MISSING_PACKAGES[*]:-}" ]] ||
  fail "file lạ bị coi là gói: ${AUR_MISSING_PACKAGES[*]:-}"
pass "file/thư mục lạ trong pacman DB bị bỏ qua"

# --- 6. Không có pacman DB --------------------------------------------------
empty="$WORK/empty"
mkdir -p "$empty/var/lib/pacman/local"
AUR_MISSING_PACKAGES=()
run_report "$empty" "${AUR_PKGNAMES[@]}"
[[ "$REPORT_RC" -eq 1 ]] || fail "không có gói nào thì mọi gói phải báo thiếu"
[[ "${#AUR_MISSING_PACKAGES[@]}" -eq 4 ]] ||
  fail "phải báo thiếu cả 4 gói: ${AUR_MISSING_PACKAGES[*]:-}"
# Không có cả var/lib/pacman/local: glob không được nổ và không được in gói ma.
AUR_MISSING_PACKAGES=()
run_report "$WORK/khong-co" calamares
[[ "$REPORT_RC" -eq 1 ]] || fail "thiếu pacman DB phải trả về 1"
[[ -s "$REPORT_FILE" ]] && fail "thiếu pacman DB thì không được in gói nào: $(cat "$REPORT_FILE")"
pass "thiếu pacman DB: báo thiếu đủ 4 gói, không chết vì glob"

# --- 7. Tên gói có dấu '.' phải khớp theo nghĩa đen -------------------------
dot="$WORK/dot"
make_db "$dot" "calamaresx-1.0-1" "calamares-3.4.2-2" "yay-13.0.1-1" \
  "coccoc-browser-stable-152.0.7977.124-1" "legacy-launcher-latest-1"
AUR_MISSING_PACKAGES=()
run_report "$dot" "${AUR_PKGNAMES[@]}"
[[ "$REPORT_RC" -eq 0 ]] || fail "tên 'calamares' khớp nhầm 'calamaresx'"
grep -qxF "AUR package baked into the image: calamares 3.4.2-2" "$REPORT_FILE" ||
  fail "tên 'calamares' bị tách sai: $(cat "$REPORT_FILE")"
[[ -z "${AUR_MISSING_PACKAGES[*]:-}" ]] ||
  fail "calamares bị báo thiếu oan: ${AUR_MISSING_PACKAGES[*]:-}"
pass "dấu '.' trong tên gói được coi là ký tự thường"

# --- 8. Không còn gọi pacman --sysroot -------------------------------------
# --sysroot là nguyên nhân của hàng loạt cảnh báo sync DB; nếu ai đó đưa nó
# trở lại thì bài này đỏ.
# Chỉ xem dòng lệnh thật: comment nhắc đến --sysroot là hợp lệ.
if grep -vE '^[[:space:]]*#' "$BUILD_ISO" |
  grep -nE 'pacman[[:space:]]+-[A-Za-z]*Q[^|]*--sysroot'; then
  fail "build-iso.sh again queries packages with pacman --sysroot (prints sync-database warnings)"
fi
pass "build-iso.sh không còn dùng pacman --sysroot để đối chiếu gói AUR"

echo "OK: kiểm tra gói AUR trong airootfs chạy được trên cây giả, không cần pacman/Arch"
