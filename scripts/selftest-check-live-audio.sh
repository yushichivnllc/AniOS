#!/usr/bin/env bash
# Tự kiểm tra scripts/check-live-audio.sh mà không cần dựng ISO.
#
# `unsquashfs` thật chỉ có trên Arch Linux (và chỉ chạy được trên squashfs
# thật), nên script này dựng một bản unsquashfs giả mô phỏng đúng những hành vi
# mà check-live-audio.sh dựa vào. Cả ba hành vi dưới đây đã đo trực tiếp trên
# squashfs-tools 4.6.1 và 4.7.5 (hai bản dựng từ nguồn, không suy đoán):
#
#   unsquashfs -cat IMAGE PATH
#       in nội dung file; TỪ CHỐI symlink tuyệt đối và trả exit code 2
#       (unsquashfs.c, cat_scan()/SQUASHFS_SYMLINK_TYPE với set_exit_code mặc
#        định TRUE).
#
#   unsquashfs -ll IMAGE PATH
#       in metadata dạng ls -l cho chuỗi thư mục cha rồi tới entry, kèm
#       "-> <đích>" cho symlink; KHÔNG trích gì và KHÔNG đi theo symlink.
#       Đường dẫn không tồn tại: in hết thư mục cha rồi thoát 0 (không có dòng
#       nào khớp đường dẫn cần tìm).
#
#   unsquashfs -d DIR IMAGE PATH
#       trích entry, GIỮ NGUYÊN symlink — kể cả symlink tuyệt đối (chỉ `-cat`
#       mới từ chối; khi có -follow-symlinks/-match thì follow_path() mới từ chối
#       và unsquashfs báo "Extract filename ... can't be resolved").
#       Điểm chết người nằm ở chỗ khác (unsquashfs.c, dir_scan()):
#
#           int res = mkdir(parent_name, S_IRUSR|S_IWUSR|S_IXUSR);
#           if(res == -1) {
#               if((depth != 1 && !force) || errno != EEXIST) {
#                   EXIT_UNSQUASH_IGNORE("dir_scan: failed to make directory %s,"
#                       " because %s\n", parent_name, strerror(errno));
#
#       Chỉ thư mục đích gốc (depth == 1) được phép tồn tại sẵn; mọi thư mục khác
#       trên đường dẫn mà đã có thì unsquashfs CHẾT với
#           FATAL ERROR: dir_scan: failed to make directory ..., because File exists
#       nên lần trích thứ hai vào cùng một đích luôn thất bại. Đó chính là lý do
#       bản cũ của check-live-audio.sh báo THIẾU gần như mọi file: nó trích chung
#       một $EXTRACT_DIR cho tất cả các đường dẫn.
#
# Trên cây thư mục giả đó script dựng lại đúng bố cục của ảnh live: hai file
# /etc/alsa/conf.d/*.conf là symlink tuyệt đối do pipewire-alsa/pipewire-audio
# cài, các symlink *.wants/* do systemd enable tạo ra, và một usr/bin "khổng lồ"
# như thật (ảnh live có hàng nghìn binary). Nhờ vậy kiểm tra được logic của
# check-live-audio.sh (đi theo symlink, báo thiếu file, so nội dung) ngay trên
# máy thường, trong vài giây.
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="$ROOT_DIR/scripts/check-live-audio.sh"

[[ -x "$CHECKER" ]] || { echo "FAIL: thiếu hoặc không chạy được $CHECKER" >&2; exit 1; }

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/anios-audio-selftest.XXXXXX")"
cleanup() { rm -rf -- "$SANDBOX"; }
trap cleanup EXIT

# --- unsquashfs giả -------------------------------------------------------
FAKE_BIN="$SANDBOX/bin"
mkdir -p -- "$FAKE_BIN"
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
    *) if [[ -z "$image" ]]; then image="$1"; else paths+=("$1"); fi; shift ;;
  esac
done
[[ -n "$image" && -d "$image" ]] || { echo "unsquashfs: cannot open $image" >&2; exit 1; }
# unsquashfs dùng chính giá trị -d làm tiền tố khi in danh sách.
prefix="$dest"

# `-cat` theo symlink TƯƠNG ĐỐI, còn symlink tuyệt đối thì từ chối
# (unsquashfs.c, cat_scan(), nhánh SQUASHFS_SYMLINK_TYPE).
is_abs_symlink() {
  local entry="$image/${1#/}"
  [[ -L "$entry" ]] || return 1
  [[ "$(readlink -- "$entry")" == /* ]]
}

# Một dòng metadata như `unsquashfs -ll` (unsquashfs_info.c):
#   <quyền> <chủ/nhóm> <kích thước> <ngày> <giờ> <tiền tố>/<đường dẫn>[ -> <đích>]
print_long_line() {
  local rel="$1" src="$image/$1" perms size target=""
  [[ -e "$src" || -L "$src" ]] || return 1
  perms="$(stat -c '%A' -- "$src")"
  size="$(stat -c '%s' -- "$src")"
  if [[ -L "$src" ]]; then
    target=" -> $(readlink -- "$src")"
  fi
  printf '%s %s %s %s %s/%s%s\n' \
    "$perms" "root/root" "$size" "2026-09-29 03:40" "$prefix" "$rel" "$target"
}

list_long() {
  local rel="$1" cur="" i
  local -a parts=()
  IFS='/' read -r -a parts <<<"$rel"
  for ((i = 0; i < ${#parts[@]}; i++)); do
    cur+="${cur:+/}${parts[i]}"
    [[ -e "$image/$cur" || -L "$image/$cur" ]] || return 0
    print_long_line "$cur"
  done
  # Đối số là thư mục thì unsquashfs in cả cây con.
  if [[ -d "$image/$rel" ]]; then
    while IFS= read -r sub; do
      print_long_line "$rel/$sub"
    done < <(cd -- "$image" && find "$rel" -mindepth 1 -printf '%P\n' | sort)
  fi
}

# Các đường dẫn trong ảnh khớp mẫu (unsquashfs so khớp wildcard theo mặc định).
expand_pattern() {
  local match
  while IFS= read -r match; do
    [[ -n "$match" ]] || continue
    printf '%s\n' "${match#"$image/"}"
  done < <(compgen -G "$image/$1" || true)
}

# Trích một entry. mkdir(2) từng thư mục trên đường dẫn, chỉ thư mục đích gốc là
# được phép tồn tại sẵn — đúng như dir_scan() của unsquashfs thật.
extract_entry() {
  local rel="$1" cur="" i
  local -a parts=()
  IFS='/' read -r -a parts <<<"$rel"
  for ((i = 0; i < ${#parts[@]} - 1; i++)); do
    cur+="${cur:+/}${parts[i]}"
    if [[ -d "$dest/$cur" ]]; then
      echo "FATAL ERROR: dir_scan: failed to make directory $dest/$cur, because File exists" >&2
      return 1
    fi
    mkdir -p -- "$dest/$cur"
  done
  mkdir -p -- "$(dirname -- "$dest/$rel")"
  rm -rf -- "$dest/$rel"
  # cp -a giữ nguyên symlink, kể cả symlink tuyệt đối: unsquashfs cũng vậy.
  cp -a -- "$image/$rel" "$dest/$rel"
}

if [[ "$mode" == cat ]]; then
  ((${#paths[@]} == 1)) || { echo "unsquashfs: -cat needs exactly one path" >&2; exit 1; }
  rel="${paths[0]#/}"
  if is_abs_symlink "$rel"; then
    echo "unsquashfs: cat: $rel failed to resolve symbolic link" >&2
    exit 2
  fi
  cur="$image/$rel"
  for ((_ = 0; _ < 16; _++)); do
    [[ -L "$cur" ]] || break
    cur="$(dirname -- "$cur")/$(readlink -- "$cur")"
  done
  [[ -f "$cur" ]] || { echo "unsquashfs: cat: no matches for $rel" >&2; exit 2; }
  cat -- "$cur"
  exit 0
fi

if [[ "$mode" == list ]]; then
  ((${#paths[@]} > 0)) || paths=(.)
  for rel in "${paths[@]}"; do
    rel="${rel#/}"
    src="$image${rel:+/$rel}"
    if [[ ! -e "$src" && ! -L "$src" ]]; then
      echo "unsquashfs: no matches for $rel" >&2
      exit 2
    fi
    if [[ -d "$src" ]]; then
      (cd -- "$image" && find "${rel:-.}" | sed 's|^\./||')
    else
      printf '%s\n' "$rel"
    fi
  done
  exit 0
fi

if [[ "$mode" == list-long ]]; then
  # FAKE_NO_LL=1 mô phỏng bản squashfs-tools mới đổi định dạng `-ll`: checker
  # phải vẫn đọc được ảnh live nhờ đường dự phòng (trích entry rồi readlink).
  [[ -z "${FAKE_NO_LL:-}" ]] || exit 0
  ((${#paths[@]} > 0)) || paths=(.)
  for rel in "${paths[@]}"; do
    list_long "${rel#/}"
  done
  exit 0
fi

[[ -n "$dest" ]] || { echo "unsquashfs: missing -d" >&2; exit 1; }
((${#paths[@]} > 0)) || { echo "unsquashfs: nothing to extract" >&2; exit 1; }
for pattern in "${paths[@]}"; do
  pattern="${pattern#/}"
  matched=0
  while IFS= read -r rel; do
    matched=1
    extract_entry "$rel" || exit $?
  done < <(expand_pattern "$pattern")
  if ((!matched)); then
    echo "unsquashfs: no matches for $pattern" >&2
    exit 2
  fi
done
FAKE
chmod 0755 -- "$FAKE_BIN/unsquashfs"
export PATH="$FAKE_BIN:$PATH"

# --- Ảnh live giả ---------------------------------------------------------
build_fake_image() {
  local image="$1"
  rm -rf -- "$image"
  mkdir -p -- \
    "$image/etc/alsa/conf.d" \
    "$image/usr/share/alsa/alsa.conf.d" \
    "$image/usr/share/alsa/cards" \
    "$image/usr/lib/systemd/user" \
    "$image/usr/lib/spa-0.2/alsa" \
    "$image/usr/lib/alsa-lib" \
    "$image/usr/bin" \
    "$image/etc/systemd/user/default.target.d" \
    "$image/etc/systemd/user/default.target.wants" \
    "$image/etc/systemd/user/sockets.target.wants" \
    "$image/etc/systemd/user/pipewire.service.wants" \
    "$image/usr/local/bin"

  # pipewire 1.6.9: /usr/share/alsa/alsa.conf.d/*.conf là file thật,
  # /etc/alsa/conf.d/*.conf là SYMLINK TUYỆT ĐỐI (PKGBUILD: ln -st ...).
  cat >"$image/usr/share/alsa/alsa.conf.d/99-pipewire-default.conf" <<'EOF'
pcm.!default {
    type pipewire
    playback_node "-1"
    capture_node  "-1"
    hint {
        show on
        description "Default ALSA Output (currently PipeWire Media Server)"
    }
}

ctl.!default {
    type pipewire
}
EOF
  cat >"$image/usr/share/alsa/alsa.conf.d/50-pipewire.conf" <<'EOF'
# Add a specific named PipeWire pcm

defaults.pipewire.server "pipewire-0"

pcm.pipewire {
	type pipewire
}

ctl.pipewire {
	type pipewire
}
EOF
  ln -s /usr/share/alsa/alsa.conf.d/99-pipewire-default.conf \
    "$image/etc/alsa/conf.d/99-pipewire-default.conf"
  ln -s /usr/share/alsa/alsa.conf.d/50-pipewire.conf \
    "$image/etc/alsa/conf.d/50-pipewire.conf"

  local unit
  for unit in pipewire.service pipewire.socket pipewire-pulse.service \
    pipewire-pulse.socket wireplumber.service; do
    printf '[Unit]\nDescription=%s\n\n[Service]\nExecStart=/usr/bin/true\n' "$unit" \
      >"$image/usr/lib/systemd/user/$unit"
  done
  for binary in pipewire pipewire-pulse wireplumber wpctl pactl aplay \
    speaker-test alsamixer; do
    printf '#!/bin/sh\n' >"$image/usr/bin/$binary"
    chmod 0755 -- "$image/usr/bin/$binary"
  done
  # usr/bin của ảnh live có ~3350 entry (Steam, Mesa, Qt...). Nhồi thêm entry để
  # thư mục này to như thật: bản cũ của checker chặn mọi thư mục quá 500 entry
  # nên báo THIẾU toàn bộ binary trong đó dù chúng có thật.
  local i
  for ((i = 1; i <= 600; i++)); do
    : >"$image/usr/bin/zz-filler-$i"
  done
  printf 'ELF fake\n' >"$image/usr/lib/spa-0.2/alsa/libspa-alsa.so"
  printf 'ELF fake\n' >"$image/usr/lib/alsa-lib/libasound_module_pcm_pipewire.so"
  # Nhồi thêm >70 plugin trong usr/lib/alsa-lib và >100 file trong
  # usr/share/alsa/cards (gồm cả CMI8738-MC8.conf) như ảnh thật: nếu bước in
  # chẩn đoán khi thiếu file dùng `| head -60` dưới `set -Eeuo pipefail`, lệnh
  # đứng trước sẽ nhận SIGPIPE và làm cả script chết với exit code 141 trước khi
  # kịp in `::error::`.
  for ((i = 1; i <= 80; i++)); do
    printf 'ELF fake\n' >"$image/usr/lib/alsa-lib/libasound_module_pcm_extra_$i.so"
  done
  : >"$image/usr/share/alsa/cards/AACI.conf"
  : >"$image/usr/share/alsa/cards/CMI8738-MC8.conf"
  for ((i = 1; i <= 100; i++)); do
    : >"$image/usr/share/alsa/cards/Card-$i.conf"
  done

  cat >"$image/etc/systemd/user/default.target.d/10-anios-audio.conf" <<'EOF'
[Unit]
Wants=pipewire.service pipewire-pulse.service wireplumber.service anios-audio-setup.service
After=pipewire.service pipewire-pulse.service wireplumber.service
EOF
  ln -s /usr/lib/systemd/user/pipewire.service \
    "$image/etc/systemd/user/default.target.wants/pipewire.service"
  ln -s /usr/lib/systemd/user/pipewire-pulse.service \
    "$image/etc/systemd/user/default.target.wants/pipewire-pulse.service"
  ln -s /etc/systemd/user/anios-audio-setup.service \
    "$image/etc/systemd/user/default.target.wants/anios-audio-setup.service"
  ln -s /usr/lib/systemd/user/pipewire.socket \
    "$image/etc/systemd/user/sockets.target.wants/pipewire.socket"
  ln -s /usr/lib/systemd/user/pipewire-pulse.socket \
    "$image/etc/systemd/user/sockets.target.wants/pipewire-pulse.socket"
  ln -s /usr/lib/systemd/user/wireplumber.service \
    "$image/etc/systemd/user/pipewire.service.wants/wireplumber.service"

  printf '[Unit]\nDescription=AniOS live audio setup\n\n[Service]\nExecStart=/usr/local/bin/anios-audio-setup\n\n[Install]\nWantedBy=default.target\n' \
    >"$image/etc/systemd/user/anios-audio-setup.service"

  printf '#!/usr/bin/env bash\nset -e\necho anios-audio-setup\n' \
    >"$image/usr/local/bin/anios-audio-setup"
  printf '#!/usr/bin/env bash\nset -e\necho anios-audio-check\n' \
    >"$image/usr/local/bin/anios-audio-check"
  chmod 0755 -- "$image/usr/local/bin/anios-audio-setup" "$image/usr/local/bin/anios-audio-check"
}

PKGLIST="$SANDBOX/anios-pkglist.txt"
write_pkglist() {
  cat >"$PKGLIST" <<'EOF'
alsa-card-profiles 1:1.2.12-1
alsa-utils 1.2.14-2
libpulse 17.0+r98+gb096704c0-1
pipewire 1:1.6.9-1
pipewire-alsa 1:1.6.9-1
pipewire-audio 1:1.6.9-1
pipewire-pulse 1:1.6.9-1
rtkit 0.13-3
wireplumber 1:0.5.11-1
EOF
}
write_pkglist

IMAGE="$SANDBOX/airootfs.sfs"
build_fake_image "$IMAGE"

run_checker() { "$CHECKER" "$IMAGE" "$PKGLIST" >"$SANDBOX/out.txt" 2>&1; }

failures=0
expect_pass() {
  local label="$1"
  if run_checker; then
    # Không chỉ "không chết": một ảnh live hợp lệ không được có dòng THIẾU nào,
    # cũng không được có dấu hiệu bỏ qua thư mục vì "quá lớn" như bản cũ.
    if grep -qE 'THIẾU|quá lớn|bỏ qua' "$SANDBOX/out.txt"; then
      echo "  FAIL  $label (script PASS nhưng vẫn báo thiếu/bỏ qua thứ gì đó)"
      sed 's/^/        /' "$SANDBOX/out.txt"
      failures=$((failures + 1))
      return 0
    fi
    echo "  OK    $label"
  else
    echo "  FAIL  $label (mong đợi PASS)"
    sed 's/^/        /' "$SANDBOX/out.txt"
    failures=$((failures + 1))
  fi
}
expect_fail() {
  local label="$1" rc=0
  run_checker || rc=$?
  if ((rc == 0)); then
    echo "  FAIL  $label (mong đợi FAIL nhưng script lại PASS)"
    failures=$((failures + 1))
  elif ((rc == 141)); then
    echo "  FAIL  $label (script chết vì SIGPIPE / exit code 141 thay vì thoát 1 có kiểm soát)"
    sed 's/^/        /' "$SANDBOX/out.txt"
    failures=$((failures + 1))
  elif ((rc != 1)); then
    echo "  FAIL  $label (mong đợi exit 1 nhưng trả exit $rc)"
    sed 's/^/        /' "$SANDBOX/out.txt"
    failures=$((failures + 1))
  elif ! grep -q '^::error::' "$SANDBOX/out.txt"; then
    echo "  FAIL  $label (thoát $rc nhưng không in thông báo ::error::)"
    sed 's/^/        /' "$SANDBOX/out.txt"
    failures=$((failures + 1))
  else
    echo "  OK    $label"
  fi
}

echo "--- unsquashfs giả mô phỏng đúng hành vi của squashfs-tools ---"
# Nếu unsquashfs giả đi theo symlink tuyệt đối thì toàn bộ bài kiểm tra vô nghĩa:
# lỗi thật nằm ở chỗ `unsquashfs -cat` KHÔNG đi theo được loại symlink này.
if unsquashfs -cat "$IMAGE" etc/alsa/conf.d/99-pipewire-default.conf >/dev/null 2>&1; then
  echo "  FAIL  unsquashfs giả không mô phỏng việc -cat từ chối symlink tuyệt đối" >&2
  exit 1
fi
echo "  OK    unsquashfs -cat từ chối symlink tuyệt đối (exit != 0)"
probe="$SANDBOX/probe"
rm -rf -- "$probe"
mkdir -p -- "$probe"
if unsquashfs -q -no-progress -d "$probe" "$IMAGE" \
  etc/alsa/conf.d/99-pipewire-default.conf >/dev/null 2>&1 &&
  [[ -L "$probe/etc/alsa/conf.d/99-pipewire-default.conf" ]]; then
  echo "  OK    unsquashfs -d trích chính symlink tuyệt đối (không đi theo, không đọc nội dung)"
else
  echo "  FAIL  unsquashfs giả không trích được symlink tuyệt đối bằng -d" >&2
  exit 1
fi
if unsquashfs -cat "$IMAGE" usr/share/alsa/alsa.conf.d/50-pipewire.conf |
  grep -qF 'pcm.pipewire'; then
  echo "  OK    unsquashfs -cat vẫn đọc được file thật"
else
  echo "  FAIL  unsquashfs giả không đọc được file thật" >&2
  exit 1
fi

# `unsquashfs -ll` là thứ check-live-audio.sh dùng để nhìn thấy symlink tuyệt đối
# mà không phải trích thư mục cha. Bản giả phải in đúng định dạng đó (quyền,
# chủ/nhóm, kích thước, ngày, giờ, đường dẫn, " -> đích") và không được trích gì.
long_entry="$(unsquashfs -ll "$IMAGE" etc/alsa/conf.d/99-pipewire-default.conf)"
if grep -qF 'lrwxrwxrwx' <<<"$long_entry" &&
  grep -qF 'squashfs-root/etc/alsa/conf.d/99-pipewire-default.conf' <<<"$long_entry" &&
  grep -qF ' -> /usr/share/alsa/alsa.conf.d/99-pipewire-default.conf' <<<"$long_entry"; then
  echo "  OK    -ll in ra loại entry và đích symlink (không trích, không đi theo)"
else
  echo "  FAIL  unsquashfs giả không mô phỏng định dạng của -ll:" >&2
  printf '%s\n' "$long_entry" | sed 's/^/        /' >&2
  exit 1
fi
if grep -qF 'squashfs-root/usr/bin/zz-filler-1' <<<"$(unsquashfs -ll "$IMAGE" usr/bin/pipewire)"; then
  echo "  FAIL  -ll trên một file lại liệt kê cả thư mục cha" >&2
  exit 1
fi
echo "  OK    -ll trên một file không liệt kê các entry khác trong thư mục cha"

# Lỗi chí mạng "File exists" của dir_scan: chỉ thư mục đích gốc được phép tồn tại
# sẵn, nên trích lần thứ hai vào cùng một đích luôn thất bại. Đây chính là lý do
# bản cũ báo THIẾU gần như mọi file sau file đầu tiên.
rm -rf -- "$probe"
mkdir -p -- "$probe"
if unsquashfs -q -no-progress -d "$probe" "$IMAGE" usr/bin/pipewire >/dev/null 2>&1; then
  echo "  OK    lần trích đầu vào một đích mới thành công"
else
  echo "  FAIL  unsquashfs giả không trích được file thật" >&2
  exit 1
fi
if err="$(unsquashfs -q -no-progress -d "$probe" "$IMAGE" usr/bin/wpctl 2>&1)"; then
  echo "  FAIL  unsquashfs giả không mô phỏng lỗi 'File exists' của dir_scan" >&2
  exit 1
fi
if grep -qF 'because File exists' <<<"$err"; then
  echo "  OK    trích lần hai vào cùng đích thất bại đúng như unsquashfs thật (dir_scan: ... because File exists)"
else
  echo "  FAIL  thông báo lỗi của unsquashfs giả khác unsquashfs thật: $err" >&2
  exit 1
fi

echo "--- check-live-audio.sh trên ảnh live giả hợp lệ ---"
expect_pass "đủ dàn âm thanh PipeWire và cấu hình AniOS"
# usr/bin có 600 entry giả + binary thật: bản cũ bỏ qua cả thư mục này (ngưỡng
# 500 entry) và báo thiếu toàn bộ binary bên trong.
expect_pass "nhận đủ binary nằm trong usr/bin khổng lồ, không bỏ qua thư mục nào"

echo "--- check-live-audio.sh phải bắt được ảnh live hỏng ---"
build_fake_image "$IMAGE"
rm -f -- "$IMAGE/etc/alsa/conf.d/99-pipewire-default.conf"
expect_fail "thiếu /etc/alsa/conf.d/99-pipewire-default.conf"

build_fake_image "$IMAGE"
rm -f -- "$IMAGE/usr/share/alsa/alsa.conf.d/99-pipewire-default.conf"
expect_fail "symlink ALSA trỏ tới file không tồn tại"

build_fake_image "$IMAGE"
cat >"$IMAGE/usr/share/alsa/alsa.conf.d/99-pipewire-default.conf" <<'EOF'
defaults.pcm.!card pipewire
defaults.ctl.!card pipewire
EOF
expect_fail "nội dung ALSA mặc định không đưa PCM/CTL về PipeWire"

# File nằm sâu trong thư mục khổng lồ: đúng kiểu báo lỗi mà bản cũ gây ra.
# Đồng thời kiểm tra mục chẩn đoán "--- những gì thật sự có trong ảnh ở các thư
# mục âm thanh ---" không chết vì SIGPIPE (exit code 141) khi có >100 file trong
# usr/share/alsa/cards và >70 plugin trong usr/lib/alsa-lib.
build_fake_image "$IMAGE"
rm -f -- "$IMAGE/usr/bin/wpctl"
expect_fail "thiếu wpctl trong usr/bin khổng lồ (không chết với exit code 141 khi in chẩn đoán)"
if ! grep -qF -- '--- những gì thật sự có trong ảnh ở các thư mục âm thanh ---' "$SANDBOX/out.txt"; then
  echo "  FAIL  thiếu wpctl nhưng không in danh sách chẩn đoán các thư mục âm thanh"
  failures=$((failures + 1))
elif grep -qF 'CMI8738-MC8.conf' "$SANDBOX/out.txt"; then
  echo "  FAIL  danh sách chẩn đoán bị ngập bởi usr/share/alsa/cards/CMI8738-MC8.conf"
  failures=$((failures + 1))
else
  echo "  OK    danh sách chẩn đoán in đủ cấu hình âm thanh, bỏ qua usr/share/alsa/cards và không bị SIGPIPE 141"
fi

build_fake_image "$IMAGE"
rm -f -- "$IMAGE/usr/lib/systemd/user/pipewire.socket"
expect_fail "thiếu unit pipewire.socket dù pipewire.service vẫn còn"

build_fake_image "$IMAGE"
rm -f -- "$IMAGE/etc/systemd/user/pipewire.service.wants/wireplumber.service"
ln -s /usr/lib/systemd/user/khong-ton-tai.service \
  "$IMAGE/etc/systemd/user/pipewire.service.wants/wireplumber.service"
expect_fail "symlink bật unit âm thanh trỏ tới unit không tồn tại"

build_fake_image "$IMAGE"
rm -f -- "$IMAGE/etc/systemd/user/default.target.d/10-anios-audio.conf"
expect_fail "thiếu drop-in default.target của AniOS"

build_fake_image "$IMAGE"
chmod 0644 -- "$IMAGE/usr/local/bin/anios-audio-setup"
expect_fail "anios-audio-setup mất bit thực thi"

build_fake_image "$IMAGE"
printf 'pipewire 1:1.6.9-1\n' >"$PKGLIST"
expect_fail "ảnh live thiếu gói pipewire-alsa"
write_pkglist
sed -i '/^libpulse /d' "$PKGLIST"
expect_fail "ảnh live thiếu gói libpulse (cung cấp pactl)"
write_pkglist

echo "--- nếu squashfs-tools đổi định dạng \`-ll\` ---"
# check-live-audio.sh dùng `-ll` để nhìn thấy symlink tuyệt đối mà không phải
# trích thư mục cha, nhưng nó không được PHỤ THUỘC vào định dạng đó: khi `-ll`
# không dùng được, script phải lui về cách cũ (trích entry rồi readlink — chính
# vì `-d` giữ nguyên symlink tuyệt đối) và vẫn kết luận đúng.
build_fake_image "$IMAGE"
if FAKE_NO_LL=1 run_checker; then
  if grep -qE 'THIẾU|quá lớn|bỏ qua' "$SANDBOX/out.txt"; then
    echo "  FAIL  mất thông tin khi -ll không dùng được"
    sed 's/^/        /' "$SANDBOX/out.txt"
    failures=$((failures + 1))
  else
    echo "  OK    vẫn đọc đủ ảnh live (dùng đường dự phòng, không cần định dạng -ll)"
  fi
else
  echo "  FAIL  hỏng khi định dạng -ll đổi (mất đường dự phòng):"
  sed 's/^/        /' "$SANDBOX/out.txt"
  failures=$((failures + 1))
fi

echo "--- symlink tương đối (ít gặp nhưng vẫn phải đọc được) ---"
build_fake_image "$IMAGE"
rm -f -- "$IMAGE/etc/alsa/conf.d/50-pipewire.conf"
# Từ etc/alsa/conf.d/ phải lên 3 cấp mới tới gốc của ảnh.
ln -s ../../../usr/share/alsa/alsa.conf.d/50-pipewire.conf \
  "$IMAGE/etc/alsa/conf.d/50-pipewire.conf"
expect_pass "symlink tương đối tới file cấu hình ALSA"

build_fake_image "$IMAGE"
rm -f -- "$IMAGE/etc/alsa/conf.d/50-pipewire.conf"
ln -s ../../../../../etc/passwd "$IMAGE/etc/alsa/conf.d/50-pipewire.conf"
expect_fail "symlink trỏ ra ngoài gốc của ảnh"

if ((failures)); then
  echo "FAIL: $failures trường hợp sai trong bài tự kiểm tra" >&2
  exit 1
fi
echo "PASS: scripts/check-live-audio.sh xử lý đúng symlink tuyệt đối, thư mục khổng lồ và bắt được ảnh live thiếu âm thanh"
