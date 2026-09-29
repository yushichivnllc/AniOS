#!/usr/bin/env bash
# Kiểm tra dàn âm thanh của ảnh live ngay bên trong airootfs.sfs vừa dựng.
#
#   Usage: scripts/check-live-audio.sh <airootfs.sfs> [pkglist.x86_64.txt]
#
# Không thể "nghe thử" trong CI nên script đọc thẳng squashfs để xác nhận:
#   * plugin SPA ALSA (pipewire-audio) và cấu hình ALSA trỏ về PipeWire,
#   * unit người dùng của PipeWire, pipewire-pulse và WirePlumber,
#   * drop-in default.target và symlink bật sẵn do AniOS thêm vào,
#   * công cụ wpctl/pactl/aplay/... và công cụ chẩn đoán của AniOS.
#
# ---------------------------------------------------------------------------
# VÌ SAO KHÔNG DÙNG `unsquashfs -cat`
# ---------------------------------------------------------------------------
# `unsquashfs -cat` KHÔNG đi theo symlink tuyệt đối. Trong squashfs-tools
# (unsquashfs.c, hàm cat_scan(), nhánh SQUASHFS_SYMLINK_TYPE):
#
#     /* Symlink must be relative to current directory and not be absolute,
#      * otherwise we can't follow it, as it is probably outside the Squashfs
#      * filesystem */
#     if(symlink[0] == '/') { ERROR("cat: %s failed to resolve symbolic link"); }
#
# và set_exit_code mặc định là TRUE nên lệnh trả exit code 2.
#
# Mà đúng những thứ cần kiểm tra lại là symlink tuyệt đối:
#   * PKGBUILD của pipewire cài:
#       package_pipewire-alsa(): ln -st "$pkgdir/etc/alsa/conf.d" \
#           /usr/share/alsa/alsa.conf.d/99-pipewire-default.conf
#       package_pipewire-audio(): ln -st "$pkgdir/etc/alsa/conf.d" \
#           /usr/share/alsa/alsa.conf.d/50-pipewire.conf
#     nên /etc/alsa/conf.d/*.conf trong ảnh live là symlink tuyệt đối;
#   * symlink do `systemctl enable` tạo ra (default.target.wants/...) cũng trỏ
#     tới /usr/lib/systemd/user/... bằng đường dẫn tuyệt đối.
#
# Vì vậy script tự đi theo symlink: trích THƯ MỤC CHA bằng `unsquashfs -d`
# (trích cả thư mục thì symlink bên trong được giữ nguyên), đọc đích bằng
# readlink, rồi trích tiếp file đích.
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/check-live-audio.sh <airootfs.sfs> [pkglist]

  <airootfs.sfs>  squashfs của ảnh live (thường là out/airootfs.sfs)
  [pkglist]       pkglist.x86_64.txt lấy từ ISO; bỏ trống thì bỏ qua bước
                  kiểm tra danh sách gói
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
ok() { echo "  OK    $*"; }

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/anios-audio-check.XXXXXX")"
cleanup() { rm -rf -- "$WORK_DIR"; }
trap cleanup EXIT
EXTRACT_DIR="$WORK_DIR/extract"
mkdir -p -- "$EXTRACT_DIR"

# --- Truy cập squashfs, tự đi theo symlink -------------------------------
#
# unsquashfs TỪ CHỐI mọi đường dẫn mà thành phần cuối là symlink tuyệt đối, ở
# cả hai chế độ (squashfs-tools 4.6.1, 4.7.x và master, hàm follow_path/
# follow_extract_paths và cat_scan, nhánh SQUASHFS_SYMLINK_TYPE):
#
#     /* Symlink must be relative to current directory and not be absolute,
#      * otherwise we can't follow it, as it is probably outside the Squashfs
#      * filesystem */
#     if(symlink[0] == '/') { traversed = FALSE; ... }
#
# Nhưng trích CẢ THƯ MỤC thì vẫn giữ nguyên symlink bên trong (create_inode
# gọi symlink(2) cho từng entry). Vì vậy chiến lược ở đây là:
#   1. thử trích riêng đường dẫn (rẻ, đủ cho file thường);
#   2. nếu unsquashfs từ chối — tức entry là symlink tuyệt đối — thì trích thư
#      mục cha (chỉ khi thư mục đó nhỏ) rồi khảo sát entry ngay trong cây vừa
#      trích, lấy đích bằng readlink và trích tiếp file đích.

# Chuẩn hoá đường dẫn bên trong ảnh: bỏ '/' đầu, giải quyết '.'/'..'.
sfs_normalize() {
  local raw="${1#/}" part sep="" joined=""
  local -a parts out=()
  IFS='/' read -r -a parts <<<"$raw"
  for part in ${parts[@]+"${parts[@]}"}; do
    case "$part" in
      '' | .) ;;
      ..)
        if ((${#out[@]} > 0)); then
          unset 'out[-1]'
        else
          echo "sfs_normalize: $1 vượt ra ngoài gốc của ảnh" >&2
          return 1
        fi
        ;;
      *) out+=("$part") ;;
    esac
  done
  for part in ${out[@]+"${out[@]}"}; do
    joined+="$sep$part"
    sep="/"
  done
  printf '%s\n' "$joined"
}

EXTRACTED_DIRS="$WORK_DIR/extracted-dirs"
: >"$EXTRACTED_DIRS"

# Giới hạn số entry để không bao giờ trích nhầm thư mục khổng lồ (usr/bin...)
# chỉ vì một đường dẫn bị thiếu.
SFS_MAX_DIR_ENTRIES=500

# Trích riêng một đường dẫn; thất bại nếu entry là symlink tuyệt đối.
sfs_extract_single() {
  local rel="$1"
  unsquashfs -q -no-progress -d "$EXTRACT_DIR" "$SQUASHFS" "$rel" >/dev/null 2>&1 || return 1
  [[ -e "$EXTRACT_DIR/$rel" || -L "$EXTRACT_DIR/$rel" ]]
}

# Trích cả thư mục (giữ nguyên symlink bên trong), mỗi thư mục chỉ một lần.
sfs_extract_dir() {
  local dir="$1"
  if [[ -z "$dir" ]]; then
    return 0
  fi
  if grep -qsxF -- "$dir" "$EXTRACTED_DIRS"; then
    return 0
  fi
  unsquashfs -q -no-progress -d "$EXTRACT_DIR" "$SQUASHFS" "$dir" >/dev/null 2>&1 || return 1
  [[ -d "$EXTRACT_DIR/$dir" ]] || return 1
  printf '%s\n' "$dir" >>"$EXTRACTED_DIRS"
}

# Đảm bảo entry có mặt trong cây đã trích để khảo sát bằng test/readlink/cat.
sfs_prepare() {
  local rel dir base entries
  rel="$(sfs_normalize "$1")" || return 1
  if [[ -z "$rel" ]]; then
    return 1
  fi
  if [[ -e "$EXTRACT_DIR/$rel" || -L "$EXTRACT_DIR/$rel" ]]; then
    return 0
  fi
  if sfs_extract_single "$rel"; then
    return 0
  fi
  # unsquashfs từ chối: entry nhiều khả năng là symlink tuyệt đối. Trích thư mục
  # cha để nhìn thấy symlink đó, nhưng bỏ qua thư mục quá lớn.
  dir="$(dirname -- "$rel")"
  if [[ "$dir" == "." ]]; then
    dir=""
  fi
  base="${rel##*/}"
  entries="$(unsquashfs -l "$SQUASHFS" ${dir:+"$dir"} 2>/dev/null | wc -l || true)"
  if [[ "$entries" =~ ^[0-9]+$ ]] && ((entries > SFS_MAX_DIR_ENTRIES)); then
    echo "sfs_prepare: bỏ qua trích $dir (${entries} entry, quá lớn) khi tìm $base" >&2
    return 1
  fi
  sfs_extract_dir "$dir" || return 1
  [[ -e "$EXTRACT_DIR/$dir/$base" || -L "$EXTRACT_DIR/$dir/$base" ]]
}

# In loại của entry: file | symlink | dir | other | missing.
sfs_kind() {
  local rel
  rel="$(sfs_normalize "$1" 2>/dev/null)" || { printf 'missing\n'; return 0; }
  sfs_prepare "$rel" || { printf 'missing\n'; return 0; }
  if [[ -L "$EXTRACT_DIR/$rel" ]]; then
    printf 'symlink\n'
  elif [[ -d "$EXTRACT_DIR/$rel" ]]; then
    printf 'dir\n'
  elif [[ -f "$EXTRACT_DIR/$rel" ]]; then
    printf 'file\n'
  else
    printf 'other\n'
  fi
}

# In đích của symlink; rỗng nếu entry không phải symlink.
sfs_link_target() {
  local rel
  rel="$(sfs_normalize "$1")" || return 1
  sfs_prepare "$rel" || return 1
  if [[ ! -L "$EXTRACT_DIR/$rel" ]]; then
    return 0
  fi
  readlink -- "$EXTRACT_DIR/$rel"
}

# Trả về đường dẫn (không có '/' đầu) của file thật sau khi đi theo symlink.
sfs_resolve() {
  local rel hop kind target dir
  rel="$(sfs_normalize "$1")" || return 1
  for ((hop = 0; hop < 16; hop++)); do
    kind="$(sfs_kind "$rel")"
    case "$kind" in
      file)
        printf '%s\n' "$rel"
        return 0
        ;;
      symlink)
        target="$(sfs_link_target "$rel")"
        if [[ "$target" == /* ]]; then
          rel="${target#/}"
        else
          dir="$(dirname -- "$rel")"
          if [[ "$dir" == "." ]]; then
            dir=""
          fi
          rel="$(sfs_normalize "/$dir/$target")" || return 1
        fi
        ;;
      *)
        return 1
        ;;
    esac
  done
  echo "sfs_resolve: $1 không kết thúc sau 16 bước symlink" >&2
  return 1
}

# Entry tồn tại và cuối cùng trỏ tới một file thật bên trong ảnh.
sfs_has_file() { sfs_resolve "$1" >/dev/null; }

# Đọc nội dung một đường dẫn trong ảnh, đi theo symlink.
sfs_read() {
  local rel
  rel="$(sfs_resolve "$1")" || return 1
  [[ -f "$EXTRACT_DIR/$rel" && ! -L "$EXTRACT_DIR/$rel" ]] || return 1
  cat -- "$EXTRACT_DIR/$rel"
}

# 1) Toàn bộ trạng thái unit người dùng trong ảnh: vừa là bằng chứng cho bước
#    kiểm tra, vừa giúp đọc log khi có sự cố âm thanh. Trích cả thư mục nên
#    symlink do systemd enable tạo ra vẫn hiện đúng bản chất của nó.
echo "--- /etc/systemd/user trong ảnh live ---"
if sfs_extract_dir etc/systemd/user; then
  find "$EXTRACT_DIR/etc/systemd/user" -printf '%y %P -> %l\n' | sort | sed 's/^/  /'
else
  echo "  (ảnh live không có /etc/systemd/user)"
fi

# 2) Các file mà dàn âm thanh cần có. Thiếu file nào thì app không mở được
#    thiết bị (libspa-alsa.so) hoặc không có tiếng (ALSA chưa trỏ về PipeWire).
echo "--- tệp quan trọng của dàn âm thanh ---"
missing_paths=()
for path in \
  usr/lib/systemd/user/pipewire.service \
  usr/lib/systemd/user/pipewire.socket \
  usr/lib/systemd/user/pipewire-pulse.service \
  usr/lib/systemd/user/pipewire-pulse.socket \
  usr/lib/systemd/user/wireplumber.service \
  usr/bin/pipewire usr/bin/pipewire-pulse usr/bin/wireplumber \
  usr/bin/wpctl usr/bin/pactl usr/bin/aplay usr/bin/speaker-test usr/bin/alsamixer \
  usr/lib/spa-0.2/alsa/libspa-alsa.so \
  usr/lib/alsa-lib/libasound_module_pcm_pipewire.so \
  usr/share/alsa/alsa.conf.d/50-pipewire.conf \
  etc/alsa/conf.d/50-pipewire.conf \
  etc/alsa/conf.d/99-pipewire-default.conf; do
  if sfs_has_file "$path"; then
    target="$(sfs_link_target "$path")"
    if [[ -n "$target" ]]; then
      ok "$path -> $target"
    else
      ok "$path"
    fi
  else
    echo "  THIẾU $path"
    missing_paths+=("$path")
  fi
done
((${#missing_paths[@]} == 0)) ||
  fail "Ảnh live thiếu thành phần âm thanh: ${missing_paths[*]}"

# 2b) Hai file ALSA vừa kiểm tra do gói pipewire-alsa và pipewire-audio cài
#     dưới dạng SYMLINK TUYỆT ĐỐI trỏ về /usr/share/alsa/alsa.conf.d/. Overlay
#     của AniOS KHÔNG được ship lại chúng: mkarchiso chép profile/airootfs vào
#     work/ trước khi pacstrap cài gói, nên pacman sẽ báo "failed to commit
#     transaction (conflicting files)" và bản dựng chết giữa chừng. Vì vậy bước
#     này xác nhận NỘI DUNG file đích thật sự đưa ALSA về PipeWire.
alsa_default="$(sfs_read etc/alsa/conf.d/99-pipewire-default.conf)" ||
  fail "không đọc được /etc/alsa/conf.d/99-pipewire-default.conf trong ảnh live"
# pipewire 1.x định nghĩa PCM/CTL mặc định bằng khối pcm.!default/ctl.!default
# với "type pipewire" (không còn dùng defaults.pcm.!card như bản rất cũ).
for needle in 'pcm.!default' 'ctl.!default' 'type pipewire'; do
  grep -qF -- "$needle" <<<"$alsa_default" ||
    fail "/etc/alsa/conf.d/99-pipewire-default.conf trong ảnh live thiếu '$needle': ALSA mặc định không trỏ về PipeWire"
done
ok "ALSA default -> PipeWire (gói pipewire-alsa cài sẵn)"

pipewire_alsa_conf="$(sfs_read etc/alsa/conf.d/50-pipewire.conf)" ||
  fail "không đọc được /etc/alsa/conf.d/50-pipewire.conf trong ảnh live"
for needle in 'pcm.pipewire' 'ctl.pipewire' 'type pipewire'; do
  grep -qF -- "$needle" <<<"$pipewire_alsa_conf" ||
    fail "/etc/alsa/conf.d/50-pipewire.conf trong ảnh live thiếu '$needle': thiết bị ALSA pipewire chưa được định nghĩa"
done
ok "thiết bị ALSA pcm/ctl pipewire (gói pipewire-audio cài sẵn)"

# 3) Gói âm thanh phải có mặt trong danh sách gói của ảnh live.
if [[ -n "$PKGLIST" ]]; then
  echo "--- gói âm thanh trong ảnh live ---"
  [[ -s "$PKGLIST" ]] || fail "không đọc được danh sách gói: $PKGLIST"
  for package in \
    pipewire pipewire-audio pipewire-alsa pipewire-pulse wireplumber \
    alsa-card-profiles alsa-utils rtkit; do
    line="$(grep "^${package} " "$PKGLIST" || true)"
    [[ -n "$line" ]] || fail "Ảnh live thiếu gói ${package}"
    ok "$line"
  done
fi

# 4) Cấu hình bật sẵn của AniOS: drop-in default.target + symlink. Đây là thứ
#    bảo đảm PipeWire/WirePlumber chạy ngay cả khi scriptlet của gói không để
#    lại symlink trong chroot lúc dựng.
echo "--- cấu hình tự khởi động của AniOS ---"
dropin="$(sfs_read etc/systemd/user/default.target.d/10-anios-audio.conf)" ||
  fail "không đọc được etc/systemd/user/default.target.d/10-anios-audio.conf"
for want in pipewire.service pipewire-pulse.service wireplumber.service anios-audio-setup.service; do
  grep -q "Wants=.*${want}" <<<"$dropin" ||
    fail "drop-in âm thanh không nạp ${want}"
done
ok "etc/systemd/user/default.target.d/10-anios-audio.conf"

for path in \
  etc/systemd/user/default.target.wants/pipewire.service \
  etc/systemd/user/default.target.wants/pipewire-pulse.service \
  etc/systemd/user/default.target.wants/anios-audio-setup.service \
  etc/systemd/user/sockets.target.wants/pipewire.socket \
  etc/systemd/user/sockets.target.wants/pipewire-pulse.socket \
  etc/systemd/user/pipewire.service.wants/wireplumber.service; do
  # symlink hỏng (unit đổi tên/bị xoá) cũng làm sfs_has_file thất bại.
  sfs_has_file "$path" || fail "Thiếu hoặc hỏng symlink bật unit âm thanh: $path"
  target="$(sfs_link_target "$path")"
  ok "$path${target:+ -> $target}"
done

# 5) Công cụ âm thanh của AniOS phải có trong ảnh và chạy được.
tools_dir="$WORK_DIR/tools"
mkdir -p -- "$tools_dir"
unsquashfs -q -no-progress -d "$tools_dir" "$SQUASHFS" \
  usr/local/bin/anios-audio-setup usr/local/bin/anios-audio-check \
  etc/systemd/user/anios-audio-setup.service >/dev/null ||
  fail "Không trích được công cụ âm thanh của AniOS"
for path in \
  usr/local/bin/anios-audio-setup usr/local/bin/anios-audio-check \
  etc/systemd/user/anios-audio-setup.service; do
  [[ -s "$tools_dir/$path" ]] || fail "Thiếu $path trong ảnh live"
done
for tool in usr/local/bin/anios-audio-setup usr/local/bin/anios-audio-check; do
  mode="$(stat -c '%a' "$tools_dir/$tool")"
  [[ "$mode" == 755 ]] || fail "$tool có quyền $mode, cần 755"
  ok "$tool $mode"
  bash -n "$tools_dir/$tool" || fail "$tool có lỗi cú pháp shell"
done
grep -q 'anios-audio-setup' "$tools_dir/etc/systemd/user/anios-audio-setup.service" ||
  fail "unit anios-audio-setup.service không chạy anios-audio-setup"
ok "etc/systemd/user/anios-audio-setup.service"

echo "Ảnh live có đủ dàn âm thanh PipeWire và cấu hình tự khởi động của AniOS"
