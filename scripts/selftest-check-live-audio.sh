#!/usr/bin/env bash
# Tự kiểm tra scripts/check-live-audio.sh mà không cần dựng ISO.
#
# `unsquashfs` thật chỉ có trên Arch Linux (và chỉ chạy được trên squashfs
# thật), nên script này dựng một bản unsquashfs giả mô phỏng đúng hai hành vi
# mà check-live-audio.sh dựa vào:
#
#   unsquashfs [-q] [-no-progress] -d DIR IMAGE PATH...
#       trích entry, GIỮ NGUYÊN symlink (không đi theo)
#   unsquashfs -cat IMAGE PATH
#       in nội dung file; TỪ CHỐI symlink tuyệt đối và trả exit code 2
#       (đúng như squashfs-tools, unsquashfs.c, cat_scan()/SQUASHFS_SYMLINK_TYPE
#        với set_exit_code mặc định TRUE)
#
# Trên cây thư mục giả đó script dựng lại đúng bố cục của ảnh live: hai file
# /etc/alsa/conf.d/*.conf là symlink tuyệt đối do pipewire-alsa/pipewire-audio
# cài, và các symlink *.wants/* do systemd enable tạo ra. Nhờ vậy kiểm tra được
# logic của check-live-audio.sh (đi theo symlink, báo thiếu file, so nội dung)
# ngay trên máy thường, trong vài giây.
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
image="" dest="" mode=extract
paths=()
while (($#)); do
  case "$1" in
    -q | -no-progress) shift ;;
    -cat) mode=cat; shift ;;
    -l | -ll) mode=list; shift ;;
    -d) dest="${2:?}"; shift 2 ;;
    -*) shift ;;
    *) if [[ -z "$image" ]]; then image="$1"; else paths+=("$1"); fi; shift ;;
  esac
done
[[ -n "$image" && -d "$image" ]] || { echo "unsquashfs: cannot open $image" >&2; exit 1; }

# unsquashfs thật từ chối mọi đường dẫn có thành phần cuối là symlink tuyệt đối,
# ở cả -cat lẫn -d (squashfs-tools, nhánh SQUASHFS_SYMLINK_TYPE của cat_scan và
# follow_path/follow_extract_paths).
is_abs_symlink() {
  local entry="$image/${1#/}"
  [[ -L "$entry" ]] || return 1
  [[ "$(readlink -- "$entry")" == /* ]]
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

[[ -n "$dest" ]] || { echo "unsquashfs: missing -d" >&2; exit 1; }
((${#paths[@]} > 0)) || { echo "unsquashfs: nothing to extract" >&2; exit 1; }
for rel in "${paths[@]}"; do
  rel="${rel#/}"
  src="$image/$rel"
  dst="$dest/$rel"
  if [[ ! -e "$src" && ! -L "$src" ]]; then
    echo "unsquashfs: no matches for $rel" >&2
    exit 2
  fi
  if is_abs_symlink "$rel"; then
    echo "unsquashfs: follow_extract_paths: $rel failed to resolve symbolic link" >&2
    exit 2
  fi
  mkdir -p -- "$(dirname -- "$dst")"
  rm -rf -- "$dst"
  cp -a -- "$src" "$dst"
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
  printf 'ELF fake\n' >"$image/usr/lib/spa-0.2/alsa/libspa-alsa.so"
  printf 'ELF fake\n' >"$image/usr/lib/alsa-lib/libasound_module_pcm_pipewire.so"

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
cat >"$PKGLIST" <<'EOF'
alsa-card-profiles 1:1.2.12-1
alsa-utils 1.2.14-2
pipewire 1:1.6.9-1
pipewire-alsa 1:1.6.9-1
pipewire-audio 1:1.6.9-1
pipewire-pulse 1:1.6.9-1
rtkit 0.13-3
wireplumber 1:0.5.11-1
EOF

IMAGE="$SANDBOX/airootfs.sfs"
build_fake_image "$IMAGE"

run_checker() { "$CHECKER" "$IMAGE" "$PKGLIST" >"$SANDBOX/out.txt" 2>&1; }

failures=0
expect_pass() {
  local label="$1"
  if run_checker; then
    echo "  OK    $label"
  else
    echo "  FAIL  $label (mong đợi PASS)"
    sed 's/^/        /' "$SANDBOX/out.txt"
    failures=$((failures + 1))
  fi
}
expect_fail() {
  local label="$1"
  if run_checker; then
    echo "  FAIL  $label (mong đợi FAIL nhưng script lại PASS)"
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
if unsquashfs -q -no-progress -d "$probe" "$IMAGE"   etc/alsa/conf.d/99-pipewire-default.conf >/dev/null 2>&1; then
  echo "  FAIL  unsquashfs giả không mô phỏng việc -d từ chối symlink tuyệt đối" >&2
  exit 1
fi
echo "  OK    unsquashfs -d cũng từ chối symlink tuyệt đối (phải trích cả thư mục)"
unsquashfs -q -no-progress -d "$probe" "$IMAGE" etc/alsa/conf.d >/dev/null &&
  [[ -L "$probe/etc/alsa/conf.d/99-pipewire-default.conf" ]] &&
  echo "  OK    unsquashfs -d giữ nguyên symlink khi trích cả thư mục"
if unsquashfs -cat "$IMAGE" usr/share/alsa/alsa.conf.d/50-pipewire.conf |
  grep -qF 'pcm.pipewire'; then
  echo "  OK    unsquashfs -cat vẫn đọc được file thật"
else
  echo "  FAIL  unsquashfs giả không đọc được file thật" >&2
  exit 1
fi

echo "--- check-live-audio.sh trên ảnh live giả hợp lệ ---"
expect_pass "đủ dàn âm thanh PipeWire và cấu hình AniOS"

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
cat >"$PKGLIST" <<'EOF'
alsa-card-profiles 1:1.2.12-1
alsa-utils 1.2.14-2
pipewire 1:1.6.9-1
pipewire-alsa 1:1.6.9-1
pipewire-audio 1:1.6.9-1
pipewire-pulse 1:1.6.9-1
rtkit 0.13-3
wireplumber 1:0.5.11-1
EOF

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
echo "PASS: scripts/check-live-audio.sh xử lý đúng symlink tuyệt đối và bắt được ảnh live thiếu âm thanh"
