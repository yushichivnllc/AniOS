#!/usr/bin/env bash
# Tự kiểm tra bước khai báo file_permissions của scripts/build-iso.sh mà không cần
# dựng ISO, không cần Arch, không cần root.
#
# Vì sao có bài này: mkarchiso chép profile/airootfs bằng
# `cp -af --no-preserve=ownership,mode`, nên bit thực thi của script trong ảnh chỉ
# còn nếu build-iso.sh ghi lại nó vào mảng file_permissions của profiledef.sh.
# Bước đó từng giữ HAI bản danh sách chép tay (một để ghi, một để đối chiếu) và
# chúng lệch nhau: bản đối chiếu có /usr/local/bin/anios-steam-quit — script mà
# anios-steam-quit.service gọi lúc tắt máy để Steam thoát êm — còn bản ghi thì
# không. Kết quả: MỌI lượt dựng CI chết sau ~3 phút với
#
#     Failed to declare file_permissions entry: ["/usr/local/bin/anios-steam-quit"]="0:0:755"
#
# dù profile hoàn toàn lành. Danh sách nay chỉ còn một (ANIOS_FILE_PERMISSIONS),
# và bài này chạy đúng hàm ghi/đối chiếu của build-iso.sh trên một profile releng
# giả để khoá lại cả bốn hướng hỏng:
#
#   1. đường ngay thẳng: mọi mục của AniOS nằm trong mảng file_permissions mà
#      mkarchiso thật sự nạp, còn các mục gốc của releng vẫn nguyên vẹn;
#   2. đúng lỗi từng làm hỏng CI: ghi thiếu một mục -> bước đối chiếu phải dừng
#      bản dựng và nêu đúng tên mục đó;
#   3. khai báo đường dẫn không có trong ảnh -> phải dừng, vì mkarchiso chỉ CẢNH
#      BÁO rồi bỏ qua chmod (ship script không có bit thực thi mà CI vẫn xanh);
#   4. releng đổi cách khai báo mảng (ví dụ thành `declare -A file_permissions=(`)
#      làm sed không còn khớp -> phải dừng thay vì âm thầm bỏ qua mọi khai báo.
#
# Chạy: ./scripts/selftest-build-iso-permissions.sh
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ISO="$ROOT_DIR/scripts/build-iso.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*" ; }

[[ -f "$BUILD_ISO" ]] || fail "thiếu $BUILD_ISO"

# --- Nạp danh sách và hàm từ build-iso.sh ---------------------------------
# build-iso.sh chạy ngay khi nạp (cần root, archiso...) nên không `source` được;
# lấy riêng từng khối: mảng ANIOS_FILE_PERMISSIONS (cả khối += của WITH_AUR, vì
# bài này muốn kiểm tra trường hợp đầy đủ nhất) và thân mỗi hàm, từ dòng khai báo
# ở đầu dòng tới dấu `}` đầu tiên ở đầu dòng.
list_src="$(awk '
  /^[[:space:]]*ANIOS_FILE_PERMISSIONS\+?=\(/ { p = 1 }
  p { print }
  p && /^[[:space:]]*\)/ { p = 0 }
' "$BUILD_ISO")"
[[ -n "$list_src" ]] ||
  fail "scripts/build-iso.sh không còn mảng ANIOS_FILE_PERMISSIONS (khai báo ở đầu dòng)"
eval "$list_src"
[[ -n "${ANIOS_FILE_PERMISSIONS[*]:-}" ]] ||
  fail "không đọc được mục nào từ ANIOS_FILE_PERMISSIONS của scripts/build-iso.sh"

load_function() {
  local name="$1" src
  src="$(awk -v fn="$name" '
    $0 == fn "() {" { p = 1 }
    p { print }
    p && /^}$/ { exit }
  ' "$BUILD_ISO")"
  [[ -n "$src" ]] ||
    fail "scripts/build-iso.sh không còn hàm $name() (khai báo ở đầu dòng)"
  [[ "$(tail -n1 <<<"$src")" == '}' ]] ||
    fail "không tìm thấy dấu '}' đóng hàm $name() ở đầu dòng"
  (( $(wc -l <<<"$src") <= 60 )) ||
    fail "hàm $name() dài bất thường: có thể dấu '}' đóng hàm không nằm ở đầu dòng"
  eval "$src"
}
load_function split_file_permission
load_function insert_file_permissions
load_function verify_file_permissions

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/anios-permissions-selftest.XXXXXX")"
cleanup() {
  if [[ -n "${ANIOS_SELFTEST_KEEP_SANDBOX:-}" ]]; then
    echo "Sandbox giữ lại tại: $SANDBOX" >&2
    return 0
  fi
  rm -rf -- "$SANDBOX"
}
trap cleanup EXIT

# profiledef.sh của profile releng mà archiso cài (configs/releng/profiledef.sh).
# build-iso.sh chỉ đổi các chuỗi nhận diện và bootmode trước khi chèn, nên phần
# quan trọng ở đây là dòng mở mảng `file_permissions=(` nằm ở ĐẦU DÒNG: đó chính là
# mấu neo của sed trong insert_file_permissions.
write_releng_profiledef() {
  cat >"$1" <<'PROFILEDEF'
#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="archlinux"
iso_label="ARCH_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Arch Linux <https://archlinux.org>"
iso_application="Arch Linux Live/Rescue DVD"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
bootmodes=('bios.syslinux'
           'uefi.grub')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86,arm64' '-b' '1M' '-Xdict-size' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads' 'logical' '--long' '-19')
kernel_params_aarch64="clk_ignore_unused pd_ignore_unused arm64.nopauth"
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/root/.gnupg"]="0:0:700"
  ["/usr/local/bin/choose-mirror"]="0:0:755"
  ["/usr/local/bin/Installation_guide"]="0:0:755"
  ["/usr/local/bin/livecd-sound"]="0:0:755"
)
PROFILEDEF
}

# Cây airootfs giả: chỉ cần ĐƯỜNG DẪN tồn tại (mkarchiso chmod/chown tệp thật của
# ảnh, còn bài này kiểm tra việc khai báo). Ba helper của installer cũng có mặt vì
# build-iso.sh chép chúng từ profile/installer/scripts vào ảnh trước bước này.
write_fake_airootfs() {
  local root="$1" entry
  for entry in "${ANIOS_FILE_PERMISSIONS[@]}"; do
    split_file_permission "$entry"
    install -D -m 0644 /dev/null "$root$FP_PATH"
  done
}

# Số mục releng ship sẵn: dùng để chắc sed chèn VÀO TRONG mảng chứ không phải sau
# dấu `)` đóng mảng (chèn ra ngoài thì bash vẫn parse được mà mục thì mất hút).
RELENG_ENTRY_COUNT=7

new_profile() {
  local dir="$1"
  rm -rf -- "$dir"
  install -d -m 0755 -- "$dir"
  write_releng_profiledef "$dir/profiledef.sh"
  write_fake_airootfs "$dir/airootfs"
}

# Đọc mảng file_permissions đúng cách mkarchiso đọc: khai báo mảng kết hợp trước
# rồi source profiledef.sh (hàm _read_profile của mkarchiso).
dump_declared() {
  bash -c '
    declare -A file_permissions=()
    . "$1" || exit 1
    for path in "${!file_permissions[@]}"; do
      printf "%s=%s\n" "$path" "${file_permissions["$path"]}"
    done
  ' _ "$1"
}

expect_verify_failure() {
  local label="$1" pattern="$2" out status
  out="$SANDBOX/$label.out"
  set +e
  ( verify_file_permissions ) >"$out" 2>&1
  status=$?
  set -e
  (( status != 0 )) ||
    fail "$label: bước đối chiếu phải dừng bản dựng nhưng lại trả exit 0"
  grep -qF -- "$pattern" "$out" ||
    fail "$label: thông báo lỗi phải nêu '$pattern', thực tế là: $(tr '\n' ' ' <"$out")"
}

# --- 1. Đường ngay thẳng ---------------------------------------------------
BUILD_PROFILE="$SANDBOX/good"
new_profile "$BUILD_PROFILE"
insert_file_permissions
bash -n "$BUILD_PROFILE/profiledef.sh" || fail "profiledef.sh hỏng cú pháp sau khi chèn file_permissions"
( verify_file_permissions ) >"$SANDBOX/good.out" 2>&1 ||
  fail "đường ngay thẳng không qua được bước đối chiếu: $(tr '\n' ' ' <"$SANDBOX/good.out")"

declared="$(dump_declared "$BUILD_PROFILE/profiledef.sh")"
for entry in "${ANIOS_FILE_PERMISSIONS[@]}"; do
  split_file_permission "$entry"
  grep -qxF -- "$FP_PATH=${entry#*:}" <<<"$declared" ||
    fail "mkarchiso sẽ không thấy khai báo $FP_LINE trong profiledef.sh"
done
for releng_entry in \
  '/etc/shadow=0:0:400' \
  '/root=0:0:750' \
  '/root/.automated_script.sh=0:0:755' \
  '/root/.gnupg=0:0:700' \
  '/usr/local/bin/choose-mirror=0:0:755' \
  '/usr/local/bin/Installation_guide=0:0:755' \
  '/usr/local/bin/livecd-sound=0:0:755'; do
  grep -qxF -- "$releng_entry" <<<"$declared" ||
    fail "mục gốc của releng bị mất khi chèn khai báo của AniOS: $releng_entry"
done
declared_count="$(wc -l <<<"$declared")"
(( declared_count == RELENG_ENTRY_COUNT + ${#ANIOS_FILE_PERMISSIONS[@]} )) ||
  fail "mảng file_permissions có $declared_count mục, cần $((RELENG_ENTRY_COUNT + ${#ANIOS_FILE_PERMISSIONS[@]})): sed có thể đã chèn ra ngoài mảng"
pass "mọi khai báo của AniOS nằm trong mảng file_permissions, mục của releng vẫn nguyên (${#ANIOS_FILE_PERMISSIONS[@]} mục AniOS)"

# Chính sách sudo của phiên live phải 0440 (không đọc được bằng tài khoản thường),
# còn script phải 0755 — sai một trong hai là hỏng cả phiên live.
grep -qxF -- '/etc/sudoers.d/10-anios-live=0:0:440' <<<"$declared" ||
  fail 'file_permissions phải giữ quyền 0440 cho /etc/sudoers.d/10-anios-live'
grep -qxF -- '/usr/local/bin/anios-steam-quit=0:0:755' <<<"$declared" ||
  fail 'file_permissions phải giữ bit thực thi cho /usr/local/bin/anios-steam-quit (anios-steam-quit.service gọi nó lúc tắt máy)'

# --- 2. Đúng lỗi từng làm hỏng CI: ghi thiếu một mục ----------------------
BUILD_PROFILE="$SANDBOX/missing-declaration"
new_profile "$BUILD_PROFILE"
full_list=("${ANIOS_FILE_PERMISSIONS[@]}")
dropped=()
for entry in "${full_list[@]}"; do
  [[ "$entry" == '/usr/local/bin/anios-steam-quit:0:0:755' ]] || dropped+=("$entry")
done
(( ${#dropped[@]} == ${#full_list[@]} - 1 )) || fail "không dựng được kịch bản thiếu anios-steam-quit"
ANIOS_FILE_PERMISSIONS=("${dropped[@]}")
insert_file_permissions
ANIOS_FILE_PERMISSIONS=("${full_list[@]}")
expect_verify_failure missing-declaration \
  'Failed to declare file_permissions entry: ["/usr/local/bin/anios-steam-quit"]="0:0:755"'
pass "ghi thiếu một mục thì bước đối chiếu dừng bản dựng và nêu đúng mục đó"

# --- 3. Khai báo đường dẫn không có trong ảnh ------------------------------
BUILD_PROFILE="$SANDBOX/missing-file"
new_profile "$BUILD_PROFILE"
rm -f -- "$BUILD_PROFILE/airootfs/usr/local/bin/anios-sober"
insert_file_permissions
expect_verify_failure missing-file \
  'file_permissions declares /usr/local/bin/anios-sober but the image has no such file'
pass "khai báo đường dẫn không tồn tại trong ảnh bị chặn (mkarchiso thật chỉ cảnh báo rồi bỏ qua chmod)"

# --- 4. releng đổi cách khai báo mảng --------------------------------------
BUILD_PROFILE="$SANDBOX/moved-anchor"
new_profile "$BUILD_PROFILE"
sed -i 's/^file_permissions=(/declare -A file_permissions=(/' "$BUILD_PROFILE/profiledef.sh"
insert_file_permissions
expect_verify_failure moved-anchor \
  'Failed to declare file_permissions entry: ["/etc/sudoers.d/10-anios-live"]="0:0:440"'
pass "releng đổi dòng mở mảng thì bản dựng dừng lại thay vì âm thầm bỏ qua mọi khai báo"

# --- 5. Mục sai định dạng --------------------------------------------------
BUILD_PROFILE="$SANDBOX/bad-entry"
new_profile "$BUILD_PROFILE"
ANIOS_FILE_PERMISSIONS=('/usr/local/bin/anios-setup:0:0')
set +e
( insert_file_permissions ) >"$SANDBOX/bad-entry.out" 2>&1
bad_status=$?
set -e
(( bad_status != 0 )) || fail "mục thiếu trường phải bị từ chối"
grep -qF 'Invalid file_permissions entry' "$SANDBOX/bad-entry.out" ||
  fail "mục thiếu trường phải báo 'Invalid file_permissions entry', thực tế: $(tr '\n' ' ' <"$SANDBOX/bad-entry.out")"
ANIOS_FILE_PERMISSIONS=("${full_list[@]}")
pass "mục viết sai định dạng <path>:<uid>:<gid>:<mode> bị từ chối ngay"

# --- 6. Danh sách trong build-iso.sh khớp với cây airootfs thật ------------
# Bài này dựng cây giả nên phải đối chiếu thêm với repo: mỗi đường dẫn khai báo
# phải có thật trong profile/airootfs, hoặc là helper mà build-iso.sh chép từ
# profile/installer/scripts vào ảnh khi dựng kèm gói AUR.
for entry in "${full_list[@]}"; do
  split_file_permission "$entry"
  [[ -e "$ROOT_DIR/profile/airootfs$FP_PATH" ]] && continue
  [[ -s "$ROOT_DIR/profile/installer/scripts/${FP_PATH##*/}" ]] && continue
  fail "build-iso.sh khai báo $FP_PATH nhưng cả profile/airootfs lẫn profile/installer/scripts đều không có"
done
# Và chiều ngược lại cho script thật sự ship trong ảnh: thiếu khai báo là mất bit
# thực thi (chính là lỗi của anios-steam-quit trước đây).
while IFS= read -r -d '' shipped; do
  shipped_path="/${shipped#"$ROOT_DIR/profile/airootfs"/}"
  grep -qxF -- "$shipped_path:0:0:755" <<<"$(printf '%s\n' "${full_list[@]}")" ||
    fail "tệp thực thi $shipped_path không được khai báo trong ANIOS_FILE_PERMISSIONS"
done < <(find "$ROOT_DIR/profile/airootfs/usr/local" "$ROOT_DIR/profile/airootfs/etc/grub.d" \
  -type f -perm -u+x -print0 2>/dev/null)
pass "danh sách khai báo khớp với cây airootfs thật của repo theo cả hai chiều"

echo "All file_permissions self-tests passed."
