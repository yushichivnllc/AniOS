"""Điểm vào: `python -m anios_manga` hoặc lệnh `anios-manga`."""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from .settings import Settings

QML_DIR = Path(__file__).parent / "qml"
IMAGE_PROVIDER_ID = "manga"


def build_app(settings: Settings, transport=None):
    """Tạo QGuiApplication, engine và backend. Trả về (app, engine, backend).

    `transport` chỉ dùng cho kiểm thử: thay urllib bằng bản giả để chạy không cần mạng.
    """
    from PySide6.QtCore import QUrl
    from PySide6.QtGui import QGuiApplication
    from PySide6.QtQml import QQmlApplicationEngine

    from .backend import Backend
    from .images import IMAGE_PROVIDER_ID, MangaImageProvider
    from .paths import cache_dir, ensure_dirs

    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Material")
    ensure_dirs(settings)
    app = QGuiApplication.instance() or QGuiApplication(sys.argv)
    app.setApplicationName("AniOS Manga")
    app.setOrganizationName("AniOS")
    engine = QQmlApplicationEngine()
    # Backend là con của engine: C++ huỷ backend sau khi giao diện QML đã huỷ xong.
    backend = (
        Backend(settings, transport=transport, parent=engine) if transport else Backend(settings, parent=engine)
    )
    engine.rootContext().setContextProperty("backend", backend)
    engine.addImageProvider(IMAGE_PROVIDER_ID, MangaImageProvider(cache_dir(settings), transport=transport))
    engine.load(QUrl.fromLocalFile(str(QML_DIR / "Main.qml")))
    if not engine.rootObjects():
        raise SystemExit("Không tải được giao diện QML.")
    backend.start()
    return app, engine, backend


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="anios-manga", description="Trình đọc truyện tranh cho AniOS")
    parser.add_argument("--config", type=Path, help="đường dẫn file cấu hình khác")
    parser.add_argument("--version", action="version", version=f"%(prog)s {__import__('anios_manga').__version__}")
    args = parser.parse_args(argv)
    if args.config:
        os.environ["ANIOS_MANGA_CONFIG"] = str(args.config)
    settings = Settings.load()
    app, _engine, backend = build_app(settings)
    try:
        return app.exec()
    finally:
        backend.shutdown()


if __name__ == "__main__":
    raise SystemExit(main())
