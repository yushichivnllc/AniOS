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
# Vì vậy script tự đi theo symlink. Ba điều dưới đây đã được đo trên
# squashfs-tools 4.6.1 và 4.7.5, và bài tự kiểm tra
# scripts/selftest-check-live-audio.sh mô phỏng lại đúng cả ba:
#
#   1. `unsquashfs -d` trích vào một đích đã có sẵn thư mục trên đường dẫn là lỗi
#      CHÍ MẠNG (unsquashfs.c, dir_scan()):
#
#          int res = mkdir(parent_name, S_IRUSR|S_IWUSR|S_IXUSR);
#          if(res == -1) {
#              if((depth != 1 && !force) || errno != EEXIST) {
#                  EXIT_UNSQUASH_IGNORE("dir_scan: failed to make directory %s,"
#                      " because %s\n", parent_name, strerror(errno));
#
#      Chỉ thư mục đích gốc (depth == 1) mới được phép tồn tại sẵn. Bản cũ trích
#      mọi thứ vào CHUNG một $EXTRACT_DIR, nên từ lần trích thứ hai trở đi
#      unsquashfs chết với "dir_scan: failed to make directory /.../usr, because
#      File exists" và script báo THIẾU gần hết — đúng như log CI. Ở đây mỗi lần
#      trích dùng một thư mục đích MỚI TOANH, rồi chuyển entry cần dùng vào cây
#      đệm ($CACHE_DIR).
#
#   2. Trích đúng một đường dẫn mà KHÔNG kèm -follow-symlinks/-match thì
#      unsquashfs giữ nguyên symlink tuyệt đối (nó chỉ đi theo symlink khi được
#      yêu cầu rõ ràng). Nhờ vậy, khi cần, script vẫn lấy được đích bằng readlink
#      từ cây đệm — đây là đường dự phòng cho bước 3.
#
#   3. Bản cũ còn một lỗi thứ hai: để nhìn thấy symlink tuyệt đối nó trích cả
#      thư mục cha, và vì /usr/bin của ảnh live có hàng nghìn entry (Steam, Mesa,
#      Qt...) nó tự chặn bằng ngưỡng SFS_MAX_DIR_ENTRIES=500 — tức bỏ qua luôn
#      usr/bin và báo THIẾU mọi binary có thật trong đó (pipewire, wpctl, pactl,
#      aplay...). Cách đúng: hỏi thẳng metadata bằng `unsquashfs -ll`, nó in ra
#      loại entry và đích symlink mà KHÔNG trích gì, cũng không đi theo symlink,
#      nên thư mục cha to cỡ nào cũng không ảnh hưởng.
#
#   4. Với `set -Eeuo pipefail`, KHÔNG BAO GIỜ nối ống danh sách dài vào `head`
#      (ví dụ `find ... | sort | head -60`): khi `head` đọc đủ 60 dòng và đóng
#      ống (đúng lúc đang in tới `usr/share/alsa/cards/CMI8738-MC8.conf`), lệnh
#      đứng trước nhận tín hiệu SIGPIPE (13) và thoát với mã 128 + 13 = 141.
#      `pipefail` + `-e` làm cả bước CI chết ngay với "Process completed with
#      exit code 141" trước khi kịp in `::error::`. Mọi bước giới hạn số dòng ở
#      đây đều đọc hết luồng đầu vào tới EOF bằng `awk` rồi mới ngưng in.
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
# Cây đệm: đúng những entry đã trích, giữ nguyên bản chất (symlink vẫn là symlink).
CACHE_DIR="$WORK_DIR/cache"
# Gốc cho các thư mục đích mới toanh của từng lần trích (xem lý do ở trên).
SCRATCH_ROOT="$WORK_DIR/scratch"
# Nhớ những thư mục đã trích trọn vẹn, để không trích lại.
CACHED_DIRS="$WORK_DIR/cached-dirs"
mkdir -p -- "$CACHE_DIR" "$SCRATCH_ROOT"
: >"$CACHED_DIRS"

# --- Truy cập squashfs, tự đi theo symlink -------------------------------

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

# ---------------------------------------------------------------------------
# Đọc metadata của một entry: `unsquashfs -ll`, KHÔNG trích gì
# ---------------------------------------------------------------------------
# `unsquashfs -ll <đường dẫn>` chỉ đọc metadata và in ra chuỗi thư mục cha rồi
# tới entry, dạng (unsquashfs_info.c):
#
#   lrwxrwxrwx root/root   44 2026-09-29 03:40 squashfs-root/etc/alsa/conf.d/50-pipewire.conf -> /usr/share/alsa/alsa.conf.d/50-pipewire.conf
#   -rwxr-xr-x root/root  1.2M 2026-09-29 03:40 squashfs-root/usr/bin/pipewire
#
# Nó KHÔNG đi theo symlink và KHÔNG trích gì, nên đây là cách duy nhất vừa nhìn
# được symlink tuyệt đối vừa không phải trích cả thư mục cha (usr/bin có hàng
# nghìn entry). Đường dẫn không tồn tại thì unsquashfs in chuỗi thư mục cha rồi
# thoát 0, nên phải nhận diện dòng của CHÍNH entry bằng cách so đúng đường dẫn
# (5 cột đầu là metadata — quyền, chủ/nhóm, kích thước, ngày, giờ — phần còn lại
# là đường dẫn, nên tên tệp có dấu cách vẫn không bị cắt sai).
SFS_LIST_PREFIX="squashfs-root"
declare -A SFS_ENTRY_INFO=()

# In "<loại>\t<đích>" của entry trong ảnh (loại là ký tự đầu của quyền: - d l),
# hoặc không in gì nếu ảnh không có đường dẫn đó.
sfs_image_entry() {
  local rel info
  rel="$(sfs_normalize "$1" 2>/dev/null)" || return 0
  [[ -n "$rel" ]] || return 0
  if [[ -n "${SFS_ENTRY_INFO[$rel]+có}" ]]; then
    printf '%s\n' "${SFS_ENTRY_INFO[$rel]}"
    return 0
  fi
  # `|| true`: giữ `set -e` khỏi thoát khi unsquashfs trả lỗi (đường dẫn lạ).
  # Không dùng `exit` giữa chừng trong awk: nếu $rel là thư mục lớn, đóng ống
  # sớm sẽ làm unsquashfs nhận SIGPIPE (141) dưới `set -o pipefail`.
  info="$(unsquashfs -ll "$SQUASHFS" "$rel" 2>/dev/null | awk -v want="$SFS_LIST_PREFIX/$rel" '
    !found {
      path = $0
      target = ""
      pos = index(path, " -> ")
      if (pos > 0) {
        target = substr(path, pos + 4)
        path = substr(path, 1, pos - 1)
      }
      if (match(path, /^[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[0-9][^[:space:]]*[[:space:]]+[0-9-]+[[:space:]]+[0-9:]+[[:space:]]+/)) {
        if (substr(path, RLENGTH + 1) == want) {
          split(substr(path, 1, RLENGTH), field, /[[:space:]]+/)
          printf "%s\t%s\n", substr(field[1], 1, 1), target
          found = 1
        }
      }
    }')" || true
  SFS_ENTRY_INFO[$rel]="$info"
  printf '%s\n' "$info"
}

# ---------------------------------------------------------------------------
# Trích entry vào cây đệm
# ---------------------------------------------------------------------------
# Trích đúng một đường dẫn vào một thư mục đích MỚI TOANH rồi in đường dẫn thư
# mục đó ra stdout. Vì sao phải mới: `unsquashfs -d` gọi mkdir(2) cho từng thư
# mục trên đường dẫn và coi EEXIST là lỗi chí mạng, chỉ tha cho đúng thư mục
# đích gốc —
#   FATAL ERROR: dir_scan: failed to make directory /dest/usr, because File exists
# (unsquashfs.c, dir_scan(); chi tiết trong khối chú thích đầu file) — nên trích
# lần thứ hai vào cùng một đích luôn thất bại dù entry hoàn toàn bình thường.
sfs_extract_scratch() {
  local scratch
  scratch="$(mktemp -d "$SCRATCH_ROOT/step.XXXXXX")"
  if unsquashfs -q -no-progress -d "$scratch" "$SQUASHFS" "$@" >/dev/null 2>&1; then
    printf '%s\n' "$scratch"
    return 0
  fi
  rm -rf -- "$scratch"
  return 1
}

# Chuyển entry $2 từ thư mục đích $1 vào cây đệm (giữ nguyên symlink và quyền).
sfs_cache_put() {
  local scratch="$1" rel="$2" parent
  [[ -n "$scratch" && -n "$rel" ]] || return 1
  [[ -e "$scratch/$rel" || -L "$scratch/$rel" ]] || return 1
  parent="$(dirname -- "$rel")"
  mkdir -p -- "$CACHE_DIR/$parent" || return 1
  rm -rf -- "$CACHE_DIR/$rel"
  cp -a -- "$scratch/$rel" "$CACHE_DIR/$rel"
}

# Bảo đảm entry có mặt trong cây đệm, trả 0 nếu nó có thật trong ảnh live.
sfs_materialize() {
  local rel scratch rc=0
  rel="$(sfs_normalize "$1")" || return 1
  [[ -n "$rel" ]] || return 1
  if [[ -e "$CACHE_DIR/$rel" || -L "$CACHE_DIR/$rel" ]]; then
    return 0
  fi
  # Trích đúng entry (không trích thư mục cha): unsquashfs giữ nguyên symlink
  # tuyệt đối thay vì đi theo nó, vì script không dùng -follow-symlinks/-match —
  # nếu dùng, follow_path() sẽ từ chối mọi symlink tuyệt đối.
  scratch="$(sfs_extract_scratch "$rel")" || return 1
  sfs_cache_put "$scratch" "$rel" || rc=$?
  rm -rf -- "$scratch"
  return "$rc"
}

# Trích cả một thư mục (giữ nguyên symlink bên trong) vào cây đệm.
sfs_extract_dir() {
  local dir="$1" scratch
  [[ -n "$dir" ]] || return 0
  if grep -qsxF -- "$dir" "$CACHED_DIRS"; then
    return 0
  fi
  scratch="$(sfs_extract_scratch "$dir")" || return 1
  if [[ ! -d "$scratch/$dir" ]]; then
    rm -rf -- "$scratch"
    return 1
  fi
  mkdir -p -- "$CACHE_DIR/$dir"
  cp -a -- "$scratch/$dir/." "$CACHE_DIR/$dir/"
  rm -rf -- "$scratch"
  printf '%s\n' "$dir" >>"$CACHED_DIRS"
}

# In loại của entry: file | symlink | dir | other | missing.
sfs_kind() {
  local rel info kind target
  rel="$(sfs_normalize "$1" 2>/dev/null)" || { printf 'missing\n'; return 0; }
  info="$(sfs_image_entry "$rel")"
  if [[ -n "$info" ]]; then
    IFS=$'\t' read -r kind target <<<"$info" || true
    case "$kind" in
      d) printf 'dir\n' ;;
      l) printf 'symlink\n' ;;
      -) printf 'file\n' ;;
      *) printf 'other\n' ;;
    esac
    return 0
  fi
  # Không có dòng metadata (định dạng `unsquashfs -ll` đổi ở bản mới, hoặc entry
  # thuộc loại lạ): lui về cách chắc chắn nhất — trích entry rồi hỏi hệ thống tệp
  # của cây đệm. Symlink tuyệt đối vẫn được giữ nguyên khi trích nên vẫn nhận ra.
  if sfs_materialize "$rel"; then
    if [[ -L "$CACHE_DIR/$rel" ]]; then
      printf 'symlink\n'
    elif [[ -d "$CACHE_DIR/$rel" ]]; then
      printf 'dir\n'
    elif [[ -f "$CACHE_DIR/$rel" ]]; then
      printf 'file\n'
    else
      printf 'other\n'
    fi
  else
    printf 'missing\n'
  fi
}

# In đích của symlink; rỗng nếu entry không phải symlink.
sfs_link_target() {
  local rel info kind target
  rel="$(sfs_normalize "$1")" || return 1
  info="$(sfs_image_entry "$rel")"
  if [[ -n "$info" ]]; then
    IFS=$'\t' read -r kind target <<<"$info" || true
    [[ "$kind" == "l" ]] || return 0
    printf '%s\n' "$target"
    return 0
  fi
  # Dự phòng: đọc đích từ chính symlink đã trích trong cây đệm.
  sfs_materialize "$rel" || return 0
  [[ -L "$CACHE_DIR/$rel" ]] || return 0
  readlink -- "$CACHE_DIR/$rel"
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
  sfs_materialize "$rel" || return 1
  [[ -f "$CACHE_DIR/$rel" && ! -L "$CACHE_DIR/$rel" ]] || return 1
  cat -- "$CACHE_DIR/$rel"
}

# Khi thiếu thành phần âm thanh, liệt kê những entry âm thanh thật sự có trong
# ảnh để đọc ngay trong log CI.
#
# Lưu ý quan trọng:
#   * Chỉ hỏi các thư mục cấu hình/unit/plugin âm thanh cụ thể và các binary âm
#     thanh trong usr/bin, KHÔNG quét cả usr/share/alsa (nơi có hàng trăm file
#     usr/share/alsa/cards/*.conf làm ngập danh sách).
#   * Giới hạn 60 dòng bằng `awk 'NR <= 60'` (đọc hết luồng tới EOF rồi mới
#     dừng in), TUYỆT ĐỐI KHÔNG dùng `| head -60`: dưới `set -Eeuo pipefail`,
#     `head` đóng ống sớm sẽ làm lệnh đứng trước nhận SIGPIPE và chết với
#     exit code 141 trước khi kịp in `::error::`.
sfs_dump_audio_entries() {
  local -a query_paths=(
    etc/systemd/user
    etc/alsa
    usr/share/alsa/alsa.conf
    usr/share/alsa/alsa.conf.d
    usr/lib/alsa-lib
    usr/lib/spa-0.2/alsa
    usr/lib/systemd/user
    usr/local/bin
    usr/bin/pipewire
    usr/bin/pipewire-pulse
    usr/bin/wireplumber
    usr/bin/wpctl
    usr/bin/pactl
    usr/bin/aplay
    usr/bin/speaker-test
    usr/bin/alsamixer
  )
  local dump="" p
  dump="$(
    for p in "${query_paths[@]}"; do
      unsquashfs -ll "$SQUASHFS" "$p" 2>/dev/null || true
    done | awk -v prefix="$SFS_LIST_PREFIX/" '
      {
        path = $0
        target = ""
        pos = index(path, " -> ")
        if (pos > 0) {
          target = substr(path, pos + 4)
          path = substr(path, 1, pos - 1)
        }
        if (match(path, /^[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[0-9][^[:space:]]*[[:space:]]+[0-9-]+[[:space:]]+[0-9:]+[[:space:]]+/)) {
          rel = substr(path, RLENGTH + 1)
          if (index(rel, prefix) == 1) {
            rel = substr(rel, length(prefix) + 1)
          }
          split(substr(path, 1, RLENGTH), field, /[[:space:]]+/)
          kind = substr(field[1], 1, 1)
          if ((kind == "-" || kind == "l") &&
              rel ~ /(alsa|pipewire|wireplumber|wpctl|pactl|aplay|speaker-test|alsamixer|anios-audio)/ &&
              rel !~ /^usr\/share\/alsa\/(cards|ucm|ucm2|topology|init)\//) {
            tag = (kind == "l") ? "l" : "f"
            line = "  " tag " " rel " -> " target
            if (!seen[line]++) {
              print line
            }
          }
        }
      }' | sort | awk 'NR <= 60 { print }'
  )" || true

  if [[ -z "$dump" ]]; then
    for p in etc/systemd/user etc/alsa usr/share/alsa/alsa.conf.d \
      usr/lib/alsa-lib usr/lib/spa-0.2/alsa usr/lib/systemd/user usr/local/bin; do
      sfs_extract_dir "$p" >/dev/null 2>&1 || true
    done
    dump="$(
      find "$CACHE_DIR" \( -type f -o -type l \) -printf '  %y %P -> %l\n' 2>/dev/null |
        grep -E 'alsa|pipewire|wireplumber|wpctl|pactl|aplay|speaker-test|alsamixer|anios-audio' |
        grep -vE 'usr/share/alsa/(cards|ucm|ucm2|topology|init)/' |
        sort -u | awk 'NR <= 60 { print }'
    )" || true
  fi

  [[ -z "$dump" ]] || printf '%s\n' "$dump"
}

# 1) Toàn bộ trạng thái unit người dùng trong ảnh: vừa là bằng chứng cho bước
#    kiểm tra, vừa giúp đọc log khi có sự cố âm thanh. Trích cả thư mục nên
#    symlink do systemd enable tạo ra vẫn hiện đúng bản chất của nó.
echo "--- /etc/systemd/user trong ảnh live ---"
if sfs_extract_dir etc/systemd/user; then
  find "$CACHE_DIR/etc/systemd/user" -printf '%y %P -> %l\n' | sort | sed 's/^/  /'
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
  usr/share/alsa/alsa.conf.d/99-pipewire-default.conf \
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
if ((${#missing_paths[@]} > 0)); then
  echo "--- những gì thật sự có trong ảnh ở các thư mục âm thanh ---"
  sfs_dump_audio_entries
  fail "Ảnh live thiếu thành phần âm thanh: ${missing_paths[*]}"
fi

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
#    libpulse mang pactl/paplay và libpulse.so cho app nói chuyện với
#    pipewire-pulse; anios-audio-setup và anios-audio-check gọi pactl trực tiếp
#    nên gói này phải có mặt tường minh trong ảnh.
if [[ -n "$PKGLIST" ]]; then
  echo "--- gói âm thanh trong ảnh live ---"
  [[ -s "$PKGLIST" ]] || fail "không đọc được danh sách gói: $PKGLIST"
  for package in \
    pipewire pipewire-audio pipewire-alsa pipewire-pulse wireplumber \
    alsa-card-profiles alsa-utils rtkit libpulse; do
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
for tool in usr/local/bin/anios-audio-setup usr/local/bin/anios-audio-check; do
  resolved="$(sfs_resolve "$tool")" || fail "Thiếu $tool trong ảnh live"
  sfs_materialize "$resolved" || fail "Không trích được $tool từ ảnh live"
  mode="$(stat -c '%a' "$CACHE_DIR/$resolved")"
  [[ "$mode" == 755 ]] || fail "$tool có quyền $mode, cần 755"
  ok "$tool $mode"
  bash -n "$CACHE_DIR/$resolved" || fail "$tool có lỗi cú pháp shell"
done
audio_unit="$(sfs_read etc/systemd/user/anios-audio-setup.service)" ||
  fail "không đọc được etc/systemd/user/anios-audio-setup.service"
grep -q 'anios-audio-setup' <<<"$audio_unit" ||
  fail "unit anios-audio-setup.service không chạy anios-audio-setup"
ok "etc/systemd/user/anios-audio-setup.service"

echo "Ảnh live có đủ dàn âm thanh PipeWire và cấu hình tự khởi động của AniOS"
