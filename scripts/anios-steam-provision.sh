#!/usr/bin/env bash
# Nướng Proton (và Proton GE) + Steam Runtime vào ảnh live lúc dựng ISO.
#
# Script này chạy BÊN TRONG chroot airootfs, do hook customize_airootfs.sh gọi —
# cùng cơ chế với scripts/anios-aur-build.sh. Kết quả nằm ở
# /usr/share/anios/steam-cache/ và được anios-steam-setup giải nén vào thư mục
# Steam của người dùng ở lần mở Steam đầu tiên (offline, xem script đó).
#
# Mức nướng (tham số --level):
#   standard  Proton chính thức (bản mới nhất) + Steam Runtime
#   full      standard + Proton GE (bản mới nhất)
#   off       không làm gì (AniTails)
#
# Tải gì:
#   * Proton / Proton GE: tarball dist từ GitHub Releases, tên bản phát hành do
#     GitHub API trả về (hoặc chốt bằng --proton-tag / --proton-ge-tag). Đây là
#     nguồn chính chủ của ValveSoftware/Proton và GloriousEggroll/proton-ge-custom.
#   * Steam Runtime: TẮT mặc định. Valve phát hành runtime Scout theo snapshot có
#     build-id, và đường dẫn snapshot thay đổi theo thời gian; đoán URL rồi nướng
#     một bản sai vào ảnh tệ hơn là để Steam tự tải bản đúng ở lần mở đầu tiên.
#     Muốn nướng thì truyền --runtime-url (hoặc đặt ANIOS_STEAM_RUNTIME_URL) trỏ
#     tới tarball steamrt_scout_*_amd64.tar.xz đã kiểm tra.
#
# Lỗi tải KHÔNG làm hỏng bản dựng: một lượt dựng mất hàng chục phút, và ảnh thiếu
# runtime vẫn mở được Steam (client tự tải khi có mạng). Mỗi mục hỏng in một
# annotation ::warning cho GitHub Actions rồi bỏ qua. Riêng trường hợp KHÔNG có
# gì được nướng ở mức standard/full thì in ::warning tổng hợp để người dựng biết.
set -Eeuo pipefail

DEST=/usr/share/anios/steam-cache
LEVEL=standard
PROTON_TAG=
PROTON_GE_TAG=
RUNTIME_URL="${ANIOS_STEAM_RUNTIME_URL:-}"
GITHUB_API="${ANIOS_GITHUB_API:-https://api.github.com}"

usage() {
  cat <<'EOF'
Usage: anios-steam-provision.sh [--level standard|full|off]
                                [--proton-tag TAG] [--proton-ge-tag TAG]
                                [--runtime-url URL] [--dest DIR]

Bake Proton / Proton GE / Steam Runtime tarballs into the live image so Steam
works offline. Runs inside the airootfs chroot during the ISO build.
EOF
}

while (($#)); do
  case "$1" in
    --level) LEVEL="${2:-}"; shift 2 ;;
    --proton-tag) PROTON_TAG="${2:-}"; shift 2 ;;
    --proton-ge-tag) PROTON_GE_TAG="${2:-}"; shift 2 ;;
    --runtime-url) RUNTIME_URL="${2:-}"; shift 2 ;;
    --dest) DEST="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "$LEVEL" == off ]]; then
  echo "anios-steam-provision: level=off, không nướng gì (bản này không có Steam)"
  exit 0
fi
if [[ "$LEVEL" != standard && "$LEVEL" != full ]]; then
  echo "anios-steam-provision: level không rõ: $LEVEL (chọn standard, full hoặc off)" >&2
  exit 2
fi

for tool in curl tar sha256sum; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "anios-steam-provision: thiếu $tool trong chroot, bỏ qua việc nướng runtime" >&2
    exit 0
  }
done

notice() {
  printf 'anios-steam-provision: %s\n' "$*"
  if [[ "${GITHUB_ACTIONS:-false}" == true ]]; then
    printf '::notice title=AniOS Steam::%s\n' "$*"
  fi
}
warn() {
  printf 'anios-steam-provision: %s\n' "$*" >&2
  if [[ "${GITHUB_ACTIONS:-false}" == true ]]; then
    printf '::warning title=AniOS Steam::%s\n' "$*"
  fi
}

install -d -m 0755 -- "$DEST/proton" "$DEST/proton-ge" "$DEST/runtime"

baked=()
manifest="$DEST/manifest"
: >"$manifest"

# --- Tên bản phát hành mới nhất từ GitHub API ------------------------------
# Unauthenticated bị giới hạn 60 lượt/giờ theo IP; truyền GITHUB_TOKEN (CI có
# secrets.GITHUB_TOKEN) thì hạn mức cao hơn nhiều.
github_latest_tag() {
  local repo="$1"
  curl -fsSL --retry 3 --max-time 60 \
    ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
    -H 'Accept: application/vnd.github+json' \
    "$GITHUB_API/repos/$repo/releases/latest" 2>/dev/null |
    sed -nE 's/^[[:space:]]*"tag_name":[[:space:]]*"([^"]+)".*/\1/p' | head -n 1
}

# Tải một asset của GitHub Release. $1 repo, $2 tag, $3 mẫu tên file.
fetch_release_asset() {
  local repo="$1" tag="$2" pattern="$3" url out="$4"
  url="$(curl -fsSL --retry 3 --max-time 60 \
    ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
    -H 'Accept: application/vnd.github+json' \
    "$GITHUB_API/repos/$repo/releases/tags/$tag" 2>/dev/null |
    sed -nE 's#^[[:space:]]*"browser_download_url":[[:space:]]*"([^"]+)".*#\1#p' |
    grep -E "$pattern" | head -n 1)"
  [[ -n "$url" ]] || return 1
  notice "tải $url"
  curl -fSL --retry 3 --retry-delay 3 --max-time 1800 -o "$out" "$url"
}

# --- Proton chính thức ------------------------------------------------------
provision_proton() {
  local kind="$1" repo="$2" tag_var="$3" pattern="$4"
  local tag tmp out
  tag="${!tag_var}"
  if [[ -z "$tag" ]]; then
    tag="$(github_latest_tag "$repo")" || true
  fi
  if [[ -z "$tag" ]]; then
    warn "không đọc được bản phát hành mới nhất của $repo; bỏ qua $kind"
    return 0
  fi
  notice "$kind: dùng bản $tag"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/anios-steam.XXXXXX")"
  out="$tmp/$kind.tar.gz"
  if ! fetch_release_asset "$repo" "$tag" "$pattern" "$out"; then
    warn "không tải được tarball $kind $tag; bỏ qua (Steam sẽ tự tải khi có mạng)"
    rm -rf -- "$tmp"
    return 0
  fi
  if ! tar -tzf "$out" >/dev/null 2>&1; then
    warn "tarball $kind $tag không hợp lệ; bỏ qua"
    rm -rf -- "$tmp"
    return 0
  fi
  # Tên thư mục đích: bỏ tiền tố "proton-" để compatibilitytools.d ngắn gọn, nhưng
  # giữ nguyên tên gốc nếu nó đã khác khuôn đó (GE-Proton9-11 chẳng hạn).
  local name="${tag#proton-}"
  mv -- "$out" "$DEST/proton/$name.tar.gz"
  printf '%s|%s|proton/%s.tar.gz\n' "$kind" "$name" "$name" >>"$manifest"
  baked+=("$kind $name")
  rm -rf -- "$tmp"
}

if [[ "$LEVEL" == standard || "$LEVEL" == full ]]; then
  provision_proton proton ValveSoftware/Proton PROTON_TAG 'proton-.*\.tar\.gz$'
fi
if [[ "$LEVEL" == full ]]; then
  provision_proton proton-ge GloriousEggroll/proton-ge-custom PROTON_GE_TAG 'GE-Proton.*\.tar\.gz$'
fi

# --- Steam Runtime (tắt mặc định, xem ghi chú ở đầu file) -------------------
if [[ -n "$RUNTIME_URL" ]]; then
  runtime_tmp="$(mktemp -d "${TMPDIR:-/tmp}/anios-steamrt.XXXXXX")"
  runtime_out="$runtime_tmp/runtime.tar.xz"
  notice "tải Steam Runtime từ $RUNTIME_URL"
  if curl -fSL --retry 3 --max-time 1800 -o "$runtime_out" "$RUNTIME_URL" &&
     tar -tJf "$runtime_out" >/dev/null 2>&1; then
    mv -- "$runtime_out" "$DEST/runtime/steam-runtime.tar.xz"
    printf 'steam-runtime|steam-runtime|runtime/steam-runtime.tar.xz\n' >>"$manifest"
    baked+=("steam-runtime")
  else
    warn "Steam Runtime tải về không hợp lệ; bỏ qua"
  fi
  rm -rf -- "$runtime_tmp"
else
  notice "không nướng Steam Runtime (không có --runtime-url); Steam tự tải runtime ở lần mở đầu tiên"
fi

chmod -R a+rX -- "$DEST" 2>/dev/null || true

if (( ${#baked[@]} == 0 )); then
  warn "mức '$LEVEL' nhưng không nướng được gì; ISO vẫn dựng tiếp, Steam sẽ tự tải khi có mạng"
  rm -rf -- "$DEST"
  exit 0
fi

notice "đã nướng vào $DEST: ${baked[*]}"
printf 'anios-steam-provision: manifest của ảnh:\n'
sed 's/^/  /' "$manifest"
exit 0
