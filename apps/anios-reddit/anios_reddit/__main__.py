"""Điểm vào: `python -m anios_reddit` hoặc lệnh `anios-reddit`."""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from .settings import Settings

QML_DIR = Path(__file__).parent / "qml"


def build_app(settings: Settings, client_factory=None):
    """Tạo QGuiApplication, engine và cửa sổ. Trả về (app, engine, backend)."""
    from PySide6.QtCore import QUrl
    from PySide6.QtGui import QGuiApplication
    from PySide6.QtQml import QQmlApplicationEngine

    from .backend import Backend

    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Material")
    app = QGuiApplication.instance() or QGuiApplication(sys.argv)
    app.setApplicationName("AniOS Reddit")
    app.setOrganizationName("AniOS")
    engine = QQmlApplicationEngine()
    # Backend là con của engine: C++ huỷ backend sau khi giao diện QML đã huỷ xong.
    backend = Backend(settings, client_factory, parent=engine) if client_factory else Backend(settings, parent=engine)
    engine.rootContext().setContextProperty("backend", backend)
    engine.load(QUrl.fromLocalFile(str(QML_DIR / "Main.qml")))
    if not engine.rootObjects():
        raise SystemExit("Không tải được giao diện QML.")
    return app, engine, backend


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="anios-reddit", description="Trình đọc Reddit cho AniOS")
    parser.add_argument("--config", type=Path, help="đường dẫn file cấu hình khác")
    args = parser.parse_args(argv)
    if args.config:
        os.environ["ANIOS_REDDIT_CONFIG"] = str(args.config)
    settings = Settings.load()
    app, _engine, _backend = build_app(settings)
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
