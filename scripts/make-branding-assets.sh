#!/usr/bin/env bash
# Dựng lại các ảnh thương hiệu AniOS trong profile/branding/.
#
# Script chỉ cần ImageMagick + font DejaVu. Ảnh đã được commit sẵn vào
# repository nên bước này là tuỳ chọn; chỉ chạy khi muốn đổi thiết kế.
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BRAND_DIR="$ROOT_DIR/profile/branding"
FONT_BOLD="${FONT_BOLD:-/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf}"
FONT_REGULAR="${FONT_REGULAR:-/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf}"

if ! command -v convert >/dev/null 2>&1; then
  echo "ImageMagick (convert) is required to regenerate the AniOS artwork." >&2
  exit 1
fi
for font in "$FONT_BOLD" "$FONT_REGULAR"; do
  [[ -f "$font" ]] || { echo "Missing font: $font" >&2; exit 1; }
done

mkdir -p -- "$BRAND_DIR"

# Nền tối kèm một quầng sáng xanh lam mờ, dùng chung cho mọi ảnh.
background() {
  local width="$1" height="$2" glow="$3"
  convert -size "${width}x${height}" "gradient:#171a22-#0d0f15" \
    \( -size "${width}x${height}" xc:none \
       -fill "#7aa2f7" \
       -draw "circle $((width / 2)),$((height / 2)) $((width / 2)),$((height / 2 + glow))" \
       -blur "0x$((glow / 4))" -channel A -evaluate multiply 0.35 +channel \) \
    -compose over -composite
}

# Wallpaper của phiên live (swaybg) và màn hình khoá phiên.
background 2560 1440 430 |
  convert - -fill "#7aa2f7" -draw "rectangle 1130,1090 1430,1096" \
    -font "$FONT_BOLD" -fill "#dfe4ef" -pointsize 380 -kerning 14 \
    -gravity center -annotate '+0-120' 'AniOS' \
    -font "$FONT_REGULAR" -fill "#8a93a8" -pointsize 58 -kerning 4 \
    -gravity center -annotate '+0+180' 'Hyprland live gaming desktop' \
    -font "$FONT_REGULAR" -fill "#6b7385" -pointsize 42 \
    -gravity south -annotate '+0+110' 'Arch Linux based' \
    -strip -depth 8 -dither Riemersma -colors 200 "$BRAND_DIR/wallpaper.png"

# Nền menu khởi động Syslinux (vesamenu, 640x480 như splash của releng).
# Chữ ký nằm ở góc dưới bên phải để không đè lên danh sách menu phía trên.
background 640 480 108 |
  convert - -fill "#7aa2f7" -draw "rectangle 415,430 425,444" \
    -font "$FONT_BOLD" -fill "#aab2c5" -pointsize 30 -kerning 1 \
    -gravity southeast -annotate '+26+20' 'AniOS' \
    -strip -depth 8 -colors 128 "$BRAND_DIR/syslinux-splash.png"

identify "$BRAND_DIR/wallpaper.png" "$BRAND_DIR/syslinux-splash.png"
