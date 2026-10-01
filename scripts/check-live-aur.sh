#!/usr/bin/env bash
# Kiểm tra các gói cài sẵn mới của AniOS ngay bên trong airootfs.sfs vừa dựng:
# gói AUR (yay, coccoc-browser-stable, legacy-launcher), python, nodejs, wine và
# bộ công cụ để yay dựng được gói ngay trong phiên live (base-devel, git).
#
#   Usage: scripts/check-live-aur.sh <airootfs.sfs> [pkglist.x86_64.txt]
#
# Vì sao cần script riêng dù pkglist đã liệt kê tên gói:
#   * pkglist nằm TRÊN ISO và do mkarchiso sinh ra; đối chiếu thêm pacman DB đọc
#     thẳng từ squashfs (var/lib/pacman/local/<gói>-<pkgver>-<pkgrel>) mới chắc
#     rằng gói thật sự nằm trong ảnh chứ không phải trong file của lượt dựng cũ.
#   * Gói "có trong danh sách" chưa chắc để lại binary chạy được: script kiểm tra
#     thêm usr/bin/yay, usr/bin/python3, usr/bin/node, usr/bin/wine,
#     usr/bin/makepkg... để chắc yay/python/nodejs/wine dùng được thật.
#   * Quan trọng nhất: bước dựng gói AUR tạo tài khoản tạm `aniosbuild`, thư mục
#     /root/.anios-aur, hook customize_airootfs.sh và rác makepkg trong /var/tmp.
#     Không thứ nào được nằm lại trong ảnh, và tuyệt đối không được có luật sudo
#     NOPASSWD nào lọt vào ảnh — scripts/anios-aur-build.sh không dùng sudo, nên
#     thấy NOPASSWD nghĩa là có gì đó đã thay đổi ngoài ý muốn.
#
# ---------------------------------------------------------------------------
# CHỈ DÙNG `unsquashfs -ll` VÀ `-cat` CHO FILE THƯỜNG
# ---------------------------------------------------------------------------
# Hai cái bẫy của unsquashfs đã được ghi trong README.md và kiểm chứng bằng
# scripts/selftest-check-live-audio.sh:
#   * `-cat` TỪ CHỐI symlink tuyệt đối (unsquashfs.c, cat_scan(), nhánh
#     SQUASHFS_SYMLINK_TYPE) và trả exit code 2;
#   * `-d` chết với "dir_scan: failed to make directory ..., because File exists"
#     khi thư mục đích đã tồn tại, và `-cat`/`-d` không phân biệt được "entry
#     không có" với "không đọc được".
# Vì vậy script này hỏi LOẠI entry bằng `unsquashfs -ll` (chỉ đọc metadata, không
# trích gì, không đi theo symlink, thư mục cha to cỡ nào cũng được — kể cả
# var/lib/pacman/local với vài nghìn entry), rồi chỉ `-cat` những entry đã xác
# nhận là FILE THƯỜNG (cột quyền bắt đầu bằng '-').
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/check-live-aur.sh <airootfs.sfs> [pkglist]

  <airootfs.sfs>  squashfs của ảnh live (thường là out/airootfs.sfs)
  [pkglist]       pkglist.x86_64.txt lấy từ ISO; bỏ trống thì script chỉ dựa
                  vào var/lib/pacman/local đọc thẳng từ squashfs
EOF
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
esac

SQUASHFS="${1:-}"
PKGLIST="${2:-}"

[[ -n "$SQUASHFS" ]] || { usage >&2; exit 2; }
[[ -s "$SQUASHFS" ]] || { echo "::error::Không tìm thấy squashfs: $SQUASHFS" >&2; exit 2; }
command -v unsquashfs >/dev/null 2>&1 ||
  { echo "::error::Thiếu unsquashfs (gói squashfs-tools)" >&2; exit 2; }

fail() { echo "::error::$*" >&2; exit 1; }
missing() { echo "  THIẾU $*"; ERRORS=$((ERRORS + 1)); }
ok() { echo "  OK    $*"; }
ERRORS=0

# --- Những gì phải có trong ảnh live --------------------------------------
# Gói AUR: dựng lúc build bởi scripts/anios-aur-build.sh, liệt kê trong
# profile/packages.aur.x86_64.
AUR_PACKAGES=(yay coccoc-browser-stable legacy-launcher)
# Gói kho chính thức cài sẵn theo yêu cầu (python, nodejs, wine) và những thứ bắt
# buộc phải có để `yay -S <gói>` chạy được ngay trong phiên live.
REPO_PACKAGES=(
  python python-pip nodejs npm wine winetricks
  base-devel git jre-openjdk qt5-base ttf-liberation
)
# Binary phải tồn tại để người dùng thật sự chạy được các gói trên.
REQUIRED_FILES=(
  usr/bin/yay
  usr/bin/makepkg
  usr/bin/git
  usr/bin/python3
  usr/bin/pip
  usr/bin/node
  usr/bin/npm
  usr/bin/wine
  usr/bin/winetricks
  usr/bin/java
)
# Rác của bước dựng gói AUR: không thứ nào được nằm trong ảnh cuối.
FORBIDDEN_PATHS=(
  root/.anios-aur
  root/customize_airootfs.sh
  var/tmp/anios-aur-build
  home/aniosbuild
)

# --- Đọc squashfs bằng metadata (`unsquashfs -ll`) ------------------------
# `unsquashfs -ll <path>` in chuỗi thư mục cha rồi tới entry, mỗi dòng dạng:
#   <quyền> <chủ/nhóm> <kích thước> <ngày> <giờ> <prefix>/<đường dẫn>[ -> <đích>]
# Đường dẫn không tồn tại: vẫn exit 0, chỉ in các thư mục cha. Nếu <path> là thư
# mục thì in cả cây con — nhờ vậy một lời gọi lấy được toàn bộ
# var/lib/pacman/local.
sfs_ll() {
  unsquashfs -ll "$SQUASHFS" "${1#/}" 2>/dev/null || true
}

# Biến một dòng metadata thành đường dẫn tương đối bên trong ảnh: cắt phần
# " -> <đích>" của symlink, bỏ prefix một thành phần (squashfs-root) và bỏ dấu '/'
# cuối mà unsquashfs in cho thư mục.
sfs_rel_of_line() {
  local line="$1" tail
  line="${line%% -> *}"
  tail="${line##*[[:space:]]}"
  tail="${tail%/}"
  printf '%s' "${tail#*/}"
}

# Dòng metadata của đúng entry <path> (rỗng nếu không có).
sfs_meta_line() {
  local want="${1#/}" line rel
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    rel="$(sfs_rel_of_line "$line")"
    if [[ "$rel" == "$want" ]]; then
      printf '%s\n' "$line"
      return 0
    fi
  done < <(sfs_ll "$want")
  return 1
}

sfs_exists() { sfs_meta_line "$1" >/dev/null; }

# Ký tự đầu của cột quyền: '-' file thường, 'd' thư mục, 'l' symlink.
sfs_type() {
  local line
  line="$(sfs_meta_line "$1" 2>/dev/null || true)"
  [[ -n "$line" ]] || return 1
  printf '%s' "${line:0:1}"
}

sfs_is_regular_file() { [[ "$(sfs_type "$1" || true)" == "-" ]]; }
sfs_is_symlink() { [[ "$(sfs_type "$1" || true)" == "l" ]]; }

# Chỉ -cat khi chắc chắn là file thường (xem khối chú thích đầu file).
sfs_cat_regular() {
  sfs_is_regular_file "$1" || return 1
  unsquashfs -cat "$SQUASHFS" "${1#/}" 2>/dev/null
}

# Mọi đường dẫn tương đối cấp 1 ngay dưới <dir> (dùng cho pacman DB và sudoers.d).
sfs_children() {
  local dir="${1#/}" line rel
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    rel="$(sfs_rel_of_line "$line")"
    [[ "$rel" == "$dir"/* ]] || continue
    rel="${rel#"$dir"/}"
    [[ "$rel" == */* ]] && continue
    [[ -n "$rel" ]] && printf '%s\n' "$rel"
  done < <(sfs_ll "$dir")
}

echo "Kiểm tra gói AUR, python, nodejs, wine trong $SQUASHFS"

# --- 1. Gói đã cài: đọc pacman DB của chính ảnh live ----------------------
LOCAL_DB_CHILDREN="$(sfs_children var/lib/pacman/local)"
[[ -n "$LOCAL_DB_CHILDREN" ]] ||
  fail "không đọc được var/lib/pacman/local từ $SQUASHFS (ảnh hỏng hoặc unsquashfs lỗi)"

# Thư mục DB của pacman có dạng <tên>-<pkgver>-<pkgrel> (libalpm/be_local.c,
# _alpm_splitname: không có hậu tố -<arch>, và cả pkgver lẫn pkgrel đều không
# được chứa dấu '-' nên hai dấu '-' cuối luôn tách chính xác tên gói khỏi phiên
# bản). Bước 2 vẫn đối chiếu thêm với pkglist (cột 1 là tên gói) khi có file đó.
db_has_package() {
  local pkg="$1"
  grep -qE "^${pkg//./\\.}-[^-]+-[^-]+$" <<<"$LOCAL_DB_CHILDREN"
}

db_entry_of() {
  local pkg="$1"
  grep -E "^${pkg//./\\.}-[^-]+-[^-]+$" <<<"$LOCAL_DB_CHILDREN" | head -n1
}

echo "  Gói AUR (dựng lúc build, không có trong kho chính thức):"
for pkg in "${AUR_PACKAGES[@]}"; do
  if db_has_package "$pkg"; then
    ok "$pkg ($(db_entry_of "$pkg"))"
  else
    missing "$pkg không có trong pacman DB của ảnh live"
  fi
done

echo "  Gói kho chính thức cài sẵn (python, nodejs, wine, công cụ AUR):"
for pkg in "${REPO_PACKAGES[@]}"; do
  if db_has_package "$pkg"; then
    ok "$pkg"
  else
    missing "$pkg không có trong pacman DB của ảnh live"
  fi
done

# --- 2. Đối chiếu pkglist của ISO (nếu được cung cấp) ---------------------
if [[ -n "$PKGLIST" ]]; then
  [[ -s "$PKGLIST" ]] || fail "pkglist rỗng hoặc không đọc được: $PKGLIST"
  echo "  Đối chiếu $PKGLIST (tên gói chính xác ở cột 1):"
  for pkg in "${AUR_PACKAGES[@]}" "${REPO_PACKAGES[@]}"; do
    if grep -qE "^${pkg//./\\.} " "$PKGLIST"; then
      ok "$pkg có trong pkglist"
    else
      missing "$pkg không có trong pkglist của ISO"
    fi
  done
  # Thêm gói mới không được âm thầm đẩy gói cũ ra khỏi ảnh (ví dụ hết đĩa giữa
  # chừng thì pacstrap vẫn "thành công" với ít gói hơn).
  for pkg in linux-zen hyprland sddm steam pipewire-audio ibus-unikey firefox; do
    grep -qE "^${pkg} " "$PKGLIST" || missing "$pkg biến mất khỏi pkglist"
  done
else
  echo "  (bỏ qua đối chiếu pkglist: không truyền file pkglist)"
fi

# --- 3. Binary người dùng thật sự chạy được ------------------------------
echo "  Binary trong ảnh live:"
for path in "${REQUIRED_FILES[@]}"; do
  if sfs_exists "$path"; then
    ok "$path"
  else
    missing "$path (gói có trong DB mà không để lại binary này?)"
  fi
done

# Báo cáo gói AUR do scripts/anios-aur-build.sh ghi lại: người tải ISO biết bản
# này dựng được những gói AUR nào, phiên bản bao nhiêu.
echo "  Báo cáo gói AUR trong ảnh:"
if sfs_exists usr/share/anios/aur-packages.txt; then
  if sfs_is_regular_file usr/share/anios/aur-packages.txt; then
    report_body="$(sfs_cat_regular usr/share/anios/aur-packages.txt)"
    [[ -n "$report_body" ]] || missing "usr/share/anios/aur-packages.txt rỗng"
    printf '%s\n' "$report_body" | grep -vE '^[[:space:]]*#' | grep -v '^[[:space:]]*$' |
      sed 's/^/    /' || true
    for pkg in "${AUR_PACKAGES[@]}"; do
      printf '%s\n' "$report_body" | grep -qE "^${pkg//./\\.}=" ||
        missing "báo cáo gói AUR không ghi lại $pkg"
    done
  else
    missing "usr/share/anios/aur-packages.txt không phải file thường"
  fi
else
  missing "usr/share/anios/aur-packages.txt (báo cáo gói AUR của lượt dựng)"
fi

# --- 4. Không còn rác của bước dựng gói AUR ------------------------------
echo "  Rác của bước dựng gói AUR:"
for path in "${FORBIDDEN_PATHS[@]}"; do
  if sfs_exists "$path"; then
    missing "$path vẫn nằm trong ảnh live"
  else
    ok "$path đã được dọn"
  fi
done

# Tài khoản dựng gói tạm thời không được có trong /etc/passwd, còn tài khoản live
# `anios` thì phải còn nguyên (bước dọn không được đụng tới nó).
echo "  Tài khoản trong ảnh live:"
if sfs_is_regular_file etc/passwd; then
  passwd_body="$(sfs_cat_regular etc/passwd)"
  if grep -qE '^aniosbuild:' <<<"$passwd_body"; then
    missing "tài khoản dựng gói aniosbuild vẫn còn trong etc/passwd"
  else
    ok "etc/passwd không có tài khoản dựng gói tạm"
  fi
  grep -qE '^anios:' <<<"$passwd_body" || missing "tài khoản live anios biến mất khỏi etc/passwd"
else
  missing "etc/passwd không đọc được như file thường (bước dọn đã làm hỏng?)"
fi

# Không một luật sudo NOPASSWD nào được lọt vào ảnh.
echo "  Quyền sudo trong ảnh live:"
nopasswd_found=0
while IFS= read -r entry; do
  [[ -n "$entry" ]] || continue
  path="etc/sudoers.d/$entry"
  if sfs_is_symlink "$path"; then
    continue # -cat không đọc được symlink tuyệt đối; bỏ qua có chủ đích
  fi
  if sfs_is_regular_file "$path" && sfs_cat_regular "$path" | grep -q 'NOPASSWD'; then
    echo "    NOPASSWD trong $path"
    nopasswd_found=1
  fi
done < <(sfs_children etc/sudoers.d)
if (( nopasswd_found )); then
  missing "có luật sudo NOPASSWD trong ảnh live"
else
  ok "không có luật sudo NOPASSWD nào"
fi
if sfs_exists etc/sudoers.d/10-anios-live; then
  ok "etc/sudoers.d/10-anios-live vẫn còn (sudo của tài khoản live)"
else
  missing "etc/sudoers.d/10-anios-live biến mất khỏi ảnh live"
fi

if (( ERRORS > 0 )); then
  echo "::error::Ảnh live thiếu $ERRORS mục của nhóm gói AUR/python/nodejs/wine" >&2
  exit 1
fi

echo "Ảnh live có đủ yay + gói AUR, python, nodejs, wine và không còn rác dựng gói"
