#!/usr/bin/env bash
# Tự kiểm tra scripts/check-live-aur.sh mà không cần dựng ISO, không cần Arch.
#
# `unsquashfs` thật chỉ có trên máy có squashfs-tools và chỉ đọc được squashfs
# thật, nên bài này dựng một bản unsquashfs giả mô phỏng đúng hai hành vi mà
# check-live-aur.sh dựa vào (đã đo trên squashfs-tools 4.6.1/4.7.5 và được
# scripts/selftest-check-live-audio.sh kiểm chứng):
#
#   unsquashfs -ll IMAGE PATH
#       in metadata dạng ls -l cho chuỗi thư mục cha rồi tới entry, kèm
#       " -> <đích>" nếu là symlink; KHÔNG trích gì, KHÔNG đi theo symlink.
#       PATH là thư mục thì in cả cây con. PATH không tồn tại thì vẫn exit 0 và
#       chỉ in các thư mục cha.
#
#   unsquashfs -cat IMAGE PATH
#       in nội dung file; TỪ CHỐI symlink tuyệt đối và trả exit code 2.
#
# Trên cây thư mục giả đó bài này dựng lại ảnh live với var/lib/pacman/local,
# usr/bin, etc/passwd, etc/sudoers.d và usr/share/anios/aur-packages.txt, rồi kiểm
# tra check-live-aur.sh ở các tình huống:
#
#   1. ảnh tốt                          -> exit 0, không mục THIẾU nào
#   2. thiếu binary (usr/bin/yay)        -> exit 1 và nêu đúng tên file thiếu
#   3. gói AUR không có trong pacman DB  -> exit 1 và nêu đúng tên gói
#   4. còn rác dựng gói (root/.anios-aur, tài khoản aniosbuild, sudo NOPASSWD)
#                                         -> exit 1 và nêu đủ cả ba
#   5. etc/sudoers.d có symlink TUYỆT ĐỐI -> không được chết, không được báo
#      thiếu sai (đúng cái bẫy -cat mà README.md mô tả)
#   6. ảnh không đọc được pacman DB       -> exit 1, không im lặng cho qua
#
# Chạy: ./scripts/selftest-check-live-aur.sh
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="$ROOT_DIR/scripts/check-live-aur.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

[[ -x "$CHECKER" ]] || fail "thiếu hoặc không chạy được $CHECKER"

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/anios-aur-check-selftest.XXXXXX")"
cleanup() {
  if [[ -n "${ANIOS_SELFTEST_KEEP_SANDBOX:-}" ]]; then
    echo "Sandbox giữ lại tại: $SANDBOX" >&2
    return 0
  fi
  rm -rf -- "$SANDBOX"
}
trap cleanup EXIT

FAKE_BIN="$SANDBOX/bin"
mkdir -p -- "$FAKE_BIN"

# --- unsquashfs giả -------------------------------------------------------
cat >"$FAKE_BIN/unsquashfs" <<'FAKE'
#!/usr/bin/env bash
set -Eeuo pipefail
image="" dest="squashfs-root" mode=extract
paths=()
while (($#)); do
  case "$1" in
    -q | -no-progress) shift ;;
    -cat) mode=cat; shift ;;
    -ll | -lls | -lln) mode=list-long; shift ;;
    -l | -ls) mode=list; shift ;;
    -d) dest="${2:?}"; shift 2 ;;
    -*) shift ;;
    *)
      if [[ -z "$image" ]]; then image="$1"; else paths+=("$1"); fi
      shift
      ;;
  esac
done
[[ -n "$image" && -d "$image" ]] || { echo "unsquashfs: cannot open $image" >&2; exit 1; }
prefix="$dest"

is_abs_symlink() {
  local entry="$image/${1#/}"
  [[ -L "$entry" ]] || return 1
  [[ "$(readlink -- "$entry")" == /* ]]
}

# <quyền> <chủ/nhóm> <kích thước> <ngày> <giờ> <prefix>/<đường dẫn>[ -> <đích>]
print_long_line() {
  local rel="$1" src="$image/$1" perms size target=""
  [[ -e "$src" || -L "$src" ]] || return 1
  perms="$(stat -c '%A' -- "$src")"
  size="$(stat -c '%s' -- "$src")"
  if [[ -L "$src" ]]; then
    target=" -> $(readlink -- "$src")"
  fi
  printf '%s %s %s %s %s/%s%s\n' \
    "$perms" "root/root" "$size" "2026-09-30 03:40" "$prefix" "$rel" "$target"
}

list_long() {
  local rel="$1" cur="" i
  local -a parts=()
  IFS='/' read -r -a parts <<<"$rel"
  for ((i = 0; i < ${#parts[@]}; i++)); do
    cur+="${cur:+/}${parts[i]}"
    # Thành phần không tồn tại: dừng, vẫn exit 0 (đúng như unsquashfs thật).
    [[ -e "$image/$cur" || -L "$image/$cur" ]] || return 0
    print_long_line "$cur"
  done
  if [[ -d "$image/$rel" ]]; then
    while IFS= read -r sub; do
      print_long_line "$rel/$sub"
    done < <(cd -- "$image" && find "$rel" -mindepth 1 -printf '%P\n' | sort)
  fi
}

if [[ "$mode" == cat ]]; then
  ((${#paths[@]} == 1)) || { echo "unsquashfs: -cat needs exactly one path" >&2; exit 1; }
  rel="${paths[0]#/}"
  if is_abs_symlink "$rel"; then
    echo "unsquashfs: cat: $rel failed to resolve symbolic link" >&2
    exit 2
  fi
  [[ -f "$image/$rel" ]] || { echo "unsquashfs: cat: no matches for $rel" >&2; exit 2; }
  cat -- "$image/$rel"
  exit 0
fi

if [[ "$mode" == list-long ]]; then
  ((${#paths[@]} > 0)) || paths=(.)
  for rel in "${paths[@]}"; do
    list_long "${rel#/}"
  done
  exit 0
fi

if [[ "$mode" == list ]]; then
  ((${#paths[@]} > 0)) || paths=(.)
  for rel in "${paths[@]}"; do
    rel="${rel#/}"
    [[ -e "$image/$rel" || -L "$image/$rel" ]] || continue
    if [[ -d "$image/$rel" ]]; then
      (cd -- "$image" && find "$rel" | sed "s|^|$prefix/|")
    else
      printf '%s/%s\n' "$prefix" "$rel"
    fi
  done
  exit 0
fi

echo "fake unsquashfs: bài tự kiểm tra chỉ cần -ll/-cat/-l" >&2
exit 1
FAKE
chmod 0755 -- "$FAKE_BIN/unsquashfs"

# --- Ảnh live giả ---------------------------------------------------------
# $1: thư mục ảnh. Dựng đúng bố cục mà check-live-aur.sh hỏi tới.
make_fake_image() {
  local img="$1"
  rm -rf -- "$img"
  mkdir -p -- "$img"/{usr/bin,usr/share/anios,root,home,var/tmp} \
    "$img"/etc/sudoers.d "$img"/var/lib/pacman/local

  # pacman DB: mỗi gói đã cài là một thư mục <tên>-<pkgver>-<pkgrel>-<arch>,
  # bên trong có desc/files như DB thật.
  local dbpkgs=(
    yay-13.0.1-1-x86_64
    coccoc-browser-stable-152.0.7977.124-1-x86_64
    legacy-launcher-latest-1-any
    python-3.13.1-1-x86_64
    python-pip-24.3.1-1-any
    nodejs-23.6.0-1-x86_64
    npm-11.0.0-1-any
    wine-10.0-1-x86_64
    winetricks-20240105-1-x86_64
    base-devel-1-2-x86_64
    git-2.47.1-1-x86_64
    jre-openjdk-21.0.2.u13-1-x86_64
    qt5-base-5.15.17+kde+r150-1-x86_64
    ttf-liberation-2.1.5-2-any
    linux-zen-6.13.4.zen1-1-x86_64
    hyprland-0.55.0-1-x86_64
    steam-1.0.0.82-1-x86_64
  )
  local dbpkg
  for dbpkg in "${dbpkgs[@]}"; do
    mkdir -p -- "$img/var/lib/pacman/local/$dbpkg"
    printf '%%NAME%%\n%s\n' "${dbpkg%-*-*-*}" >"$img/var/lib/pacman/local/$dbpkg/desc"
  done

  # Binary của các gói trên.
  local bin
  for bin in yay makepkg git python3 pip node npm wine winetricks java pacman \
    hyprland steam; do
    printf '#!/bin/sh\necho %s\n' "$bin" >"$img/usr/bin/$bin"
    chmod 0755 -- "$img/usr/bin/$bin"
  done

  # /etc/passwd: tài khoản live anios, KHÔNG có tài khoản dựng gói tạm.
  cat >"$img/etc/passwd" <<'PASSWD'
root:x:0:0:root:/root:/usr/bin/bash
anios:x:1000:1000:AniOS Live User:/home/anios:/bin/bash
sddm:x:977:977:sddm user:/:/usr/bin/nologin
PASSWD
  mkdir -p -- "$img/home/anios"

  # /etc/sudoers.d: chính sách của tài khoản live (có mật khẩu, không NOPASSWD).
  cat >"$img/etc/sudoers.d/10-anios-live" <<'SUDOERS'
anios ALL=(ALL:ALL) PASSWD: ALL
SUDOERS
  chmod 0440 -- "$img/etc/sudoers.d/10-anios-live"

  # Báo cáo gói AUR do scripts/anios-aur-build.sh ghi lại.
  cat >"$img/usr/share/anios/aur-packages.txt" <<'REPORT'
# Gói AUR được dựng và cài sẵn trong ảnh live AniOS này.
# Trong phiên live, cập nhật cả kho chính thức lẫn AUR bằng: yay -Syu
yay=13.0.1-1
coccoc-browser-stable=152.0.7977.124-1
legacy-launcher=latest-1
REPORT

  # pkglist.x86_64.txt như mkarchiso sinh ra (tên gói + phiên bản).
  cat >"$img/pkglist.txt" <<'PKGLIST'
linux-zen 6.13.4.zen1-1
hyprland 0.55.0-1
sddm 0.21.0-1
steam 1.0.0.82-1
pipewire-audio 1.4.0-1
ibus-unikey 0.4.0-1
firefox 135.0-1
yay 13.0.1-1
coccoc-browser-stable 152.0.7977.124-1
legacy-launcher latest-1
python 3.13.1-1
python-pip 24.3.1-1
nodejs 23.6.0-1
npm 11.0.0-1
wine 10.0-1
winetricks 20240105-1
base-devel 1-2
git 2.47.1-1
jre-openjdk 21.0.2.u13-1
qt5-base 5.15.17+kde+r150-1
ttf-liberation 2.1.5-2
PKGLIST
}

run_checker() {
  local img="$1" out="$2" with_pkglist="${3:-yes}"
  local -a args=("$img")
  [[ "$with_pkglist" == yes ]] && args+=("$img/pkglist.txt")
  PATH="$FAKE_BIN:$PATH" "$CHECKER" "${args[@]}" >"$out" 2>&1 || return $?
  return 0
}

# --- 1. Ảnh tốt -----------------------------------------------------------
IMG="$SANDBOX/img-good"
make_fake_image "$IMG"
out="$SANDBOX/out-good"
status=0
run_checker "$IMG" "$out" || status=$?
(( status == 0 )) || { cat "$out" >&2; fail "ảnh tốt mà script trả exit $status"; }
grep -qF 'THIẾU' "$out" && { cat "$out" >&2; fail "ảnh tốt mà vẫn báo THIẾU"; }
for pkg in yay coccoc-browser-stable legacy-launcher python nodejs wine; do
  grep -qE "OK    $pkg\b" "$out" || { cat "$out" >&2; fail "ảnh tốt mà không xác nhận gói $pkg"; }
done
grep -qF 'OK    usr/bin/yay' "$out" || fail "không xác nhận binary usr/bin/yay"
grep -qF 'OK    root/.anios-aur đã được dọn' "$out" || fail "không xác nhận rác dựng gói đã dọn"
grep -qF 'OK    không có luật sudo NOPASSWD nào' "$out" || fail "không xác nhận ảnh sạch NOPASSWD"
grep -qE 'yay=13\.0\.1-1' "$out" || fail "không in báo cáo gói AUR có trong ảnh"
pass "ảnh tốt: đủ yay + gói AUR, python, nodejs, wine, không rác, exit 0"

# --- 2. Thiếu binary ------------------------------------------------------
IMG2="$SANDBOX/img-nobin"
make_fake_image "$IMG2"
rm -f -- "$IMG2/usr/bin/yay"
out="$SANDBOX/out-nobin"
status=0
run_checker "$IMG2" "$out" || status=$?
(( status != 0 )) || fail "thiếu usr/bin/yay mà script vẫn exit 0"
grep -qF 'THIẾU usr/bin/yay' "$out" || { cat "$out" >&2; fail "không nêu đúng binary thiếu"; }
pass "thiếu binary của gói AUR bị phát hiện"

# --- 3. Gói AUR không nằm trong pacman DB ---------------------------------
IMG3="$SANDBOX/img-nopkg"
make_fake_image "$IMG3"
rm -rf -- "$IMG3/var/lib/pacman/local/coccoc-browser-stable-152.0.7977.124-1-x86_64"
out="$SANDBOX/out-nopkg"
status=0
run_checker "$IMG3" "$out" || status=$?
(( status != 0 )) || fail "pacman DB thiếu coccoc-browser-stable mà script vẫn exit 0"
grep -qF 'THIẾU coccoc-browser-stable không có trong pacman DB' "$out" ||
  { cat "$out" >&2; fail "không nêu đúng gói AUR thiếu trong pacman DB"; }
# pkglist vẫn còn tên gói -> phải bị bắt, vì ảnh thật mới là thứ người dùng boot.
grep -qF 'THIẾU coccoc-browser-stable không có trong pkglist' "$out" &&
  fail "pkglist đã bị xoá gói đó khỏi DB mà vẫn báo thiếu pkglist là sai kịch bản"
pass "gói AUR vắng mặt trong pacman DB của ảnh bị phát hiện"

# pkglist thiếu gói cũng phải bị bắt (trường hợp hook chạy nhưng pkglist cũ).
IMG3B="$SANDBOX/img-nopkglist"
make_fake_image "$IMG3B"
grep -v '^yay ' "$IMG3B/pkglist.txt" >"$IMG3B/pkglist.new" && mv "$IMG3B/pkglist.new" "$IMG3B/pkglist.txt"
out="$SANDBOX/out-nopkglist"
status=0
run_checker "$IMG3B" "$out" || status=$?
(( status != 0 )) || fail "pkglist của ISO thiếu yay mà script vẫn exit 0"
grep -qF 'THIẾU yay không có trong pkglist' "$out" ||
  { cat "$out" >&2; fail "không nêu đúng gói thiếu trong pkglist"; }
pass "pkglist của ISO thiếu gói AUR cũng bị phát hiện"

# --- 4. Rác của bước dựng gói AUR ----------------------------------------
IMG4="$SANDBOX/img-residue"
make_fake_image "$IMG4"
mkdir -p -- "$IMG4/root/.anios-aur" "$IMG4/var/tmp/anios-aur-build/src/yay"
printf 'yay\n' >"$IMG4/root/.anios-aur/packages.aur.x86_64"
printf '#!/bin/bash\nexit 0\n' >"$IMG4/root/customize_airootfs.sh"
mkdir -p -- "$IMG4/home/aniosbuild"
printf 'aniosbuild:x:1412:1412::/var/tmp/anios-aur-build/home:/bin/bash\n' >>"$IMG4/etc/passwd"
printf 'aniosbuild ALL=(ALL) NOPASSWD: ALL\n' >"$IMG4/etc/sudoers.d/20-anios-aur-build"
out="$SANDBOX/out-residue"
status=0
run_checker "$IMG4" "$out" || status=$?
(( status != 0 )) || fail "ảnh còn rác dựng gói AUR mà script vẫn exit 0"
for complaint in \
  'THIẾU root/.anios-aur vẫn nằm trong ảnh live' \
  'THIẾU root/customize_airootfs.sh vẫn nằm trong ảnh live' \
  'THIẾU var/tmp/anios-aur-build vẫn nằm trong ảnh live' \
  'THIẾU home/aniosbuild vẫn nằm trong ảnh live' \
  'THIẾU tài khoản dựng gói aniosbuild vẫn còn trong etc/passwd' \
  'THIẾU có luật sudo NOPASSWD trong ảnh live'; do
  grep -qF "$complaint" "$out" || { cat "$out" >&2; fail "không phát hiện: $complaint"; }
done
# Tài khoản live vẫn phải được xác nhận là còn, kẻo bước dọn bị nghi oan.
grep -qF 'THIẾU tài khoản live anios biến mất' "$out" && fail "báo sai rằng tài khoản live biến mất"
pass "rác dựng gói AUR (thư mục, hook, tài khoản tạm, NOPASSWD) đều bị phát hiện"

# --- 5. Bẫy symlink tuyệt đối trong etc/sudoers.d -------------------------
IMG5="$SANDBOX/img-symlink"
make_fake_image "$IMG5"
# File do gói cài, nằm ở /usr/share và được link tuyệt đối vào etc/sudoers.d —
# đúng kiểu symlink mà `unsquashfs -cat` từ chối đọc (exit 2).
mkdir -p -- "$IMG5/usr/share/anios"
printf '%%sudo ALL=(ALL) ALL\n' >"$IMG5/usr/share/anios/50-anios-shared"
ln -s /usr/share/anios/50-anios-shared "$IMG5/etc/sudoers.d/50-anios-shared"
out="$SANDBOX/out-symlink"
status=0
run_checker "$IMG5" "$out" || status=$?
(( status == 0 )) || { cat "$out" >&2; fail "symlink tuyệt đối trong etc/sudoers.d làm script chết (exit $status)"; }
grep -qF 'THIẾU' "$out" && { cat "$out" >&2; fail "symlink tuyệt đối bị báo THIẾU sai"; }
pass "symlink tuyệt đối trong etc/sudoers.d không làm chết bước kiểm tra"

# --- 6. Ảnh không đọc được pacman DB --------------------------------------
IMG6="$SANDBOX/img-empty"
mkdir -p -- "$IMG6/usr/bin"
out="$SANDBOX/out-empty"
status=0
run_checker "$IMG6" "$out" no || status=$?
(( status != 0 )) || fail "ảnh không có pacman DB mà script vẫn exit 0"
grep -qF 'không đọc được var/lib/pacman/local' "$out" ||
  { cat "$out" >&2; fail "không báo rõ là không đọc được pacman DB"; }
pass "ảnh hỏng/không có pacman DB bị chặn, không im lặng cho qua"

# --- 7. Không truyền pkglist thì vẫn kiểm tra được bằng pacman DB ---------
out="$SANDBOX/out-nolist"
status=0
run_checker "$IMG" "$out" no || status=$?
(( status == 0 )) || { cat "$out" >&2; fail "không có pkglist mà script vẫn exit $status"; }
grep -qF '(bỏ qua đối chiếu pkglist' "$out" || fail "không nói rõ đã bỏ qua bước pkglist"
grep -qF 'OK    yay' "$out" || fail "không có pkglist thì không xác nhận được gói AUR"
pass "vẫn kiểm tra được gói AUR khi chỉ có airootfs.sfs, không có pkglist"

echo "AniOS live AUR check self-test passed"
