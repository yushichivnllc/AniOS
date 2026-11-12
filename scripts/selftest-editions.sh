#!/usr/bin/env bash
# Tự kiểm tra hệ thống ba bản edition (anios / aniterals / anix) mà không cần
# dựng ISO, không cần Arch, không cần root.
#
# Vì sao có bài này: ba bản ISO dùng chung một profile nền và khác nhau ở manifest
# gói. Lỗi dễ gặp nhất là bản amnesic vẫn mang Steam (ảnh phình vô ích, đúng thứ
# bản đó muốn bỏ) hoặc bản "đầy đủ nhất" lại thiếu tầng Proton — cả hai đều chỉ lộ
# ra sau một lượt dựng hàng chục phút và một lần ghi USB.
#
# Bài này nạp ĐÚNG hàm anios_apply_edition_packages() từ scripts/build-iso.sh (không
# chép lại logic, nên sửa hàm là bài này thấy ngay) rồi chạy nó trên manifest thật
# của repo cho từng bản, và kiểm tra luôn đường phân giải --edition của CLI.
#
# Chạy: ./scripts/selftest-editions.sh
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ISO="$ROOT_DIR/scripts/build-iso.sh"
EDITIONS_DIR="$ROOT_DIR/profile/editions"
BASE_MANIFEST="$ROOT_DIR/profile/packages.x86_64"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

[[ -s "$BUILD_ISO" ]] || fail "thiếu $BUILD_ISO"
[[ -s "$BASE_MANIFEST" ]] || fail "thiếu manifest nền: $BASE_MANIFEST"
[[ -d "$EDITIONS_DIR" ]] || fail "thiếu $EDITIONS_DIR"

# --- Nạp hàm từ build-iso.sh ------------------------------------------------
# build-iso.sh chạy ngay khi nạp (cần root, archiso...) nên không `source` được;
# lấy riêng thân hàm, từ dòng khai báo ở đầu dòng tới dấu `}` đầu tiên ở đầu dòng.
fn_src="$(awk '/^anios_apply_edition_packages\(\) \{$/ { p = 1 } p { print } p && /^\}$/ { exit }' "$BUILD_ISO")"
[[ -n "$fn_src" ]] ||
  fail "scripts/build-iso.sh không còn hàm anios_apply_edition_packages() (khai báo ở đầu dòng)"
[[ "$(tail -n1 <<<"$fn_src")" == '}' ]] ||
  fail "không tìm thấy dấu '}' đóng hàm anios_apply_edition_packages() ở đầu dòng"
eval "$fn_src"
pass "nạp được đúng hàm anios_apply_edition_packages() từ scripts/build-iso.sh"

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/anios-editions-selftest.XXXXXX")"
cleanup() {
  if [[ -n "${ANIOS_SELFTEST_KEEP_SANDBOX:-}" ]]; then
    echo "Sandbox giữ lại tại: $SANDBOX" >&2
    return 0
  fi
  rm -rf -- "$SANDBOX"
}
trap cleanup EXIT

# Manifest cuối cùng của một edition, dựng bằng ĐÚNG hàm mà build-iso.sh gọi.
edition_manifest() {
  # Hai lệnh `local` riêng: gộp vào một lệnh (`local a="$1" b="...$a..."`) thì
  # bash khai báo cả hai biến TRƯỚC khi gán, nên tham chiếu $edition_id trong cùng
  # câu lệnh bị `set -u` coi là biến chưa tồn tại.
  local edition_id="$1"
  local out="$SANDBOX/$edition_id.packages"
  cp -- "$BASE_MANIFEST" "$out"
  ANIOS_EDITION_ID="$edition_id" anios_apply_edition_packages "$out" "$EDITIONS_DIR/$edition_id" >/dev/null
  printf '%s\n' "$out"
}

# --- 1. Ba bản tồn tại và phân giải được -----------------------------------
found_editions="$(cd "$EDITIONS_DIR" && for d in */; do [[ -s "$d/edition.conf" ]] && printf '%s\n' "${d%/}"; done | sort | tr '\n' ' ')"
[[ "$found_editions" == "anios aniterals anix " ]] ||
  fail "profile/editions phải có đúng ba bản anios aniterals anix, thực tế: $found_editions"
pass "có đúng ba bản edition: anios, aniterals, anix"

# --- 2. Manifest của từng bản ----------------------------------------------
ANIOS_MANIFEST="$(edition_manifest anios)"
ANITALS_MANIFEST="$(edition_manifest aniterals)"
ANIX_MANIFEST="$(edition_manifest anix)"

grep -qxF 'steam' "$ANIOS_MANIFEST" || fail "bản anios phải có gói steam"
grep -qxF 'steam' "$ANIX_MANIFEST" || fail "bản anix phải có gói steam"
! grep -qxF 'steam' "$ANITALS_MANIFEST" || fail "bản amnesic aniterals KHÔNG được mang gói steam"
pass "steam có trong anios/anix và bị cắt khỏi aniterals"

grep -qxF 'protontricks' "$ANIX_MANIFEST" ||
  fail "bản anix (đầy đủ nhất) phải thêm protontricks"
! grep -qxF 'protontricks' "$ANIOS_MANIFEST" ||
  fail "protontricks là gói riêng của anix, không được lọt vào bản anios"
pass "tầng Proton/runtime riêng của anix không lọt sang bản khác"

grep -qxF 'tor' "$ANITALS_MANIFEST" || fail "bản aniterals phải cài tor"
grep -qxF 'macchanger' "$ANITALS_MANIFEST" || fail "bản aniterals phải cài macchanger"
! grep -qxF 'ollama-vulkan' "$ANITALS_MANIFEST" || fail "bản aniterals phải cắt stack AI (ollama-vulkan)"
! grep -qxF 'wine' "$ANITALS_MANIFEST" || fail "bản aniterals phải cắt wine"
pass "aniterals có Tor/anti-forensic và đã cắt game + AI"

# Phần dùng chung của ba bản không được mất đi khi cắt gói.
for shared in linux-zen hyprland sddm pipewire networkmanager firefox; do
  for m in "$ANIOS_MANIFEST" "$ANITALS_MANIFEST" "$ANIX_MANIFEST"; do
    grep -qxF "$shared" "$m" || fail "gói dùng chung $shared bị mất trong $(basename "$m")"
  done
done
pass "phần nền (kernel, Hyprland, SDDM, PipeWire, mạng, trình duyệt) còn nguyên ở cả ba bản"

# --- 3. Khử trùng lặp và không còn dòng rỗng --------------------------------
# Comment ĐƯỢC phép: định dạng manifest của pacman chấp nhận dòng `#`, và chính
# profile/packages.x86_64 (được pacstrap đọc trực tiếp) có hàng chục dòng chú thích.
# scripts/check-profile.sh cũng kiểm manifest bằng regex cho phép `#`. Cái phải bị
# loại là dòng RỖNG và dòng TRÙNG, vì chúng làm khó đọc và gây cài lặp.
for m in "$ANIOS_MANIFEST" "$ANITALS_MANIFEST" "$ANIX_MANIFEST"; do
  dupes="$(sort -- "$m" | uniq -d)"
  [[ -z "$dupes" ]] || fail "$(basename "$m") còn dòng trùng: $dupes"
  if grep -nE '^[[:space:]]*$' "$m" >/dev/null; then
    fail "$(basename "$m") còn dòng rỗng"
  fi
  # Dùng ĐÚNG regex mà scripts/check-profile.sh kiểm manifest: `$` nằm trong nhánh
  # cuối của nhóm, nên dòng `#` (kèm chú thích) vẫn hợp lệ, còn tên gói thì phải
  # trọn dòng.
  if grep -nEv '^[[:space:]]*($|#|[a-zA-Z0-9@._+-]+$)' "$m" >/dev/null; then
    fail "$(basename "$m") có dòng không hợp lệ: $(grep -nEv '^[[:space:]]*($|#|[a-zA-Z0-9@._+-]+$)' "$m" | head -n 3)"
  fi
done
pass "manifest của cả ba bản không còn dòng trùng/dòng rỗng và mọi dòng đều hợp lệ"

# --- 4. CLI phân giải --edition --------------------------------------------
status=0
out="$("$BUILD_ISO" --edition nosuch 2>&1)" || status=$?
(( status == 2 )) || fail "--edition không hợp lệ phải exit 2, thực tế $status"
for edition_id in anios aniterals anix; do
  grep -qxF "  $edition_id" <<<"$out" || fail "--edition sai không liệt kê bản $edition_id: $out"
done
pass "--edition sai thì exit 2 và liệt kê đúng ba bản có sẵn"

status=0
"$BUILD_ISO" --edition >/dev/null 2>&1 || status=$?
(( status == 2 )) || fail "--edition thiếu tham số phải exit 2, thực tế $status"
pass "--edition thiếu tham số bị từ chối"

help_out="$("$BUILD_ISO" --help)"
for edition_id in anios aniterals anix all; do
  grep -qF "$edition_id" <<<"$help_out" || fail "--help không nhắc tới $edition_id"
done
pass "--help liệt kê cả ba bản và --edition all"

# --- 5. --edition all phải tách work dir theo từng bản ----------------------
# mkarchiso tái sử dụng work dir và bỏ qua bước đã chạy, nên ba bản dùng chung một
# work dir là bản sau kế thừa airootfs của bản trước (ISO ra sai mà không báo lỗi).
all_block="$(awk '/if \[\[ "\$EDITION" == all \]\]; then/ { p = 1 } p { print } p && /^fi$/ { exit }' "$BUILD_ISO")"
[[ -n "$all_block" ]] || fail "build-iso.sh không còn nhánh xử lý --edition all"
grep -qF -- '--work "$WORK_DIR-$edition_id"' <<<"$all_block" ||
  fail "--edition all phải tách work dir theo từng bản, nếu không bản sau kế thừa airootfs của bản trước"
grep -qF 'edition.conf' <<<"$all_block" ||
  fail "--edition all phải duyệt theo edition.conf có thật chứ không hardcode tên bản"
# ORIG_ARGS vẫn còn đúng `--edition all`; vòng phân tích đọc tuần tự nên tuỳ chọn
# CUỐI thắng. Truyền thẳng ORIG_ARGS xuống lượt con thì con lại thấy EDITION=all
# và tự gọi chính nó mãi mãi. Bắt buộc phải lọc --edition ra trước.
#
# Chỉ xét LỆNH GỌI ĐỆ QUY (từ dòng `"$0" --edition` tới dòng có `|| exit $?`):
# ORIG_ARGS vẫn được phép xuất hiện ở vòng lọc phía trên, vì đó chính là nguồn
# để lọc.
recursive_call="$(awk '/"\$0" --edition "\$edition_id"/ { p = 1 } p { print } p && /\|\| exit \$\?/ { exit }' <<<"$all_block")"
[[ -n "$recursive_call" ]] || fail "không tìm thấy lệnh gọi đệ quy trong nhánh --edition all"
if grep -qF 'ORIG_ARGS' <<<"$recursive_call"; then
  fail "--edition all truyền thẳng ORIG_ARGS (còn --edition all) cho lượt gọi đệ quy: sẽ tự gọi chính nó mãi mãi"
fi
grep -qF '${forward_args[@]' <<<"$recursive_call" ||
  fail "lệnh gọi đệ quy phải truyền danh sách tham số đã lọc (forward_args)"
grep -qF 'skip_next_arg' <<<"$all_block" ||
  fail "--edition all phải bỏ cả giá trị đi kèm --edition khi lọc tham số truyền xuống"
pass "--edition all tách work dir riêng và không tự đệ quy vô hạn"

# --- 6. file_permissions phải bỏ mục mà edition đã gỡ khỏi ảnh ----------------
# Danh sách ANIOS_FILE_PERMISSIONS là của TOÀN họ AniOS. AniTails gỡ
# anios-persist và anios-steam-quit qua remove.paths, mà verify_file_permissions()
# đòi mọi đường dẫn khai báo phải có thật trong ảnh — nên không lọc là bản amnesic
# chết ở bước đó với "file_permissions declares ... but the image has no such file"
# dù profile hoàn toàn lành. Bài này nạp đúng hàm lọc từ build-iso.sh.
perm_fn="$(awk '/^anios_drop_removed_permissions\(\) \{$/ { p = 1 } p { print } p && /^\}$/ { exit }' "$BUILD_ISO")"
[[ -n "$perm_fn" ]] ||
  fail "scripts/build-iso.sh không còn hàm anios_drop_removed_permissions() (khai báo ở đầu dòng)"
[[ "$(tail -n1 <<<"$perm_fn")" == '}' ]] ||
  fail "không tìm thấy dấu '}' đóng hàm anios_drop_removed_permissions() ở đầu dòng"
eval "$perm_fn"

# remove.paths THẬT của bản aniterals.
mapfile -t anitals_removed < <(
  sed -E -e 's/#.*$//' -e 's/^[[:space:]]+//' -e 's/[[:space:]]+$//' \
    "$EDITIONS_DIR/aniterals/remove.paths" | awk 'NF'
)
(( ${#anitals_removed[@]} )) || fail "remove.paths của aniterals rỗng, không kiểm tra được gì"

# Danh sách khai báo THẬT, trích từ build-iso.sh bằng chính bộ lọc của check-profile.
mapfile -t real_declarations < <(
  awk '
    /^[[:space:]]*ANIOS_FILE_PERMISSIONS\+?=\(/ { in_list = 1; next }
    in_list && /^[[:space:]]*\)/ { in_list = 0; next }
    in_list {
      gsub(/^[[:space:]]*['\''"]|['\''"][[:space:]]*(#.*)?$/, "")
      if ($0 ~ /^[^:]+:[0-9]+:[0-9]+:[0-9]+$/) print
    }
  ' "$BUILD_ISO"
)
(( ${#real_declarations[@]} )) || fail "không đọc được ANIOS_FILE_PERMISSIONS từ build-iso.sh"

ANIOS_FILE_PERMISSIONS=("${real_declarations[@]}")
before_count="${#ANIOS_FILE_PERMISSIONS[@]}"
# Hàm in ra danh sách được giữ; nơi gọi trong build-iso.sh gán lại bằng mapfile.
mapfile -t ANIOS_FILE_PERMISSIONS < <(anios_drop_removed_permissions "${anitals_removed[@]}")
after_count="${#ANIOS_FILE_PERMISSIONS[@]}"

# Thông báo "drops" phải đi stderr, không được lẫn vào danh sách in ra stdout.
if grep -q 'file_permissions drops' < <(anios_drop_removed_permissions "${anitals_removed[@]}" 2>/dev/null); then
  fail "thông báo drops bị in ra stdout, sẽ lọt vào mảng file_permissions khi dùng mapfile"
fi
pass "thông báo drops đi stderr nên không làm bẩn mảng file_permissions"

# Hai script mà aniterals gỡ đều nằm trong danh sách khai báo của cả họ.
for dropped_script in /usr/local/bin/anios-persist /usr/local/bin/anios-steam-quit; do
  grep -qxF -- "$dropped_script" <(printf '%s\n' "${anitals_removed[@]}") ||
    fail "remove.paths của aniterals phải gỡ $dropped_script"
  grep -qxF -- "$dropped_script:0:0:755" <(printf '%s\n' "${real_declarations[@]}") ||
    fail "ANIOS_FILE_PERMISSIONS phải khai báo $dropped_script (bản anios vẫn cần nó)"
  if grep -qxF -- "$dropped_script:0:0:755" <(printf '%s\n' "${ANIOS_FILE_PERMISSIONS[@]}"); then
    fail "bản amnesic vẫn khai báo file_permissions cho $dropped_script đã bị gỡ: verify_file_permissions sẽ dừng bản dựng"
  fi
done
(( after_count == before_count - 2 )) ||
  fail "hàm lọc phải bỏ đúng 2 mục, thực tế $before_count -> $after_count"
pass "file_permissions bỏ đúng các mục mà edition đã gỡ khỏi ảnh (anios-persist, anios-steam-quit)"

# Không có gì bị gỡ thì danh sách phải nguyên vẹn.
ANIOS_FILE_PERMISSIONS=("${real_declarations[@]}")
mapfile -t ANIOS_FILE_PERMISSIONS < <(anios_drop_removed_permissions)
(( ${#ANIOS_FILE_PERMISSIONS[@]} == ${#real_declarations[@]} )) ||
  fail "không có remove.paths thì danh sách file_permissions phải giữ nguyên"
pass "edition không gỡ gì thì file_permissions giữ nguyên"

# --- Regression: AniTails không được yêu cầu gói chỉ có ở AUR ---------------
! grep -qxF 'secure-delete' "$ANITALS_MANIFEST" ||
  fail "secure-delete thuộc AUR nhưng AniTails tắt AUR; pacstrap sẽ không tìm thấy gói"
grep -qxF 'wipe' "$ANITALS_MANIFEST" || fail "AniTails phải giữ công cụ wipe"
pass "AniTails dùng wipe, không yêu cầu secure-delete từ kho chính thức"

# Chạy ĐÚNG pipeline kiểm tra Steam trong workflow trên script thật. Không dựng
# ISO: unsquashfs giả chỉ xuất nội dung file, kèm đuôi lớn để bắt grep -q/SIGPIPE.
steam_check="$(sed -n '/^[[:space:]]*unsquashfs -cat .*usr\/local\/bin\/anios-steam-setup |/p' \
  "$ROOT_DIR/.github/workflows/build-iso.yml")"
[[ -n "$steam_check" ]] || fail "không tìm được pipeline kiểm tra Steam của CI"
steam_fixture="$SANDBOX/steam-setup"
cp "$ROOT_DIR/profile/airootfs/usr/local/bin/anios-steam-setup" "$steam_fixture"
unsquashfs() {
  cat "$steam_fixture" || return
  # Lớn hơn pipe buffer; grep phải đọc hết thay vì thoát ngay khi tìm được mẫu.
  printf '%200000s\n' ''
}
sfs=unused
bash_check="$SANDBOX/check-steam.sh"
{
  echo 'set -euo pipefail'
  declare -f unsquashfs
  declare -p steam_fixture sfs
  printf '%s\n' "$steam_check"
} >"$bash_check"
bash "$bash_check" >"$SANDBOX/steam-check.log" ||
  fail "pipeline CI từ chối script Steam thật hoặc đóng pipe quá sớm"
# Đảm bảo phép kiểm tra vẫn phát hiện cache path sai, không chỉ luôn trả về 0.
sed -i 's|/usr/share/anios/steam-cache|/invalid/cache|g' "$steam_fixture"
if bash "$bash_check" >"$SANDBOX/steam-check-invalid.log"; then
  fail "pipeline CI chấp nhận bộ cài Steam không có cache path đúng"
fi
pass "pipeline CI nhận đúng cache path, đọc hết pipe và từ chối path sai"

echo "All edition self-tests passed."
