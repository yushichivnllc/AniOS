#!/usr/bin/env bash
# Tự kiểm tra profile/airootfs/usr/local/bin/anios-steam-setup — bộ cài Proton /
# Steam Runtime OFFLINE từ cache nướng sẵn trong ảnh — mà không cần dựng ISO,
# không cần Arch, không cần mạng.
#
# Vì sao có bài này: anios-steam-setup chạy ở lần mở Steam đầu tiên của người dùng.
# Nếu nó hỏng thì biểu hiện là Steam mở lên mà không có Proton, hoặc tệ hơn là
# Steam không mở được — cả hai đều chỉ lộ ra trên máy thật sau khi đã ghi USB.
# Bài này chạy ĐÚNG script đó (không chép lại logic) trên một cache giả có
# tarball thật, nên lỗi giải nén, lỗi đánh dấu, lỗi đường dẫn đều bị bắt trong
# vài giây.
#
# Các kịch bản:
#   1. cache có Proton       -> giải nén vào compatibilitytools.d/<tên>/, có stamp
#   2. chạy lại lần hai      -> bỏ qua (không giải nén lại), vẫn exit 0
#   3. manifest đổi          -> nhận ra và cài lại bản mới
#   4. không có cache        -> exit 0, không tạo gì (ảnh dựng với provision=off)
#   5. manifest trỏ file thiếu -> cảnh báo rồi bỏ qua, KHÔNG chết
#   6. tarball hỏng          -> dọn phần dở, exit 0; với --strict thì exit 1
#   7. steam-runtime         -> giải nén vào ubuntu12_32/, không phải compatibilitytools.d
#   8. script phải OFFLINE   -> không được gọi curl/wget
#
# Chạy: ./scripts/selftest-anios-steam-setup.sh
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP="$ROOT_DIR/profile/airootfs/usr/local/bin/anios-steam-setup"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

[[ -x "$SETUP" ]] || fail "thiếu hoặc không thực thi được: $SETUP"
bash -n "$SETUP" || fail "anios-steam-setup có lỗi cú pháp"

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/anios-steam-setup-selftest.XXXXXX")"
cleanup() {
  if [[ -n "${ANIOS_SELFTEST_KEEP_SANDBOX:-}" ]]; then
    echo "Sandbox giữ lại tại: $SANDBOX" >&2
    return 0
  fi
  rm -rf -- "$SANDBOX"
}
trap cleanup EXIT

# --- Cache giả: một "Proton" thật (tarball bọc thư mục <tên>/ như upstream) ----
make_proton_tarball() {
  local stage="$1" out="$2" name="$3"
  install -d -m 0755 -- "$stage/$name"
  cat >"$stage/$name/proton" <<'PROTON'
#!/usr/bin/env bash
echo "fake proton $name"
PROTON
  chmod +x -- "$stage/$name/proton"
  printf 'compatibilitytool.vdf stub\n' >"$stage/$name/compatibilitytool.vdf"
  tar -czf "$out" -C "$stage" "$name"
}

CACHE="$SANDBOX/cache"
install -d -m 0755 -- "$CACHE/proton" "$CACHE/runtime"
proton_stage="$SANDBOX/proton-src"
make_proton_tarball "$proton_stage" "$CACHE/proton/proton-9.0-1.tar.gz" proton-9.0-1
printf 'proton|proton-9.0-1|proton/proton-9.0-1.tar.gz\n' >"$CACHE/manifest"

# Một "Steam Runtime" giả: tarball .tar.xz chứa steam-runtime/.
# Snapshot runtime của Valve bọc đúng MỘT thư mục steam-runtime/ ở cấp ngoài cùng;
# anios-steam-setup strip đúng một cấp đó rồi đặt vào ubuntu12_32/steam-runtime/.
rt_stage="$SANDBOX/rt-src"
install -d -m 0755 -- "$rt_stage/steam-runtime/usr/lib"
printf 'stub\n' >"$rt_stage/steam-runtime/VERSIONS.txt"
tar -cJf "$CACHE/runtime/steam-runtime.tar.xz" -C "$rt_stage" steam-runtime

run_setup() {
  local steam_root="$1"; shift
  ANIOS_STEAM_CACHE="$CACHE" STEAM_ROOT="$steam_root" HOME="$SANDBOX/home" \
    "$SETUP" "$@"
}

# --- 1. Giải nén Proton lần đầu ---------------------------------------------
ROOT1="$SANDBOX/steam1"
run_setup "$ROOT1" >/dev/null || fail "anios-steam-setup thất bại ở lần chạy đầu"
[[ -x "$ROOT1/compatibilitytools.d/proton-9.0-1/proton" ]] ||
  fail "Proton không được giải nén vào compatibilitytools.d/proton-9.0-1/"
[[ -s "$ROOT1/compatibilitytools.d/proton-9.0-1/compatibilitytool.vdf" ]] ||
  fail "compatibilitytool.vdf thiếu: --strip-components=1 có thể đã cắt sai cấp thư mục"
[[ -s "$ROOT1/.anios-provisioned" ]] || fail "không ghi file đánh dấu .anios-provisioned"
pass "Proton được giải nén offline vào compatibilitytools.d (bọc đúng một cấp thư mục)"

# --- 7. Steam Runtime vào ubuntu12_32 ---------------------------------------
printf 'steam-runtime|steam-runtime|runtime/steam-runtime.tar.xz\n' >>"$CACHE/manifest"
run_setup "$ROOT1" >/dev/null || fail "anios-steam-setup thất bại khi thêm steam-runtime"
[[ -s "$ROOT1/ubuntu12_32/steam-runtime/VERSIONS.txt" ]] ||
  fail "Steam Runtime không nằm trong ubuntu12_32/steam-runtime/"
[[ ! -e "$ROOT1/compatibilitytools.d/steam-runtime" ]] ||
  fail "steam-runtime bị giải nén nhầm vào compatibilitytools.d"
pass "Steam Runtime vào ubuntu12_32/, Proton vào compatibilitytools.d/"

# --- 2. Chạy lại: bỏ qua -----------------------------------------------------
before="$(find "$ROOT1" -newermt '-1 second' -type f 2>/dev/null | wc -l)"
out2="$(run_setup "$ROOT1" 2>&1)" || fail "lần chạy thứ hai phải exit 0"
grep -qF 'đã cài rồi' <<<"$out2" || fail "lần chạy thứ hai không bỏ qua: $out2"
pass "lần mở Steam thứ hai trở đi không giải nén lại (nhờ file đánh dấu)"

# --- 3. Manifest đổi -> cài lại ---------------------------------------------
make_proton_tarball "$SANDBOX/proton-src-2" "$CACHE/proton/proton-9.1-0.tar.gz" proton-9.1-0
printf 'proton|proton-9.0-1|proton/proton-9.0-1.tar.gz\nproton|proton-9.1-0|proton/proton-9.1-0.tar.gz\nsteam-runtime|steam-runtime|runtime/steam-runtime.tar.xz\n' \
  >"$CACHE/manifest"
run_setup "$ROOT1" >/dev/null || fail "anios-steam-setup thất bại khi manifest đổi"
[[ -x "$ROOT1/compatibilitytools.d/proton-9.1-0/proton" ]] ||
  fail "bản Proton mới không được cài sau khi manifest đổi"
pass "manifest đổi (ISO mới) thì bản Proton mới được cài thêm"

# --- 4. Không có cache -------------------------------------------------------
ROOT2="$SANDBOX/steam2"
out4="$(ANIOS_STEAM_CACHE="$SANDBOX/nope" STEAM_ROOT="$ROOT2" HOME="$SANDBOX/home" \
  "$SETUP" 2>&1)" || fail "thiếu cache phải exit 0 chứ không được chặn Steam"
grep -qF 'không có' <<<"$out4" || fail "thiếu cache không được báo rõ: $out4"
[[ ! -d "$ROOT2/compatibilitytools.d" ]] || fail "không có cache thì không được tạo gì"
pass "ảnh không nướng runtime (provision=off) vẫn mở được Steam"

# --- 5. Manifest trỏ tới file không tồn tại ----------------------------------
CACHE_BAD="$SANDBOX/cache-bad"
install -d -m 0755 -- "$CACHE_BAD/proton"
printf 'proton|ghost|proton/ghost.tar.gz\n' >"$CACHE_BAD/manifest"
ROOT3="$SANDBOX/steam3"
out5="$(ANIOS_STEAM_CACHE="$CACHE_BAD" STEAM_ROOT="$ROOT3" HOME="$SANDBOX/home" \
  "$SETUP" 2>&1)" || fail "manifest thiếu file phải cảnh báo rồi exit 0"
grep -qF 'ghost' <<<"$out5" || fail "không nêu tên mục hỏng: $out5"
pass "manifest trỏ file thiếu chỉ cảnh báo, không làm hỏng việc mở Steam"

# --- 6. Tarball hỏng ---------------------------------------------------------
CACHE_BRK="$SANDBOX/cache-brk"
install -d -m 0755 -- "$CACHE_BRK/proton"
printf 'day khong phai tarball\n' >"$CACHE_BRK/proton/broken.tar.gz"
printf 'proton|broken|proton/broken.tar.gz\n' >"$CACHE_BRK/manifest"
ROOT4="$SANDBOX/steam4"
out6="$(ANIOS_STEAM_CACHE="$CACHE_BRK" STEAM_ROOT="$ROOT4" HOME="$SANDBOX/home" \
  "$SETUP" 2>&1)" || fail "tarball hỏng phải exit 0 ở chế độ thường"
# Guard "bọc đúng một thư mục cấp ngoài" bắt tarball hỏng TRƯỚC khi giải nén,
# nên thông báo là về số mục chứ không phải lỗi tar; điều phải đúng là nó nêu tên
# gói và từ chối cài.
{ grep -qF 'bỏ qua broken' <<<"$out6" || grep -qF 'thất bại' <<<"$out6"; } ||
  fail "tarball hỏng không được nêu tên và từ chối: $out6"
[[ ! -d "$ROOT4/compatibilitytools.d/broken" ]] ||
  fail "phần giải nén dở của tarball hỏng không được dọn"
status=0
ANIOS_STEAM_CACHE="$CACHE_BRK" STEAM_ROOT="$SANDBOX/steam5" HOME="$SANDBOX/home" \
  "$SETUP" --strict >/dev/null 2>&1 || status=$?
(( status != 0 )) || fail "--strict phải trả exit khác 0 khi tarball hỏng"
pass "tarball hỏng: dọn phần dở, exit 0 (và exit khác 0 với --strict cho CI)"

# --- 8. Phải offline ---------------------------------------------------------
if grep -nE '\b(curl|wget|pacman|yay)\b' "$SETUP" >/dev/null; then
  fail "anios-steam-setup gọi công cụ tải gói; việc tải thuộc về anios-steam-provision.sh"
fi
pass "anios-steam-setup hoàn toàn offline (không curl/wget/pacman)"

# --- HOME rỗng không được làm chết phiên ------------------------------------
status=0
env -u HOME ANIOS_STEAM_CACHE="$CACHE" STEAM_ROOT="" "$SETUP" >/dev/null 2>&1 || status=$?
(( status == 0 )) || fail "thiếu HOME phải exit 0 (Steam vẫn mở được bằng runtime trực tuyến)"
pass "thiếu HOME vẫn exit 0"

echo "All anios-steam-setup self-tests passed."
