#!/bin/sh
# Cài shortcut AniOS Manga vào menu ứng dụng của người dùng hiện tại (không cần root).
#
#   ./install-desktop.sh            # mục menu + icon
#   ./install-desktop.sh --desktop  # thêm cả biểu tượng trên màn hình Desktop
#   ./install-desktop.sh --uninstall
#
# Cần lệnh `anios-manga` có trong PATH (chạy `pip install -e .` hoặc `pipx install .` trước).
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
APPS_DIR=$DATA_HOME/applications
ICON_DIR=$DATA_HOME/icons/hicolor/scalable/apps
DESKTOP_DIR=$(xdg-user-dir DESKTOP 2>/dev/null || true)
[ -n "$DESKTOP_DIR" ] || DESKTOP_DIR=$HOME/Desktop
NAME=anios-manga.desktop

refresh() {
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "$APPS_DIR" 2>/dev/null || true
  command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t "$DATA_HOME/icons/hicolor" 2>/dev/null || true
}

if [ "${1:-}" = "--uninstall" ]; then
  rm -f "$APPS_DIR/$NAME" "$ICON_DIR/anios-manga.svg" "$DESKTOP_DIR/$NAME"
  refresh
  echo "Đã gỡ shortcut AniOS Manga."
  exit 0
fi

if ! command -v anios-manga >/dev/null 2>&1; then
  echo "Không tìm thấy lệnh anios-manga trong PATH. Hãy cài trước: pip install -e $HERE" >&2
  exit 1
fi

mkdir -p "$APPS_DIR" "$ICON_DIR"
# Exec dùng đường dẫn tuyệt đối để shortcut vẫn chạy khi PATH của phiên đồ hoạ khác PATH của terminal.
BIN=$(command -v anios-manga)
sed "s|^Exec=.*|Exec=$BIN|" "$HERE/data/$NAME" > "$APPS_DIR/$NAME"
chmod 644 "$APPS_DIR/$NAME"
cp "$HERE/data/anios-manga.svg" "$ICON_DIR/anios-manga.svg"
refresh

if [ "${1:-}" = "--desktop" ]; then
  mkdir -p "$DESKTOP_DIR"
  cp "$APPS_DIR/$NAME" "$DESKTOP_DIR/$NAME"
  chmod 755 "$DESKTOP_DIR/$NAME"
  # GNOME/Nautilus chỉ chạy shortcut trên Desktop khi được đánh dấu là đáng tin cậy.
  command -v gio >/dev/null 2>&1 && gio set "$DESKTOP_DIR/$NAME" metadata::trusted true 2>/dev/null || true
  echo "Đã thêm biểu tượng vào $DESKTOP_DIR."
fi

echo "Đã cài shortcut AniOS Manga vào $APPS_DIR (chạy: $BIN)."
