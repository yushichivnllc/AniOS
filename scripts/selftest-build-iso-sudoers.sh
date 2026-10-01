#!/usr/bin/env bash
# Tự kiểm tra bước "không có luật sudo NOPASSWD nào lọt vào ảnh" ở cuối
# scripts/build-iso.sh mà không cần dựng ISO, không cần Arch, không cần root.
#
# Vì sao có bài này: bước đó từng là `grep -R NOPASSWD etc/sudoers.d etc/sudoers`.
# Gói `sudo` của Arch ship /etc/sudoers kèm sẵn ví dụ đã comment
#
#     ## Same thing without a password
#     # %wheel ALL=(ALL:ALL) NOPASSWD: ALL
#
# nên grep thô luôn khớp: bản dựng chạy ~25 phút, mkarchiso báo "Done!", cả ba gói
# AUR đã nằm trong ảnh, rồi script vẫn chết với "A NOPASSWD sudo rule leaked into
# the image" trên một ảnh hoàn toàn sạch. Lỗi chỉ lộ ra ở cuối lượt dựng dài nên
# phải có bài kiểm tra ngoại tuyến bắt nó trong vài giây.
#
# Bài này nạp ĐÚNG hàm sudoers_nopasswd_rules() từ scripts/build-iso.sh (không chép
# lại logic, nên sửa hàm là bài này thấy ngay) rồi chạy nó trên các cây airootfs giả:
#
#   1. ảnh sạch: /etc/sudoers mặc định của gói sudo + etc/sudoers.d/10-anios-live
#      thật của repo           -> KHÔNG báo gì (đúng kịch bản làm hỏng CI)
#   2. luật NOPASSWD thật trong etc/sudoers.d/   -> báo đúng file:dòng
#   3. luật NOPASSWD ghi thêm vào /etc/sudoers    -> chỉ báo luật, không báo comment
#   4. bỏ comment dòng ví dụ của /etc/sudoers     -> vẫn bị bắt (cách rò rỉ phổ biến
#      nhất: `sed -i 's/^# \(%wheel .* NOPASSWD: ALL\)/\1/' /etc/sudoers`)
#   5. cú pháp biên: comment thụt đầu dòng, `#1000` (uid, là luật thật), dòng nối
#      bằng `\`, comment cuối dòng, tên file có dấu cách, drop-in chỉ có comment
#   6. thiếu etc/sudoers hoặc etc/sudoers.d       -> không báo gì và không chết
#   7. fail closed: file sudoers đọc không được   -> hàm trả exit khác 0, không bao giờ
#      coi là "sạch" (kể cả khi file đọc được nằm SAU nó)
#
# Chạy: ./scripts/selftest-build-iso-sudoers.sh
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ISO="$ROOT_DIR/scripts/build-iso.sh"
LIVE_SUDOERS="$ROOT_DIR/profile/airootfs/etc/sudoers.d/10-anios-live"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

[[ -f "$BUILD_ISO" ]] || fail "thiếu $BUILD_ISO"
[[ -s "$LIVE_SUDOERS" ]] || fail "thiếu chính sách sudo của tài khoản live: $LIVE_SUDOERS"

# --- Nạp hàm từ build-iso.sh ----------------------------------------------
# build-iso.sh chạy ngay khi nạp (cần root, archiso...) nên không `source` được;
# lấy riêng thân hàm: từ dòng khai báo tới dấu `}` đầu tiên ở đầu dòng.
fn_src="$(awk '/^sudoers_nopasswd_rules\(\) \{$/ { p = 1 } p { print } p && /^\}$/ { exit }' "$BUILD_ISO")"
[[ -n "$fn_src" ]] ||
  fail "scripts/build-iso.sh không còn hàm sudoers_nopasswd_rules() (khai báo ở đầu dòng)"
[[ "$(tail -n1 <<<"$fn_src")" == '}' ]] ||
  fail "không tìm thấy dấu '}' đóng hàm sudoers_nopasswd_rules() ở đầu dòng"
(( $(wc -l <<<"$fn_src") <= 40 )) ||
  fail "hàm sudoers_nopasswd_rules() dài bất thường: có thể dấu '}' đóng hàm không nằm ở đầu dòng"
eval "$fn_src"

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/anios-sudoers-selftest.XXXXXX")"
cleanup() {
  if [[ -n "${ANIOS_SELFTEST_KEEP_SANDBOX:-}" ]]; then
    echo "Sandbox giữ lại tại: $SANDBOX" >&2
    return 0
  fi
  rm -rf -- "$SANDBOX"
}
trap cleanup EXIT

# /etc/sudoers do gói `sudo` của Arch cài (sudo 1.9.17p2; PKGBUILD chỉ chạy
# `make install` rồi xoá sudoers.dist, không sửa file này). Rút gọn từ
# plugins/sudoers/sudoers.in của upstream, GIỮ NGUYÊN các dòng ví dụ đã comment.
write_stock_sudoers() {
  cat >"$1" <<'SUDOERS'
## sudoers file.
##
## This file MUST be edited with the 'visudo' command as root.
## Failure to use 'visudo' may result in syntax or file permission errors
## that prevent sudo from running.
##
## See the sudoers man page for the details on how to write a sudoers file.
##

##
## Host alias specification
##
# Host_Alias	WEBSERVERS = www1, www2, www3

##
## Cmnd alias specification
##
# Cmnd_Alias	PROCESSES = /usr/bin/nice, /bin/kill, /usr/bin/renice, \
# 			    /usr/bin/pkill, /usr/bin/top

##
## Defaults specification
##
Defaults!/usr/bin/visudo env_keep += "SUDO_EDITOR EDITOR VISUAL"
Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/bin"
##
## Uncomment to disable "use_pty" when running commands as root.
# Defaults>root !use_pty

##
## User privilege specification
##
root ALL=(ALL:ALL) ALL

## Uncomment to allow members of group wheel to execute any command
# %wheel ALL=(ALL:ALL) ALL

## Same thing without a password
# %wheel ALL=(ALL:ALL) NOPASSWD: ALL

## Uncomment to allow members of group sudo to execute any command
# %sudo ALL=(ALL:ALL) ALL

## Uncomment to allow any user to run sudo if they know the password
## of the user they are running the command as (root by default).
# Defaults targetpw  # Ask for the password of the target user
# ALL ALL=(ALL:ALL) ALL  # WARNING: only use this together with 'Defaults targetpw'

## Read drop-in files from /etc/sudoers.d
@includedir /etc/sudoers.d
SUDOERS
}

# airootfs giả như sau pacstrap + bước dựng AUR: sudoers mặc định của gói sudo và
# chính sách sudo thật của tài khoản live lấy thẳng từ repo.
new_image() {
  local root="$SANDBOX/$1"
  mkdir -p -- "$root/etc/sudoers.d"
  write_stock_sudoers "$root/etc/sudoers"
  cp -- "$LIVE_SUDOERS" "$root/etc/sudoers.d/10-anios-live"
  printf '%s' "$root"
}

# Chạy hàm; tự thất bại nếu hàm trả exit khác 0 (script thật chạy dưới set -e).
scan() {
  local root="$1" out
  out="$(sudoers_nopasswd_rules "$root")" ||
    fail "sudoers_nopasswd_rules trả exit khác 0 trên $root"
  printf '%s' "$out"
}

expect_clean() {
  local label="$1" root="$2" out
  out="$(scan "$root")"
  [[ -z "$out" ]] || { printf '%s\n' "$out" >&2; fail "$label: báo rò rỉ NOPASSWD trên ảnh sạch"; }
}

# $3.. : các dòng báo cáo phải xuất hiện đúng nguyên văn; ngoài ra không được có dòng nào khác.
expect_exactly() {
  local label="$1" root="$2" out expected
  shift 2
  out="$(scan "$root")"
  expected="$(printf '%s\n' "$@")"
  [[ "$out" == "$expected" ]] || {
    printf -- '--- mong đợi:\n%s\n--- thực tế:\n%s\n' "$expected" "$out" >&2
    fail "$label: báo cáo không khớp"
  }
}

# --- 1. Ảnh sạch ----------------------------------------------------------
IMG="$(new_image img-clean)"
# Đối chứng âm: chứng minh fixture THỰC SỰ tái hiện lỗi cũ. Nếu ai đó rút dòng
# ví dụ khỏi fixture thì bài này không còn bảo vệ được gì, nên phải báo ngay.
grep -Rqs 'NOPASSWD' "$IMG/etc/sudoers.d/" "$IMG/etc/sudoers" ||
  fail "fixture sudoers mặc định không còn chứa chữ NOPASSWD: bài này không còn tái hiện lỗi cũ"
grep -qE '^[[:space:]]*#.*NOPASSWD' "$IMG/etc/sudoers" ||
  fail "fixture phải có dòng ví dụ ĐÃ COMMENT chứa NOPASSWD"
if grep -vE '^[[:space:]]*#' "$IMG/etc/sudoers" "$IMG/etc/sudoers.d/10-anios-live" | grep -q 'NOPASSWD'; then
  fail "fixture sạch lại có luật NOPASSWD đang hiệu lực"
fi
# Kiểm tra thật: grep thô cũ sẽ khớp (lỗi), hàm mới thì im lặng (đúng). Đặt đúng
# quyền 0440 của file sudoers thật (build-iso.sh khai báo 0:0:440) để chắc hàm đọc
# được file chỉ-đọc; các ca bên dưới cần ghi thêm vào file nên dùng file ghi được.
chmod 0440 -- "$IMG/etc/sudoers" "$IMG/etc/sudoers.d/10-anios-live"
expect_clean "ảnh sạch (sudoers mặc định + 10-anios-live)" "$IMG"
pass "ảnh sạch: dòng ví dụ '# %wheel ... NOPASSWD: ALL' của gói sudo không bị coi là rò rỉ"

# --- 2. Luật NOPASSWD thật trong etc/sudoers.d ----------------------------
IMG2="$(new_image img-dropin)"
printf 'aniosbuild ALL=(ALL) NOPASSWD: ALL\n' >"$IMG2/etc/sudoers.d/20-anios-aur-build"
expect_exactly "drop-in rò rỉ" "$IMG2" \
  'etc/sudoers.d/20-anios-aur-build:1: aniosbuild ALL=(ALL) NOPASSWD: ALL'
pass "luật NOPASSWD trong etc/sudoers.d bị phát hiện kèm file:dòng"

# --- 3. Luật NOPASSWD ghi thêm vào /etc/sudoers ----------------------------
# Cách rò rỉ kinh điển của script dựng gói: echo '...' >> /etc/sudoers.
IMG3="$(new_image img-appended)"
printf 'aniosbuild ALL=(ALL) NOPASSWD: ALL\n' >>"$IMG3/etc/sudoers"
line="$(grep -n '^aniosbuild ALL=(ALL) NOPASSWD: ALL$' "$IMG3/etc/sudoers" | cut -d: -f1)"
[[ -n "$line" ]] || fail "fixture: không tìm thấy dòng vừa ghi thêm"
expect_exactly "luật ghi thêm vào /etc/sudoers" "$IMG3" \
  "etc/sudoers:$line: aniosbuild ALL=(ALL) NOPASSWD: ALL"
pass "luật NOPASSWD ghi thêm vào /etc/sudoers bị bắt, dòng ví dụ đã comment bên trên thì không"

# --- 4. Bỏ comment dòng ví dụ của /etc/sudoers -----------------------------
IMG4="$(new_image img-uncommented)"
sed -i 's/^# \(%wheel ALL=(ALL:ALL) NOPASSWD: ALL\)$/\1/' "$IMG4/etc/sudoers"
line="$(grep -n '^%wheel ALL=(ALL:ALL) NOPASSWD: ALL$' "$IMG4/etc/sudoers" | cut -d: -f1)"
[[ -n "$line" ]] || fail "fixture: sed không bỏ được comment dòng ví dụ"
expect_exactly "bỏ comment dòng ví dụ" "$IMG4" \
  "etc/sudoers:$line: %wheel ALL=(ALL:ALL) NOPASSWD: ALL"
pass "bỏ comment dòng ví dụ '%wheel ... NOPASSWD' trong /etc/sudoers vẫn bị phát hiện"

# --- 5. Cú pháp biên -------------------------------------------------------
# 5a. Chỉ có comment (kể cả thụt đầu dòng, bằng tab, không dấu cách sau '#'): sạch.
IMG5="$(new_image img-comments)"
printf '%s\n' \
  '   # %wheel ALL=(ALL) NOPASSWD: ALL' \
  $'\t#NOPASSWD: ALL, không có dấu cách sau dấu #' \
  '#' \
  '## NOPASSWD ở đây chỉ là chữ trong chú thích' \
  >"$IMG5/etc/sudoers.d/99-notes"
expect_clean "drop-in chỉ có comment" "$IMG5"
pass "drop-in chỉ có comment nhắc tới NOPASSWD (thụt đầu dòng, tab, không dấu cách) không bị báo"

# 5b. '#<chữ số>' là uid trong sudoers(5), không phải comment: đây là luật thật.
IMG5B="$(new_image img-uid)"
printf '#1000 ALL=(ALL) NOPASSWD: ALL\n' >"$IMG5B/etc/sudoers.d/30-uid"
expect_exactly "luật theo uid" "$IMG5B" 'etc/sudoers.d/30-uid:1: #1000 ALL=(ALL) NOPASSWD: ALL'
pass "'#1000 ... NOPASSWD' (uid) được coi là luật thật chứ không phải comment"

# 5c. Luật nối dòng bằng '\': tag NOPASSWD nằm ở dòng sau, vẫn phải bị bắt.
IMG5C="$(new_image img-continued)"
printf 'aniosbuild ALL=(ALL) \\\n    NOPASSWD: ALL\n' >"$IMG5C/etc/sudoers.d/40-continued"
expect_exactly "luật nối dòng" "$IMG5C" 'etc/sudoers.d/40-continued:2:     NOPASSWD: ALL'
pass "luật NOPASSWD bị ngắt qua dòng nối '\\' vẫn bị phát hiện"

# 5d. Luật thật có comment cuối dòng vẫn là luật thật.
IMG5D="$(new_image img-trailing)"
printf 'aniosbuild ALL=(ALL) NOPASSWD: ALL # tạm thời\n' >"$IMG5D/etc/sudoers.d/50-trailing"
expect_exactly "comment cuối dòng" "$IMG5D" \
  'etc/sudoers.d/50-trailing:1: aniosbuild ALL=(ALL) NOPASSWD: ALL # tạm thời'
pass "comment cuối dòng không che được một luật NOPASSWD thật"

# 5e. Tên file có dấu cách không bị tách từ; đường dẫn truyền vào có '/' cuối vẫn ra nhãn gọn.
IMG5E="$(new_image img-space)"
printf 'aniosbuild ALL=(ALL) NOPASSWD: ALL\n' >"$IMG5E/etc/sudoers.d/60 co dau cach"
out="$(scan "$IMG5E/")"
[[ "$out" == 'etc/sudoers.d/60 co dau cach:1: aniosbuild ALL=(ALL) NOPASSWD: ALL' ]] || {
  printf '%s\n' "$out" >&2
  fail "tên file có dấu cách (hoặc đường dẫn có '/' cuối) bị xử lý sai"
}
pass "tên file có dấu cách và đường dẫn airootfs có '/' cuối được xử lý đúng"

# 5f. Nhiều luật ở nhiều file: báo đủ, theo thứ tự etc/sudoers rồi etc/sudoers.d/*.
IMG5F="$(new_image img-many)"
printf 'aniosbuild ALL=(ALL) NOPASSWD: ALL\n' >>"$IMG5F/etc/sudoers"
printf 'foo ALL=(ALL) NOPASSWD: /usr/bin/pacman\n' >"$IMG5F/etc/sudoers.d/20-foo"
printf 'bar ALL=(ALL) NOPASSWD: ALL\n' >"$IMG5F/etc/sudoers.d/30-bar"
line="$(grep -n '^aniosbuild ' "$IMG5F/etc/sudoers" | cut -d: -f1)"
expect_exactly "nhiều luật rò rỉ" "$IMG5F" \
  "etc/sudoers:$line: aniosbuild ALL=(ALL) NOPASSWD: ALL" \
  'etc/sudoers.d/20-foo:1: foo ALL=(ALL) NOPASSWD: /usr/bin/pacman' \
  'etc/sudoers.d/30-bar:1: bar ALL=(ALL) NOPASSWD: ALL'
pass "nhiều luật NOPASSWD ở nhiều file đều được liệt kê, kể cả luật chỉ cho một lệnh"

# --- 6. Thiếu file / thư mục ------------------------------------------------
# Ảnh không cài sudo (ví dụ --no-aur trên một profile tối giản) không được làm
# bước kiểm tra chết dưới `set -e`.
mkdir -p -- "$SANDBOX/img-bare/etc"
expect_clean "không có sudoers lẫn sudoers.d" "$SANDBOX/img-bare"
mkdir -p -- "$SANDBOX/img-emptyd/etc/sudoers.d"
expect_clean "sudoers.d rỗng, không có etc/sudoers" "$SANDBOX/img-emptyd"
mkdir -p -- "$SANDBOX/img-onlymain/etc"
write_stock_sudoers "$SANDBOX/img-onlymain/etc/sudoers"
expect_clean "chỉ có etc/sudoers mặc định" "$SANDBOX/img-onlymain"
expect_clean "airootfs không tồn tại" "$SANDBOX/img-does-not-exist"
pass "thiếu etc/sudoers hoặc etc/sudoers.d không làm bước kiểm tra chết hay báo nhầm"

# --- 7. Fail closed: file không đọc được ------------------------------------
# Bộ phát hiện rò rỉ mà gặp file không đọc được thì KHÔNG được im lặng coi là sạch.
# Cho file hỏng đứng TRƯỚC một file đọc được: nếu hàm chỉ trả status của lần awk
# cuối cùng thì lỗi này bị nuốt mất.
if (( EUID == 0 )); then
  # root đọc được mọi file nên `chmod 000` không tạo được tình huống này.
  echo "SKIP: đang chạy bằng root, bỏ qua ca file sudoers không đọc được"
else
  IMG7="$(new_image img-unreadable)"
  printf 'aniosbuild ALL=(ALL) NOPASSWD: ALL\n' >"$IMG7/etc/sudoers.d/20-unreadable"
  printf 'bar ALL=(ALL) PASSWD: ALL\n' >"$IMG7/etc/sudoers.d/30-readable"
  chmod 000 -- "$IMG7/etc/sudoers.d/20-unreadable"
  status=0
  sudoers_nopasswd_rules "$IMG7" >/dev/null 2>&1 || status=$?
  chmod 600 -- "$IMG7/etc/sudoers.d/20-unreadable"
  (( status != 0 )) ||
    fail "file sudoers đọc không được mà hàm vẫn trả exit 0, tức coi như ảnh sạch"
  pass "file sudoers không đọc được -> hàm trả exit khác 0 (fail closed), không coi là ảnh sạch"
fi

echo "AniOS build-iso sudoers leak-check self-test passed"
