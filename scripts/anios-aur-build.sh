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
#   ANIOS_AUR_MAKEPKG_OPTS cờ bổ sung cho makepkg (mặc định rỗng)
#   ANIOS_AUR_KEEP_TMP=1   giữ lại thư mục dựng để tự chạy makepkg khi lỗi
#   ANIOS_AUR_KEEP_DEPS=1  không gỡ makedepend mồ côi sau khi dựng xong
#   ANIOS_AUR_RETRIES      số lần thử lại mỗi gói (mặc định 1)
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
RETRIES="${ANIOS_AUR_RETRIES:-1}"
LOG="$SRC_DIR/anios-aur-build.log"

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

# --- Tiện ích -------------------------------------------------------------
ts() { date '+%H:%M:%S'; }

log() {
  local line="[$(ts)] $*"
  printf '%s\n' "$line"
  printf '%s\n' "$line" >>"$LOG" 2>/dev/null || true
}

die() {
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
    echo '   * PKGBUILD trên AUR đã đổi, hoặc nguồn upstream (.deb, .jar, git) bị gỡ.'
    echo '   * Hết dung lượng đĩa khi makepkg tải và giải nén nguồn.'
    echo
    echo ' Cách xử lý:'
    echo '   * Đọc nhật ký ở trên rồi sửa profile/packages.aur.x86_64.'
    echo '   * Dựng ISO không kèm gói AUR: sudo ./scripts/build-iso.sh --no-aur'
    echo '   * Giữ hiện trường để tự chạy makepkg: export ANIOS_AUR_KEEP_TMP=1'
    echo "=============================================================="
  } >&2
  exit 1
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
install_deps() {
  local pkg="$1" dep
  local -a all=() missing=() wanted=() skipped=()
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
    return 1
  fi
  if (( ${#wanted[@]} == 0 )); then
    log "$pkg: đã đủ phụ thuộc"
    return 0
  fi
  log "$pkg: cài phụ thuộc ${wanted[*]}"
  # Không -Sy: cùng lý do với bước cài công cụ dựng gói ở trên.
  run_logged pacman -S --noconfirm --needed --asdeps -- "${wanted[@]}" ||
    die "Không cài được phụ thuộc của $pkg: ${wanted[*]}" \
      "Thử lại sau (mirror có thể đang lỗi), hoặc bỏ gói này khỏi profile/packages.aur.x86_64."
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
  local pkg="$1" dest="$SRC_DIR/src/$pkg" tmp_tar="$SRC_DIR/$pkg.tar.gz"
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
  for ((attempt = 1; attempt <= total; attempt++)); do
    if (( attempt > 1 )); then
      log "Thử lại $pkg (lần $attempt/$total)"
      run_logged pacman -Sy >/dev/null 2>&1 || true
    fi
    if ! fetch_aur "$pkg"; then
      log "Không lấy được PKGBUILD của $pkg từ AUR"
      continue
    fi
    if [[ "$pkg" == calamares ]] &&
      ! enable_calamares_packagechooser "$SRC_DIR/src/$pkg/PKGBUILD"; then
      log "Không thể bật module packagechooser bắt buộc trong PKGBUILD calamares"
      return 1
    fi
    # Chuyển quyền trước khi đọc phụ thuộc: nhánh dự phòng của srcinfo_deps chạy
    # `makepkg --printsrcinfo` dưới tài khoản dựng gói, cần thư mục ghi được.
    if (( EUID == 0 )); then
      chown -R -- "$BUILDER_UID:$BUILDER_GID" "$SRC_DIR/src/$pkg" "$SRC_DIR/home"
    fi
    install_deps "$pkg" || return 1
    # Cờ của makepkg:
    #   -f         work dir dùng lại không khiến makepkg bỏ qua gói đã dựng
    #   --nocheck  bỏ qua check(): bộ test của gói AUR thường cần mạng và
    #              checkdepends riêng, không đáng để đánh đổi cả bản dựng ISO
    #   KHÔNG -s / -i / -r: phụ thuộc do script cài bằng quyền root ở trên, còn
    #              việc cài gói cũng do root làm (pacman -U) nên tài khoản dựng
    #              gói không cần sudo và ảnh không cần quyền NOPASSWD nào
    build_status=0
    # shellcheck disable=SC2086
    (cd "$SRC_DIR/src/$pkg" && run_makepkg -f --noconfirm --nocheck $MAKEPKG_EXTRA_OPTS) ||
      build_status=$?
    if (( build_status == 0 )); then
      pkgfile="$(find "$SRC_DIR/src/$pkg" -maxdepth 1 -name "$pkg-*.pkg.tar*" | sort | sed -n '1p')"
      if [[ -z "$pkgfile" ]]; then
        # Gói split: lấy file .pkg.tar đầu tiên có trong thư mục.
        pkgfile="$(find "$SRC_DIR/src/$pkg" -maxdepth 1 -name '*.pkg.tar*' | sort | sed -n '1p')"
      fi
      if [[ -z "$pkgfile" ]]; then
        log "makepkg xong nhưng không tìm thấy file .pkg.tar của $pkg"
        continue
      fi
      log "$pkg: cài $(basename -- "$pkgfile") vào airootfs"
      if run_logged pacman -U --noconfirm --asexplicit -- "$pkgfile"; then
        return 0
      fi
      log "pacman -U thất bại với $pkgfile"
    else
      log "makepkg thất bại với $pkg (exit $build_status)"
    fi
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
      continue
    fi
    log "$pkg $(pacman -Q "$pkg" | awk '{print $2}') đã cài vào ảnh live"
    AUR_OK+=("$pkg")
  else
    AUR_FAILED+=("$pkg (dựng thất bại — xem nhật ký)")
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
    for reason in ${AUR_FAILED[@]+"${AUR_FAILED[@]}"}; do
      printf '%s\n' "# THẤT BẠI: $reason"
    done
  } >"$report_tmp"
  install -d -m 0755 -- "$(dirname -- "$REPORT")"
  install -m 0644 -- "$report_tmp" "$REPORT"
  log "Đã ghi báo cáo gói AUR vào $REPORT"
fi

# --- Kết luận -------------------------------------------------------------
if (( ${#AUR_FAILED[@]} > 0 )); then
  log "Xong với lỗi: ${#AUR_OK[@]} gói cài được, ${#AUR_FAILED[@]} gói hỏng"
  die "Các gói AUR sau không dựng được: ${AUR_FAILED[*]}"
fi

log "Hoàn tất: ${AUR_OK[*]}"
exit 0
