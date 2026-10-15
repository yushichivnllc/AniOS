#!/usr/bin/env bash
# Dựng và cài các gói AUR vào airootfs ngay trong lúc dựng ISO AniOS.
#
# Script này KHÔNG chạy trên máy host. scripts/build-iso.sh chép nó cùng
# profile/packages.aur.x86_64 vào <profile>/airootfs/root/.anios-aur/ của profile
# dựng tạm, rồi /root/customize_airootfs.sh gọi nó bên trong chroot airootfs.
# mkarchiso chạy hook đó bằng arch-chroot NGAY SAU bước pacstrap và TRƯỚC bước
# sinh pkglist (hàm _build_iso_base của mkarchiso), nhờ vậy:
#
#   * base-devel, git và mọi thư viện mà gói AUR phụ thuộc đã có sẵn trong chroot
#     trước khi makepkg chạy;
#   * gói AUR sau khi cài nằm trong pacman DB của ảnh nên xuất hiện trong
#     /arch/pkglist.x86_64.txt, và `yay -Syu` trong phiên live thấy chúng đúng
#     như mọi gói AUR khác;
#   * không phải khai báo kho pacman cục bộ trong ảnh live (cách đó để lại một
#     repo trỏ tới đường dẫn chỉ tồn tại lúc dựng, làm mọi lệnh pacman của người
#     dùng báo lỗi về sau).
#
# Script KHÔNG dùng sudo và KHÔNG thêm quyền NOPASSWD nào: makepkg chạy dưới một
# tài khoản thường tạm thời (makepkg từ chối chạy bằng root), còn mọi lệnh pacman
# đều do script này chạy với quyền root sẵn có trong chroot. Phụ thuộc của gói
# được đọc từ .SRCINFO (dữ liệu thuần, không thực thi PKGBUILD bằng root) rồi cài
# trước, nên makepkg không cần gọi sudo.
#
# AUR là kho do cộng đồng đóng gói: PKGBUILD có thể đổi, nguồn upstream có thể
# sập. Vì vậy script KHÔNG im lặng bỏ qua gói hỏng — nó ghi rõ nguyên nhân, in gợi
# ý rồi trả exit code khác 0 để bản dựng dừng lại thay vì phát hành ISO thiếu gói.
# Muốn dựng ISO không kèm gói AUR (máy không có mạng, hoặc cần bản dựng nhanh):
#
#     sudo ./scripts/build-iso.sh --no-aur
#
# Biến môi trường có thể ghi đè (chủ yếu phục vụ bài tự kiểm tra
# scripts/selftest-anios-aur-build.sh, chạy được trên máy thường không cần Arch):
#
#   ANIOS_AUR_MANIFEST     danh sách gói AUR      (mặc định /root/.anios-aur/packages.aur.x86_64)
#   ANIOS_AUR_BUILD_USER   tài khoản dựng gói     (mặc định aniosbuild)
#   ANIOS_AUR_BUILD_UID    UID của tài khoản đó   (mặc định 1412)
#   ANIOS_AUR_SRC_DIR      thư mục làm việc       (mặc định /var/tmp/anios-aur-build)
#   ANIOS_AUR_REPORT       báo cáo ghi vào ảnh    (mặc định /usr/share/anios/aur-packages.txt)
#   ANIOS_AUR_ROOT         gốc AUR                (mặc định https://aur.archlinux.org)
#   ANIOS_AUR_GITHUB_MIRROR mirror AUR chỉ-đọc    (mặc định archlinux/aur trên GitHub)
#   ANIOS_AUR_CALAMARES_STAGED_DIR cấu hình Calamares đã stage (mặc định /usr/share/anios/installer/calamares)
#   ANIOS_AUR_PKG_CACHE    cache gói pacman       (mặc định /var/cache/pacman/pkg)
#   ANIOS_AUR_PACMAN_DB    thư mục pacman DB      (mặc định /var/lib/pacman, chỉ dùng để kiểm tra sync DB)
#   ANIOS_AUR_MAKEPKG_OPTS cờ bổ sung cho makepkg (mặc định rỗng)
#   ANIOS_AUR_KEEP_TMP=1   giữ lại thư mục dựng để tự chạy makepkg khi lỗi
#   ANIOS_AUR_KEEP_DEPS=1  không gỡ makedepend mồ côi sau khi dựng xong
#   ANIOS_AUR_RETRIES      số lần thử lại mỗi gói (mặc định 2)
#   ANIOS_AUR_RETRY_DELAY  giây chờ giữa hai lần thử (mặc định 20)
#   ANIOS_AUR_ANNOTATE=1   in ::error::/::warning:: cho GitHub Actions
#                          (tự bật khi GITHUB_ACTIONS=true)
#   ANIOS_AUR_ALLOW_STALE_SUMS=1
#                          chấp nhận dựng tiếp khi PKGBUILD của AUR có sha256sums
#                          lệch với file tải về (upstream đổi file nhưng AUR chưa
#                          cập nhật). Mặc định TẮT: script dừng và báo rõ.
set -Eeuo pipefail

AUR_ROOT="${ANIOS_AUR_ROOT:-https://aur.archlinux.org}"
AUR_GITHUB_MIRROR="${ANIOS_AUR_GITHUB_MIRROR:-https://github.com/archlinux/aur.git}"
CALAMARES_STAGED_DIR="${ANIOS_AUR_CALAMARES_STAGED_DIR:-/usr/share/anios/installer/calamares}"
BUILD_USER="${ANIOS_AUR_BUILD_USER:-aniosbuild}"
BUILD_UID="${ANIOS_AUR_BUILD_UID:-1412}"
SRC_DIR="${ANIOS_AUR_SRC_DIR:-/var/tmp/anios-aur-build}"
MANIFEST="${ANIOS_AUR_MANIFEST:-/root/.anios-aur/packages.aur.x86_64}"
REPORT="${ANIOS_AUR_REPORT:-/usr/share/anios/aur-packages.txt}"
PKG_CACHE="${ANIOS_AUR_PKG_CACHE:-/var/cache/pacman/pkg}"
MAKEPKG_EXTRA_OPTS="${ANIOS_AUR_MAKEPKG_OPTS:-}"
KEEP_TMP="${ANIOS_AUR_KEEP_TMP:-0}"
KEEP_DEPS="${ANIOS_AUR_KEEP_DEPS:-0}"
RETRIES="${ANIOS_AUR_RETRIES:-2}"
RETRY_DELAY="${ANIOS_AUR_RETRY_DELAY:-20}"
ALLOW_STALE_SUMS="${ANIOS_AUR_ALLOW_STALE_SUMS:-0}"
# Chỉ để bài tự kiểm tra trỏ được sang thư mục giả; người dựng không cần đổi.
PACMAN_DB_DIR="${ANIOS_AUR_PACMAN_DB:-/var/lib/pacman}"
LOG="$SRC_DIR/anios-aur-build.log"

# AUR là kho cộng đồng: một PKGBUILD sai checksum, một nguồn upstream bị gỡ hay
# một mirror ốm là chuyện thường ngày, và bản dựng ISO hàng tuần không nên chết
# vì một lần như thế. Vì vậy mỗi gói được thử lại vài lần với PKGBUILD tải mới
# và nguồn tải lại từ đầu, còn lỗi được PHÂN LOẠI để phần tổng kết nói đúng
# nguyên nhân (xem build_failure_class bên dưới).
[[ "$RETRIES" =~ ^[0-9]+$ ]] || { echo "ANIOS_AUR_RETRIES='$RETRIES' không hợp lệ, dùng 2" >&2; RETRIES=2; }
[[ "$RETRY_DELAY" =~ ^[0-9]+$ ]] || { echo "ANIOS_AUR_RETRY_DELAY='$RETRY_DELAY' không hợp lệ, dùng 20" >&2; RETRY_DELAY=20; }

# GitHub Actions đọc dòng "::error ...::thông báo" trong output của bước và biến
# nó thành annotation hiện ngay trên trang run/PR (và đọc được qua API), nên
# người dựng biết gói nào hỏng vì lý do gì mà không phải mở log dài hàng nghìn
# dòng — log CI đôi khi không truy cập được từ nơi khác.
if [[ "${GITHUB_ACTIONS:-}" == "true" || "${ANIOS_AUR_ANNOTATE:-0}" == "1" ]]; then
  ANNOTATE=1
else
  ANNOTATE=0
fi

# releng của archiso không có base-devel lẫn git (xem configs/releng/packages.x86_64),
# mà makepkg bắt buộc phải có chúng. `go` KHÔNG nằm trong danh sách này: nó là
# makedepend của yay, script tự cài lúc dựng rồi gỡ ở bước dọn mồ côi, để ảnh live
# không phình thêm vài trăm MB. Khi người dùng cần dựng gói Go trong phiên live,
# chính yay sẽ tự cài makedepend cho họ.
BUILD_TOOLS=(base-devel git)

# Khởi tạo keyring tạm trong chroot nếu chưa có, để pacman xác thực chữ ký gói
# khi cài công cụ hoặc phụ thuộc (go, v.v.). archiso không copy keyring từ host
# sang airootfs nên nếu không khởi tạo trước thì pacman sẽ báo lỗi
# "keyring is not writable" / "required key missing from keyring".
init_keyring() {
  if (( EUID == 0 )) && [[ ! -d /etc/pacman.d/gnupg/private-keys-v1.d ]]; then
    log "Khởi tạo pacman keyring tạm thời trong chroot..."
    run_logged pacman-key --init || true
    run_logged pacman-key --populate archlinux || true
  fi
}

AUR_OK=()
AUR_FAILED=()
INSTALLED_AS_DEPS=()
# Gói dựng được chỉ nhờ ANIOS_AUR_ALLOW_STALE_SUMS=1 (AUR lệch checksum). Báo cáo
# của ảnh phải nói rõ, để người tải ISO biết gói nào không được xác thực nguồn.
AUR_UNVERIFIED=()
# Lý do hỏng của lượt thử hiện tại / của gói đang dựng (do install_deps và
# build_one điền vào, phần tổng kết đọc lại).
ATTEMPT_REASON=""
ATTEMPT_CLASS=""
BUILD_FAILURE_REASON=""
BUILD_FAILURE_CLASS=""

# --- Tiện ích -------------------------------------------------------------
ts() { date '+%H:%M:%S'; }

log() {
  local line
  line="[$(ts)] $*"
  printf '%s\n' "$line"
  printf '%s\n' "$line" >>"$LOG" 2>/dev/null || true
}

# Thông báo một dòng cho GitHub Actions. Xuống dòng phải mã hoá thành %0A, còn
# '%' thành %25, nếu không annotation sẽ bị cắt và mất phần quan trọng.
annotate_message() {
  local level="$1" title="$2" message="$3" flat
  (( ANNOTATE )) || return 0
  flat="$message"
  flat="${flat//'%'/%25}"
  flat="${flat//$'\r'/%0D}"
  flat="${flat//$'\n'/%0A}"
  printf '::%s title=%s::%s\n' "$level" "$title" "$flat"
}

annotate_error() { annotate_message error "${1:-AniOS AUR}" "${2:-}"; }
annotate_warning() { annotate_message warning "${1:-AniOS AUR}" "${2:-}"; }

die() {
  # Annotation phải gọn một dòng: nội dung đầy đủ vẫn nằm trong khối in ra
  # stderr bên dưới và trong nhật ký 40 dòng cuối.
  annotate_error "AniOS: gói AUR cài sẵn không dựng được" "$*"
  # In nguyên khối ra stderr để log của mkarchiso và của CI giữ được cả gợi ý sửa.
  {
    echo
    echo "=============================================================="
    echo " AniOS: KHÔNG dựng xong các gói AUR cài sẵn"
    echo "=============================================================="
    printf ' %s\n' "$@"
    echo
    echo " Nhật ký: ${LOG:-<không ghi được>}"
    if [[ -n "${LOG:-}" && -s "${LOG:-}" ]]; then
      echo ' 40 dòng cuối:'
      tail -n 40 -- "$LOG" | sed 's/^/   | /'
    fi
    echo
    echo ' Nguyên nhân thường gặp:'
    echo '   * Máy dựng không ra được aur.archlinux.org, GitHub mirror hoặc nguồn upstream (tường lửa, DNS, proxy).'
    echo '   * PKGBUILD trên AUR đã đổi: sha256sums lệch với file tải về, hoặc nguồn upstream (.deb, .jar, git) bị gỡ.'
    echo '   * Phụ thuộc trong kho chính thức không cài được (keyring cũ, mirror ốm, hết dung lượng đĩa).'
    echo
    echo ' Cách xử lý:'
    echo '   * Đọc nhật ký ở trên rồi sửa profile/packages.aur.x86_64.'
    echo '   * Thử lại với nhiều lần thử hơn: export ANIOS_AUR_RETRIES=3'
    echo '   * Dựng ISO không kèm gói AUR: sudo ./scripts/build-iso.sh --no-aur'
    echo '   * Giữ hiện trường để tự chạy makepkg: export ANIOS_AUR_KEEP_TMP=1'
    echo "=============================================================="
  } >&2
  exit 1
}

# --- Phân loại lỗi dựng gói -----------------------------------------------
# `makepkg` chỉ in ra lỗi rồi thoát; đọc lại phần nhật ký của lượt thử vừa rồi để
# biết gói hỏng vì cái gì. Nhờ vậy phần tổng kết (và annotation của GitHub) nói
# được "AUR lệch checksum" khác "không tải được nguồn" khác "dựng hỏng" — mỗi
# loại cần một cách xử lý khác nhau, và người dựng không phải mở log ra tra.
build_failure_class() {
  local from="${1:-0}" slice
  slice="$(tail -n "+$((from + 1))" -- "$LOG" 2>/dev/null || true)"
  [[ -n "$slice" ]] || { printf 'unknown'; return 0; }
  if grep -qF 'did not pass the validity check' <<<"$slice"; then
    printf 'checksum'
  elif grep -qE 'failed to download|Failure while downloading|Could not resolve host|unable to access|curl: \(|Connection (timed out|refused|reset)|TLS|SSL|failed retrieving file|Operation too slow' <<<"$slice"; then
    printf 'download'
  elif grep -qE 'target not found|unable to satisfy dependency|could not satisfy dependencies|invalid or corrupted package|required key missing|invalid PGP signature|signature from .* is unknown' <<<"$slice"; then
    printf 'deps'
  elif grep -qE 'A failure occurred in (build|package|prepare)\(\)|error: failed to build|make: \*\*\*' <<<"$slice"; then
    printf 'build'
  else
    printf 'unknown'
  fi
}

# Câu giải thích ngắn cho từng loại lỗi, dùng chung cho log, báo cáo và annotation.
build_failure_hint() {
  case "${1:-unknown}" in
    checksum)
      printf '%s' 'AUR lệch checksum: sha256sums trong PKGBUILD không khớp file tải về (upstream đổi file hoặc AUR vừa sửa). Chờ AUR cập nhật rồi dựng lại, hoặc tạm chấp nhận bằng ANIOS_AUR_ALLOW_STALE_SUMS=1'
      ;;
    download)
      printf '%s' 'không tải được nguồn (mạng, mirror hoặc upstream đã gỡ file)'
      ;;
    deps)
      printf '%s' 'phụ thuộc trong kho chính thức không cài được (keyring cũ, mirror ốm hoặc hết đĩa)'
      ;;
    build)
      printf '%s' 'makepkg dựng hỏng (PKGBUILD/nguồn upstream đổi so với lúc AniOS kiểm thử)'
      ;;
    *)
      printf '%s' 'makepkg thất bại, chưa khớp mẫu lỗi quen thuộc nào'
      ;;
  esac
}

# Khi PKGBUILD lệch checksum, in ra sha256 thật của nguồn đã tải để người dựng
# biết ngay AUR đang lệch hay file tải về bị cắt cụt.
log_actual_source_sums() {
  local pkgdir="$1" file sum name
  [[ -d "$pkgdir/src" ]] || return 0
  for file in "$pkgdir/src"/*; do
    [[ -f "$file" ]] || continue
    sum="$(sha256sum -- "$file" 2>/dev/null | awk '{print $1}')"
    [[ -n "$sum" ]] || continue
    name="$(basename -- "$file")"
    if grep -qF "$sum" "$pkgdir/PKGBUILD" 2>/dev/null; then
      log "  $name: sha256=$sum (khớp PKGBUILD)"
    else
      log "  $name: sha256=$sum (KHÁC sha256sums trong PKGBUILD — AUR đang lệch)"
    fi
  done
}

# Chạy lệnh, vừa in ra console bản dựng vừa nối vào nhật ký.
run_logged() {
  local status=0
  set +e
  if [[ -n "$LOG" ]]; then
    printf '[%s] $ %s\n' "$(ts)" "$*" >>"$LOG"
    "$@" 2>&1 | tee -a -- "$LOG"
    status=${PIPESTATUS[0]}
  else
    "$@"
    status=$?
  fi
  set -e
  return "$status"
}

# Dọn dẹp khi kết thúc, giữ nguyên exit code của thân script.
cleanup() {
  local status=$? home_dir
  trap - EXIT
  if [[ "$KEEP_TMP" == "1" ]]; then
    log "ANIOS_AUR_KEEP_TMP=1 — giữ lại $SRC_DIR để kiểm tra"
    return "$status"
  fi
  log "Dọn tàn dư dựng gói AUR khỏi ảnh live"
  if (( EUID == 0 )); then
    home_dir="$(getent passwd "$BUILD_USER" 2>/dev/null | cut -d: -f6 || true)"
    userdel "$BUILD_USER" >/dev/null 2>&1 || true
    groupdel "$BUILD_USER" >/dev/null 2>&1 || true
    # Home của tài khoản dựng gói nằm trong SRC_DIR; chỉ xoá riêng khi ai đó
    # trỏ nó ra chỗ khác.
    if [[ -n "$home_dir" && "$home_dir" != / && "$home_dir" != "$SRC_DIR"* ]]; then
      rm -rf -- "$home_dir"
    fi
    # pacman-init.service sẽ khởi tạo lại keyring sạch trên tmpfs khi boot ISO
    # live; dọn keyring tạm sinh lúc build để không để lộ private master key và
    # tránh xung đột với mount tmpfs của releng.
    pkill -KILL -u 0 gpg-agent 2>/dev/null || true
    rm -rf -- /etc/pacman.d/gnupg
  fi
  if [[ -n "$SRC_DIR" && "$SRC_DIR" != / && "$SRC_DIR" != /var && "$SRC_DIR" != /var/tmp ]]; then
    rm -rf -- "$SRC_DIR"
  fi
  # mkarchiso cũng xoá /var/tmp và cache pacman ở bước _cleanup_pacstrap_dir;
  # dọn ở đây để log bản dựng nói rõ ảnh không còn rác dựng gói.
  if [[ -d "$PKG_CACHE" ]]; then
    find "$PKG_CACHE" -maxdepth 1 -type f -delete 2>/dev/null || true
  fi
  return "$status"
}

# --- Đọc manifest ---------------------------------------------------------
# Điền hai mảng AUR_PKGBASES (tên package base) và AUR_SPECS (đúng dòng trong
# manifest, có thể kèm "=phiên bản").
#
# Phải đọc thẳng vào biến toàn cục, KHÔNG qua `mapfile < <(read_manifest ...)`:
# process substitution chạy trong shell con nên `die` bên trong đó chỉ kết thúc
# shell con, còn script cha vẫn đi tiếp với danh sách rỗng và báo "không có gì để
# dựng" — một tên gói sai sẽ âm thầm biến thành ISO thiếu gói AUR.
AUR_PKGBASES=()
AUR_SPECS=()
parse_manifest() {
  local file="$1" line spec pkg
  AUR_PKGBASES=()
  AUR_SPECS=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%$'\r'}"
    line="${line%%#*}"                      # bỏ comment
    line="${line#"${line%%[![:space:]]*}"}" # xén khoảng trắng đầu dòng
    line="${line%"${line##*[![:space:]]}"}" # xén khoảng trắng cuối dòng
    [[ -n "$line" ]] || continue
    spec="$line"
    pkg="${spec%%=*}"
    if [[ ! "$pkg" =~ ^[A-Za-z0-9@._+-]+$ ]]; then
      die "Tên gói AUR không hợp lệ trong $file: '$spec'" \
        "Tên gói chỉ được chứa chữ cái, số và các ký tự @ . _ + -"
    fi
    AUR_PKGBASES+=("$pkg")
    AUR_SPECS+=("$spec")
  done <"$file"
}

# --- Đọc phụ thuộc từ SRCINFO (không thực thi PKGBUILD bằng root) ----------
# $1: thư mục gói. In ra mỗi dòng một phụ thuộc, giữ nguyên ràng buộc phiên bản.
srcinfo_deps() {
  local pkgdir="$1" generated srcinfo
  srcinfo="$pkgdir/.SRCINFO"
  if [[ ! -s "$srcinfo" ]]; then
    # Gói không có .SRCINFO (hiếm, AUR bắt buộc khi submit): để makepkg tự in
    # SRCINFO dưới tài khoản thường, vẫn không chạy PKGBUILD bằng root.
    generated="$(
      cd "$pkgdir" &&
        run_as_builder env "HOME=$SRC_DIR/home" makepkg --printsrcinfo 2>>"$LOG"
    )" || generated=""
    [[ -n "$generated" ]] || return 1
    printf '%s\n' "$generated" >"$pkgdir/.SRCINFO.anios"
    srcinfo="$pkgdir/.SRCINFO.anios"
  fi
  # Chỉ depends/makedepends chung và x86_64: makepkg chạy --nocheck,
  # không cần checkdepends hay thư viện cho i686. Giữ phiên bản để
  # pacman -T không coi một thư viện quá cũ là đã thoả phụ thuộc.
  sed -n -E \
    -e 's/^[[:space:]]*(make)?depends(_(x86_64))?[[:space:]]*=[[:space:]]*(.+)$/\4/p' \
    -- "$srcinfo" |
    sed -E -e 's/[[:space:]]+$//' |
    awk 'NF && !seen[$0]++'
}

# pacman -T in ra những phụ thuộc CHƯA được thoả (kể cả kiểm tra provides),
# nên java-runtime của legacy-launcher không bị coi là thiếu khi jre-openjdk
# đã nằm trong ảnh.
unsatisfied_deps() {
  local -a deps=("$@")
  (( ${#deps[@]} > 0 )) || return 0
  pacman -T "${deps[@]}" 2>>"$LOG" || true
}

dep_is_resolvable() {
  pacman -Sp --noconfirm -- "$1" >/dev/null 2>&1
}

# Cài các phụ thuộc còn thiếu bằng quyền root, đánh dấu --asdeps để bước dọn mồ
# côi cuối script gỡ được những makedepend chỉ cần lúc dựng (ví dụ `go` của yay).
#
# Hỏng ở đây KHÔNG gọi die ngay: gói này được ghi vào AUR_FAILED rồi vòng lặp đi
# tiếp, để phần tổng kết nói được đủ "gói nào hỏng vì cái gì" trong một lượt dựng
# thay vì bắt người dựng sửa từng gói một. Bản dựng vẫn dừng ở cuối script.
install_deps() {
  local pkg="$1" dep
  local -a all=() missing=() wanted=() skipped=()
  ATTEMPT_REASON=""
  mapfile -t all < <(srcinfo_deps "$SRC_DIR/src/$pkg" || true)
  if (( ${#all[@]} == 0 )); then
    log "$pkg: không đọc được phụ thuộc từ SRCINFO — makepkg sẽ tự kiểm tra"
    return 0
  fi
  mapfile -t missing < <(unsatisfied_deps "${all[@]}")
  for dep in ${missing[@]+"${missing[@]}"}; do
    [[ -n "$dep" ]] || continue
    if dep_is_resolvable "$dep"; then
      wanted+=("$dep")
    else
      skipped+=("$dep")
    fi
  done
  if (( ${#skipped[@]} > 0 )); then
    log "$pkg: không phân giải được phụ thuộc trong kho chính thức: ${skipped[*]}"
    log "$pkg: kiểm tra phiên bản kho hoặc dựng/cài phụ thuộc AUR trước gói này."
    ATTEMPT_REASON="không phân giải được phụ thuộc: ${skipped[*]}"
    ATTEMPT_CLASS=deps
    # Mã 3 = hỏng vĩnh viễn với lượt dựng này (thử lại cũng vậy), khác mã 1 =
    # lỗi có thể do mirror/keyring nên đáng thử lại.
    return 3
  fi
  if (( ${#wanted[@]} == 0 )); then
    log "$pkg: đã đủ phụ thuộc"
    return 0
  fi
  log "$pkg: cài phụ thuộc ${wanted[*]}"
  # Không -Sy ở lần đầu: cùng lý do với bước cài công cụ dựng gói ở trên (giữ cả
  # ảnh ở MỘT snapshot kho, tránh partial upgrade).
  if ! run_logged pacman -S --noconfirm --needed --asdeps -- "${wanted[@]}"; then
    # Hai nguyên nhân thật của "không cài được phụ thuộc" là keyring cũ (gói mới
    # ký bằng khoá chưa có trong chroot) và sync DB cũ/mirror vừa đồng bộ. Cả hai
    # đều chữa được tại chỗ, nên làm mới rồi thử lại đúng một lần trước khi kết
    # luận gói này hỏng — bản dựng ISO hàng tuần không nên chết vì chuyện đó.
    log "$pkg: cài phụ thuộc thất bại — làm mới keyring và sync DB rồi thử lại"
    run_logged pacman-key --populate archlinux || true
    run_logged pacman -Sy --noconfirm --needed archlinux-keyring || true
    run_logged pacman -Sy --noconfirm || true
    if ! run_logged pacman -S --noconfirm --needed --asdeps -- "${wanted[@]}"; then
      ATTEMPT_REASON="không cài được phụ thuộc: ${wanted[*]}"
      ATTEMPT_CLASS=deps
      return 1
    fi
  fi
  for dep in "${wanted[@]}"; do
    INSTALLED_AS_DEPS+=("${dep%%[<>=]*}")
  done
}

# --- Chạy makepkg dưới tài khoản thường -----------------------------------
run_as_builder() {
  if (( EUID != 0 )); then
    # Bài tự kiểm tra chạy script bằng tài khoản thường: không cần hạ quyền.
    "$@"
    return $?
  fi
  if command -v runuser >/dev/null 2>&1; then
    runuser --user "$BUILD_USER" -- "$@"
  elif command -v setpriv >/dev/null 2>&1; then
    setpriv --reap --init-groups \
      --uid "$(id -u "$BUILD_USER")" --gid "$(id -g "$BUILD_USER")" -- "$@"
  else
    die "Thiếu cả runuser lẫn setpriv (gói util-linux) nên không hạ quyền xuống $BUILD_USER được."
  fi
}

run_makepkg() {
  # Không đặt BUILDDIR: makepkg lấy thư mục hiện tại làm startdir, nên chỉ cần
  # cd vào thư mục gói (build_one làm việc đó) là file .pkg.tar sinh ra nằm ngay
  # trong $SRC_DIR/src/<gói>, đúng chỗ script tìm để pacman -U.
  run_logged run_as_builder \
    env "HOME=$SRC_DIR/home" "TMPDIR=$BUILD_TMPDIR" "PATH=$PATH" \
    makepkg "$@"
}

# Bật module packagechooser mà AniOS dùng trong giao diện cài đặt. PKGBUILD
# calamares trên AUR hiện bỏ module này khỏi build, dù cấu hình của AniOS gọi nó.
# Chỉ gỡ đúng dòng trong danh sách skip; packagechooserq vẫn được tắt vì AniOS
# dùng module Widgets cổ điển `packagechooser`, không dùng biến thể Qt Quick.
enable_calamares_packagechooser() {
  local pkgbuild="$1"
  [[ -s "$pkgbuild" ]] || {
    log "Calamares không có PKGBUILD để bật packagechooser: $pkgbuild"
    return 1
  }
  if grep -Eq '^[[:space:]]*packagechooser[[:space:]]*(#.*)?$' "$pkgbuild"; then
    sed -i -E '/^[[:space:]]*packagechooser[[:space:]]*(#.*)?$/d' "$pkgbuild" || return 1
    log "Calamares: đã bật packagechooser bằng cách bỏ module khỏi danh sách skip của PKGBUILD AUR"
  fi
  if grep -Eq '^[[:space:]]*packagechooser[[:space:]]*(#.*)?$' "$pkgbuild"; then
    log "Calamares: PKGBUILD vẫn bỏ qua module packagechooser sau khi chuẩn bị"
    return 1
  fi
  return 0
}

# --- Tải PKGBUILD từ AUR --------------------------------------------------
# Ưu tiên git AUR; nếu host AUR lỗi TLS/Anubis thì thử mirror GitHub chính thức,
# mỗi package nằm trên một branch riêng. Snapshot cgit là phương án cuối cùng.
fetch_aur() {
  local pkg="$1"
  local dest="$SRC_DIR/src/$pkg"
  local tmp_tar="$SRC_DIR/$pkg.tar.gz"
  rm -rf -- "$dest" "$tmp_tar"
  if run_logged git clone --quiet --depth 1 -- "$AUR_ROOT/$pkg.git" "$dest"; then
    if [[ -s "$dest/PKGBUILD" ]]; then
      return 0
    fi
    log "Clone $pkg không chứa PKGBUILD"
  else
    log "git clone $AUR_ROOT/$pkg.git thất bại — thử mirror GitHub của AUR"
  fi

  rm -rf -- "$dest"
  if [[ -n "$AUR_GITHUB_MIRROR" ]]; then
    if run_logged git clone --quiet --depth 1 --single-branch --branch "$pkg" -- \
      "$AUR_GITHUB_MIRROR" "$dest"; then
      if [[ -s "$dest/PKGBUILD" ]]; then
        log "$pkg: tải PKGBUILD từ mirror GitHub chính thức của AUR"
        return 0
      fi
      log "Mirror GitHub clone $pkg không chứa PKGBUILD"
    else
      log "Mirror GitHub không tải được $pkg — thử snapshot cgit AUR"
    fi
  fi

  rm -rf -- "$dest"
  run_logged curl -fL --retry 3 --retry-delay 5 --connect-timeout 30 \
    -o "$tmp_tar" "$AUR_ROOT/cgit/aur.git/snapshot/$pkg.tar.gz" || return 1
  tar -xzf "$tmp_tar" -C "$SRC_DIR/src" || return 1
  rm -f -- "$tmp_tar"
  [[ -s "$dest/PKGBUILD" ]]
}

build_one() {
  local pkg="$1" attempt total=$((RETRIES + 1)) pkgfile build_status
  local log_offset attempt_class attempt_reason stale_sums_retryed=0
  BUILD_FAILURE_REASON=""
  BUILD_FAILURE_CLASS=""
  for ((attempt = 1; attempt <= total; attempt++)); do
    if (( attempt > 1 )); then
      log "Thử lại $pkg (lần $attempt/$total, chờ ${RETRY_DELAY}s)"
      sleep "$RETRY_DELAY"
      # PKGBUILD được tải lại từ đầu ở mỗi lượt (fetch_aur xoá cả thư mục gói),
      # nên nguồn tải hỏng/cắt cụt của lượt trước không bị dùng lại.
      run_logged pacman -Sy >/dev/null 2>&1 || true
    fi
    if ! fetch_aur "$pkg"; then
      log "Không lấy được PKGBUILD của $pkg từ AUR"
      BUILD_FAILURE_CLASS=download
      BUILD_FAILURE_REASON="không tải được PKGBUILD từ AUR, mirror GitHub và snapshot"
      continue
    fi
    if [[ "$pkg" == calamares ]] &&
      ! enable_calamares_packagechooser "$SRC_DIR/src/$pkg/PKGBUILD"; then
      log "Không thể bật module packagechooser bắt buộc trong PKGBUILD calamares"
      BUILD_FAILURE_CLASS=build
      BUILD_FAILURE_REASON="không bật được module packagechooser trong PKGBUILD calamares"
      return 1
    fi
    # Chuyển quyền trước khi đọc phụ thuộc: nhánh dự phòng của srcinfo_deps chạy
    # `makepkg --printsrcinfo` dưới tài khoản dựng gói, cần thư mục ghi được.
    if (( EUID == 0 )); then
      chown -R -- "$BUILDER_UID:$BUILDER_GID" "$SRC_DIR/src/$pkg" "$SRC_DIR/home"
    fi
    ATTEMPT_REASON=""
    ATTEMPT_CLASS=""
    dep_status=0
    install_deps "$pkg" || dep_status=$?
    if (( dep_status != 0 )); then
      BUILD_FAILURE_CLASS="${ATTEMPT_CLASS:-deps}"
      BUILD_FAILURE_REASON="${ATTEMPT_REASON:-không cài được phụ thuộc}"
      if (( dep_status == 3 )); then
        log "$pkg: phụ thuộc không phân giải được — không thử lại (lượt sau cũng vậy)"
        return 1
      fi
      continue
    fi
    # Cờ của makepkg:
    #   -f         work dir dùng lại không khiến makepkg bỏ qua gói đã dựng
    #   --nocheck  bỏ qua check(): bộ test của gói AUR thường cần mạng và
    #              checkdepends riêng, không đáng để đánh đổi cả bản dựng ISO
    #   KHÔNG -s / -i / -r: phụ thuộc do script cài bằng quyền root ở trên, còn
    #              việc cài gói cũng do root làm (pacman -U) nên tài khoản dựng
    #              gói không cần sudo và ảnh không cần quyền NOPASSWD nào
    log_offset="$(wc -l <"$LOG" 2>/dev/null || echo 0)"
    build_status=0
    # shellcheck disable=SC2086
    (cd "$SRC_DIR/src/$pkg" && run_makepkg -f --noconfirm --nocheck $MAKEPKG_EXTRA_OPTS) ||
      build_status=$?
    if (( build_status != 0 )); then
      attempt_class="$(build_failure_class "$log_offset")"
      attempt_reason="makepkg thất bại (exit $build_status)"
      log "makepkg thất bại với $pkg (exit $build_status; lỗi: $attempt_class)"
      if [[ "$attempt_class" == checksum ]]; then
        log "$pkg: sha256sums trong PKGBUILD không khớp nguồn tải về — đối chiếu:"
        log_actual_source_sums "$SRC_DIR/src/$pkg"
        if [[ "$ALLOW_STALE_SUMS" == "1" ]]; then
          # Lối thoát có chủ đích (mặc định TẮT): upstream đổi file cùng phiên
          # bản mà AUR chưa kịp sửa sha256sums. Chỉ bỏ qua phần kiểm tra checksum
          # của CHÍNH gói này, và ghi lại rõ trong báo cáo của ảnh.
          log "$pkg: ANIOS_AUR_ALLOW_STALE_SUMS=1 — dựng lại, bỏ kiểm tra checksum nguồn"
          stale_sums_retryed=1
          build_status=0
          (cd "$SRC_DIR/src/$pkg" && run_makepkg -f --noconfirm --nocheck --skipchecksums $MAKEPKG_EXTRA_OPTS) ||
            build_status=$?
          if (( build_status == 0 )); then
            log "$pkg: dựng xong KHÔNG kiểm tra checksum nguồn (AUR đang lệch)"
            BUILD_FAILURE_CLASS=""
            BUILD_FAILURE_REASON=""
          else
            log "makepkg vẫn thất bại với $pkg dù đã bỏ kiểm tra checksum (exit $build_status)"
            BUILD_FAILURE_CLASS=build
            BUILD_FAILURE_REASON="makepkg thất bại cả khi bỏ kiểm tra checksum (exit $build_status)"
            continue
          fi
        fi
      fi
      if (( build_status != 0 )); then
        BUILD_FAILURE_CLASS="$attempt_class"
        BUILD_FAILURE_REASON="$attempt_reason ($(build_failure_hint "$attempt_class"))"
        continue
      fi
    fi
    pkgfile="$(find "$SRC_DIR/src/$pkg" -maxdepth 1 -name "$pkg-*.pkg.tar*" | sort | sed -n '1p')"
    if [[ -z "$pkgfile" ]]; then
      # Gói split: lấy file .pkg.tar đầu tiên có trong thư mục.
      pkgfile="$(find "$SRC_DIR/src/$pkg" -maxdepth 1 -name '*.pkg.tar*' | sort | sed -n '1p')"
    fi
    if [[ -z "$pkgfile" ]]; then
      log "makepkg xong nhưng không tìm thấy file .pkg.tar của $pkg"
      BUILD_FAILURE_CLASS=build
      BUILD_FAILURE_REASON="makepkg báo xong nhưng không sinh file gói"
      continue
    fi
    log "$pkg: cài $(basename -- "$pkgfile") vào airootfs"
    if run_logged pacman -U --noconfirm --asexplicit -- "$pkgfile"; then
      if (( stale_sums_retryed )); then
        # Báo cáo của ảnh phải nói rõ gói này được dựng khi AUR lệch checksum.
        AUR_UNVERIFIED+=("$pkg")
      fi
      return 0
    fi
    log "pacman -U thất bại với $pkgfile"
    BUILD_FAILURE_CLASS=deps
    BUILD_FAILURE_REASON="không cài được gói đã dựng bằng pacman -U"
  done
  return 1
}

# --- Gỡ makedepend mồ côi -------------------------------------------------
# Những gói script cài bằng --asdeps mà sau khi dựng không còn gói nào cần (điển
# hình là `go` của yay) sẽ thành mồ côi. Gỡ chúng để ảnh live không gánh vài trăm
# MB công cụ chỉ dùng lúc dựng. base-devel/git/python/nodejs/wine... đều được cài
# "explicit" từ packages.x86_64 nên pacman không đụng tới.
remove_orphan_build_deps() {
  local -a orphans=() dep
  if [[ "$KEEP_DEPS" == "1" ]]; then
    log "ANIOS_AUR_KEEP_DEPS=1 — giữ lại makedepend"
    return 0
  fi
  # Chỉ xét những gói CHÍNH script này cài bằng --asdeps, giao với danh sách mồ
  # côi của pacman: nhờ vậy không bao giờ gỡ nhầm gói mà ảnh live cần nhưng tình
  # cờ cũng ở trạng thái mồ côi.
  for dep in ${INSTALLED_AS_DEPS[@]+"${INSTALLED_AS_DEPS[@]}"}; do
    if pacman -Qdtq 2>/dev/null | grep -xF "$dep" >/dev/null; then
      orphans+=("$dep")
    fi
  done
  if (( ${#orphans[@]} == 0 )); then
    log "Không có makedepend mồ côi nào để gỡ"
    return 0
  fi
  log "Gỡ ${#orphans[@]} gói chỉ cần lúc dựng: ${orphans[*]}"
  run_logged pacman -Rns --noconfirm -- "${orphans[@]}" ||
    log "Cảnh báo: không gỡ được makedepend mồ côi (ảnh sẽ nặng hơn một chút)"
}

# Copy the AniOS Calamares configuration only after the stable package has been
# installed. Keeping it staged under /usr/share/anios avoids pacman file clashes.
install_calamares_configuration() {
  local staged="$CALAMARES_STAGED_DIR" module_file failure
  [[ -d "$staged" ]] || return 0 # `--no-aur` deliberately omits the installer.
  if ! pacman -Q calamares >/dev/null 2>&1; then
    # The package loop already records the primary AUR download/build error. Do
    # not replace it with a secondary "Calamares is not installed" diagnostic.
    for failure in ${AUR_FAILED[@]+"${AUR_FAILED[@]}"}; do
      if [[ "${failure%% *}" == calamares ]]; then
        log "Bỏ qua kiểm tra packagechooser: gói calamares đã thất bại trước đó; sẽ báo lỗi AUR gốc ở phần tổng kết."
        return 0
      fi
    done
    die "Calamares configuration was staged but the stable calamares package is not installed." \
      "Keep calamares in profile/packages.aur.x86_64 or build with --no-aur to omit the installer."
  fi
  module_file="$(find /usr/lib/calamares/modules -type f -iname '*packagechooser*' -print -quit 2>/dev/null || true)"
  [[ -n "$module_file" ]] ||
    die "The stable Calamares package does not provide its packagechooser module." \
      "AniOS needs packagechooser to save the GRUB, SDDM and dotfiles choices."
  for config in \
    settings.conf \
    modules/packagechooser-grub.conf \
    modules/packagechooser-sddm.conf \
    modules/packagechooser-dotfiles.conf \
    modules/shellprocess-anios-pacstrap.conf \
    modules/shellprocess-anios-skel.conf \
    modules/shellprocess-anios-finalize.conf \
    branding/anios/branding.desc; do
    [[ -s "$staged/$config" ]] || die "Missing AniOS Calamares configuration: $staged/$config"
  done
  install -d -m 0755 -- /etc/calamares
  cp -a -- "$staged/." /etc/calamares/
  log "Installed AniOS Calamares config; packagechooser plugin: $module_file"
}

# --- Chuẩn bị -------------------------------------------------------------
[[ -s "$MANIFEST" ]] ||
  die "Không tìm thấy danh sách gói AUR: $MANIFEST" \
    "scripts/build-iso.sh phải chép profile/packages.aur.x86_64 vào airootfs/root/.anios-aur/."

install -d -m 0755 -- "$SRC_DIR/src" "$SRC_DIR/home"
: >"$LOG"
trap cleanup EXIT

parse_manifest "$MANIFEST"
if (( ${#AUR_PKGBASES[@]} == 0 )); then
  log "Danh sách AUR rỗng ($MANIFEST) — không có gì để dựng."
  exit 0
fi

log "AniOS: dựng ${#AUR_PKGBASES[@]} gói AUR vào ảnh live: ${AUR_SPECS[*]}"

init_keyring

# Cố tình KHÔNG dùng -Sy ở đường thường: pacstrap vừa điền sync DB vài phút
# trước, nên cài thẳng bằng DB đó giữ cho cả ảnh ở MỘT snapshot kho. -Sy giữa
# chừng sẽ kéo bản mới hơn cho riêng base-devel/git và đẩy ảnh vào trạng thái
# "partial upgrade" (pacman cảnh báo đúng điều này). Chỉ khi DB sẵn có không cài
# được (mirrorlist trống, keyring hết hạn) mới đồng bộ lại rồi thử lần hai.
log "Cài công cụ dựng gói: ${BUILD_TOOLS[*]}"
if ! run_logged pacman -S --needed --noconfirm -- "${BUILD_TOOLS[@]}"; then
  log "DB sẵn có không cài được ${BUILD_TOOLS[*]}; đồng bộ lại kho và keyring rồi thử lại"
  run_logged pacman -Sy --noconfirm --needed archlinux-keyring || true
  run_logged pacman -Sy --needed --noconfirm -- "${BUILD_TOOLS[@]}" ||
    die "Không cài được công cụ dựng gói (${BUILD_TOOLS[*]}) bên trong airootfs." \
      "Kiểm tra mirrorlist và đường mạng của máy dựng ISO."
fi
for tool in makepkg git curl tar; do
  command -v "$tool" >/dev/null 2>&1 ||
    die "Thiếu lệnh '$tool' trong airootfs sau khi cài ${BUILD_TOOLS[*]}."
done

# makepkg từ chối chạy bằng root nên phải có tài khoản thường trong chroot.
# UID 1412 không đụng UID nào của hệ live (tài khoản anios là 1000). Tài khoản
# này bị xoá ở bước cleanup, không bao giờ nằm trong ảnh cuối.
if (( EUID == 0 )); then
  if ! id -u "$BUILD_USER" >/dev/null 2>&1; then
    groupadd --system "$BUILD_USER" 2>/dev/null || true
    useradd --system --uid "$BUILD_UID" --gid "$BUILD_USER" \
      --home-dir "$SRC_DIR/home" --create-home --shell /bin/bash \
      --comment "AniOS AUR build account (removed after the ISO build)" \
      "$BUILD_USER" ||
      die "Không tạo được tài khoản dựng gói '$BUILD_USER' trong airootfs."
  fi
  BUILDER_UID="$(id -u "$BUILD_USER")"
  BUILDER_GID="$(id -g "$BUILD_USER")"
  install -d -m 0700 -o "$BUILDER_UID" -g "$BUILDER_GID" -- "$SRC_DIR/home"
  install -d -m 0755 -o "$BUILDER_UID" -g "$BUILDER_GID" -- "$SRC_DIR/src"
fi

# Vài hệ treo /tmp với noexec làm backend của fakeroot chết. Chỉ khi đó mới dời
# TMPDIR vào thư mục dựng (vẫn nằm trong airootfs và vẫn bị dọn ở cuối).
tmp_flags="$(findmnt -no OPTIONS --target /tmp 2>/dev/null || true)"
if [[ "$tmp_flags" == *noexec* ]]; then
  install -d -m 1777 -- "$SRC_DIR/tmp"
  BUILD_TMPDIR="$SRC_DIR/tmp"
  log "/tmp của airootfs là noexec — dùng TMPDIR=$BUILD_TMPDIR cho makepkg"
else
  BUILD_TMPDIR="${TMPDIR:-/tmp}"
fi

# --- Kiểm tra sơ bộ trước khi dựng ----------------------------------------
# Dựng gói AUR cần tải nguồn lớn (AppImage/.deb vài trăm MB) rồi giải nén; hết
# đĩa là nguyên nhân âm thầm khiến `pacman -S` và makepkg hỏng giữa chừng. Nói
# trước cho người dựng biết thay vì để họ đoán từ một lỗi tải file.
avail_kib="$(df -Pk -- "$SRC_DIR" 2>/dev/null | awk 'NR==2 {print $4}')"
if [[ "$avail_kib" =~ ^[0-9]+$ ]]; then
  log "Chỗ trống cho bước dựng gói AUR: $((avail_kib / 1024 / 1024)) GiB"
  if (( avail_kib < 6 * 1024 * 1024 )); then
    log "CẢNH BÁO: còn ít hơn 6 GiB — bước dựng gói AUR có thể hỏng vì hết đĩa."
    annotate_warning "AniOS: ít chỗ trống cho bước dựng gói AUR" \
      "chỉ còn $((avail_kib / 1024 / 1024)) GiB trong airootfs; cần khoảng 6 GiB"
  fi
fi
if ! ls "$PACMAN_DB_DIR"/sync/*.db >/dev/null 2>&1; then
  log "CẢNH BÁO: sync DB của pacman trống — phụ thuộc sẽ không phân giải được."
  annotate_warning "AniOS: pacman chưa có sync DB trong airootfs" \
    "bước pacstrap có thể chưa hoàn tất; mọi phụ thuộc AUR sẽ không phân giải được"
fi

# --- Dựng từng gói --------------------------------------------------------
for index in "${!AUR_PKGBASES[@]}"; do
  pkg="${AUR_PKGBASES[$index]}"
  spec="${AUR_SPECS[$index]}"
  log "=== [$((index + 1))/${#AUR_PKGBASES[@]}] $spec ==="
  if pacman -Q "$pkg" >/dev/null 2>&1; then
    log "$pkg đã có sẵn trong ảnh — bỏ qua"
    AUR_OK+=("$pkg")
    continue
  fi
  if build_one "$pkg"; then
    if ! pacman -Q "$pkg" >/dev/null 2>&1; then
      log "makepkg báo xong nhưng pacman không thấy $pkg trong airootfs"
      AUR_FAILED+=("$pkg (cài xong mà pacman không nhận)")
      annotate_error "Gói AUR $pkg" "makepkg báo xong nhưng pacman không thấy gói trong airootfs"
      continue
    fi
    log "$pkg $(pacman -Q "$pkg" | awk '{print $2}') đã cài vào ảnh live"
    AUR_OK+=("$pkg")
  else
    # Lý do đã được phân loại trong build_one; nêu thẳng trong log, trong phần
    # tổng kết và trong annotation của GitHub để không phải mở nhật ký dài.
    failure_class="${BUILD_FAILURE_CLASS:-unknown}"
    failure_reason="${BUILD_FAILURE_REASON:-$(build_failure_hint "$failure_class")}"
    log "$pkg: dựng thất bại [$failure_class] — $failure_reason"
    AUR_FAILED+=("$pkg (dựng thất bại [$failure_class] — $failure_reason)")
    annotate_error "Gói AUR $pkg không dựng được" "$failure_class: $failure_reason"
  fi
done

remove_orphan_build_deps
install_calamares_configuration

# --- Báo cáo gói AUR có trong ảnh (để đối chiếu về sau) -------------------
if [[ -n "$REPORT" ]]; then
  report_tmp="$SRC_DIR/aur-report.txt"
  {
    printf '%s\n' "# Gói AUR được dựng và cài sẵn trong ảnh live AniOS này."
    printf '%s\n' "# Sinh lúc dựng ISO bởi scripts/anios-aur-build.sh (chạy trong chroot airootfs)."
    printf '%s\n' "# Chỉ là bản ghi để đối chiếu; pacman DB của ảnh mới là nguồn sự thật."
    printf '%s\n' "#"
    printf '%s\n' "# Trong phiên live, cài/cập nhật cả kho chính thức lẫn AUR bằng: yay -Syu"
    printf '%s\n' "#"
    for pkg in ${AUR_OK[@]+"${AUR_OK[@]}"}; do
      printf '%s=%s\n' "$pkg" "$(pacman -Q "$pkg" 2>/dev/null | awk '{print $2}')"
    done
    if (( ${#AUR_OK[@]} == 0 )); then
      printf '%s\n' "# (không có gói AUR nào được cài)"
    fi
    for pkg in ${AUR_UNVERIFIED[@]+"${AUR_UNVERIFIED[@]}"}; do
      printf '%s\n' "# CHÚ Ý: $pkg được dựng với ANIOS_AUR_ALLOW_STALE_SUMS=1 (sha256sums của AUR lệch nguồn tải về)."
    done
    for reason in ${AUR_FAILED[@]+"${AUR_FAILED[@]}"}; do
      printf '%s\n' "# THẤT BẠI: $reason"
    done
  } >"$report_tmp"
  install -d -m 0755 -- "$(dirname -- "$REPORT")"
  install -m 0644 -- "$report_tmp" "$REPORT"
  log "Đã ghi báo cáo gói AUR vào $REPORT"
fi

# --- Kết luận -------------------------------------------------------------
# Không gọi die ngay ở gói đầu tiên hỏng: chạy hết vòng lặp rồi mới kết luận để
# một lượt dựng (và một annotation của GitHub) nói được đủ gói nào hỏng vì cái gì.
if (( ${#AUR_FAILED[@]} > 0 )); then
  log "Xong với lỗi: ${#AUR_OK[@]} gói cài được, ${#AUR_FAILED[@]} gói hỏng"
  for reason in "${AUR_FAILED[@]}"; do
    log "  * $reason"
  done
  annotate_error "AniOS: ${#AUR_FAILED[@]} gói AUR không dựng được" "${AUR_FAILED[*]}"
  die "Các gói AUR sau không dựng được: ${AUR_FAILED[*]}"
fi

log "Hoàn tất: ${AUR_OK[*]}"
exit 0
