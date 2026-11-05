#!/usr/bin/env bash
# Dựng cả BA bản ISO của họ AniOS trong một lần chạy:
#
#   anios      bản chính: Hyprland, Steam tự khởi động, stack AI, lưu trữ trên USB
#   aniterals  bản amnesic: chạy trong RAM, Tor, không Steam, không lưu trữ
#   anix       bản đầy đủ nhất: cả tầng Proton/Proton GE, Steam tự khởi động
#
# Đây là lớp bọc mỏng quanh `scripts/build-iso.sh --edition <tên>`: nó chạy
# scripts/check-profile.sh đúng MỘT lần (thay vì ba lần), tách work dir theo từng
# bản để không bản nào kế thừa airootfs của bản trước, rồi in bảng tổng kết.
#
# Yêu cầu giống hệt build-iso.sh: máy Arch Linux x86_64 đã cập nhật, archiso, mạng
# và quyền root. Ba bản dựng tuần tự nên cần đĩa cho cả ba work dir — chuẩn bị
# khoảng 75 GiB chỗ trống.
#
# Cách dùng:
#   sudo ./scripts/build-all-editions.sh
#   sudo ./scripts/build-all-editions.sh --output /duong-dan/iso
#   sudo ./scripts/build-all-editions.sh --only anix        # chỉ dựng một bản
#   sudo ./scripts/build-all-editions.sh --no-aur           # truyền xuống build-iso.sh
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ISO="$ROOT_DIR/scripts/build-iso.sh"
EDITIONS_DIR="$ROOT_DIR/profile/editions"

OUT_DIR="$ROOT_DIR/out"
WORK_BASE="$ROOT_DIR/work"
ONLY=""
SKIP_CHECKS=0
PASSTHROUGH=()

usage() {
  cat <<'EOF'
Usage: sudo ./scripts/build-all-editions.sh [--output DIR] [--work-base DIR]
                                            [--only EDITION] [--skip-checks]
                                            [-- build-iso.sh options...]

Build the anios, aniterals and anix ISOs one after another. Options other than
the ones listed here are passed through to scripts/build-iso.sh (for example
--no-aur or --clean).

  --only EDITION   build a single edition instead of all three
  --skip-checks    do not run scripts/check-profile.sh first
EOF
}

while (($#)); do
  case "$1" in
    -o|--output)
      (($# >= 2)) || { echo "Missing directory after $1" >&2; exit 2; }
      OUT_DIR="$2"; shift 2 ;;
    --work-base)
      (($# >= 2)) || { echo "Missing directory after $1" >&2; exit 2; }
      WORK_BASE="$2"; shift 2 ;;
    --only)
      (($# >= 2)) || { echo "Missing edition after $1" >&2; exit 2; }
      ONLY="$2"; shift 2 ;;
    --skip-checks)
      SKIP_CHECKS=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    --)
      shift; PASSTHROUGH+=("$@"); break ;;
    *)
      # Mọi tuỳ chọn lạ được chuyển nguyên vẹn cho build-iso.sh, để script này
      # không phải học lại mỗi lần build-iso.sh thêm tuỳ chọn mới.
      PASSTHROUGH+=("$1"); shift ;;
  esac
done

[[ -x "$BUILD_ISO" ]] || { echo "Missing or not executable: $BUILD_ISO" >&2; exit 1; }

# Danh sách bản cần dựng: lấy từ những thư mục edition thật sự có edition.conf,
# không hardcode tên, để thêm bản mới là không phải sửa script này.
EDITIONS=()
for edition_dir in "$EDITIONS_DIR"/*/; do
  edition_id="${edition_dir%/}"
  edition_id="${edition_id##*/}"
  [[ -s "$edition_dir/edition.conf" ]] || continue
  EDITIONS+=("$edition_id")
done
(( ${#EDITIONS[@]} )) || { echo "No edition found in $EDITIONS_DIR" >&2; exit 1; }

if [[ -n "$ONLY" ]]; then
  found=0
  for edition_id in "${EDITIONS[@]}"; do
    [[ "$edition_id" == "$ONLY" ]] && found=1
  done
  (( found )) || {
    echo "Unknown edition: $ONLY (available: ${EDITIONS[*]})" >&2
    exit 2
  }
  EDITIONS=("$ONLY")
fi

if (( ! SKIP_CHECKS )); then
  # Kiểm tra profile một lần cho cả ba bản: nội dung kiểm tra không phụ thuộc
  # edition đang dựng, chạy lại ba lần chỉ mất thời gian.
  bash "$ROOT_DIR/scripts/check-profile.sh"
fi

mkdir -p -- "$OUT_DIR"
built=()
failed=()

for edition_id in "${EDITIONS[@]}"; do
  printf '\n===== [%s] Building edition %s =====\n' "$(date +%H:%M:%S)" "$edition_id"
  if "$BUILD_ISO" --edition "$edition_id" \
      --output "$OUT_DIR" \
      --work "$WORK_BASE-$edition_id" \
      --skip-checks \
      ${PASSTHROUGH[@]+"${PASSTHROUGH[@]}"}; then
    built+=("$edition_id")
  else
    echo "Edition $edition_id failed to build" >&2
    failed+=("$edition_id")
  fi
done

printf '\n===== Summary =====\n'
for edition_id in "${EDITIONS[@]}"; do
  iso="$(ls -1 "$OUT_DIR"/${edition_id}-*.iso "$OUT_DIR"/*${edition_id}*.iso 2>/dev/null | head -n 1 || true)"
  if [[ -n "$iso" ]]; then
    printf '  %-10s %s  (%s)\n' "$edition_id" "$(basename -- "$iso")" \
      "$(du -h -- "$iso" | cut -f1)"
  else
    printf '  %-10s (no ISO found in %s)\n' "$edition_id" "$OUT_DIR"
  fi
done
printf 'Built: %s\n' "${built[*]:-none}"
if (( ${#failed[@]} )); then
  printf 'Failed: %s\n' "${failed[*]}" >&2
  exit 1
fi
echo "All requested editions built into $OUT_DIR"
