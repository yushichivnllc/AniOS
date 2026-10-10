"""Kiểm thử khói: nạp toàn bộ QML bằng dữ liệu giả, không cần mạng.

Chạy được trên máy không có GPU nhờ QT_QPA_PLATFORM=offscreen và
QT_QUICK_BACKEND=software (conftest.py đặt sẵn).
"""
from __future__ import annotations

import os
import time

import pytest

pytest.importorskip("PySide6.QtQml")

from PySide6.QtCore import QUrl  # noqa: E402
from PySide6.QtGui import QGuiApplication  # noqa: E402
from PySide6.QtQml import QQmlApplicationEngine, QQmlComponent, QQmlContext  # noqa: E402

from anios_manga.__main__ import QML_DIR  # noqa: E402
from anios_manga.backend import Backend  # noqa: E402
from anios_manga.settings import Settings  # noqa: E402
from conftest import make_fake, pump  # noqa: E402

pytestmark = pytest.mark.usefixtures("qt_app")

# Lỗi QML làm hỏng giao diện nhưng không ném ngoại lệ: phải coi là thất bại.
FATAL_QML = ("TypeError", "ReferenceError", "is not a", "managed by a layout")


def qml_errors(messages, page=None):
    """Lọc thông báo lỗi QML; `page` giới hạn trong một tệp cụ thể."""
    fatal = []
    for message in messages:
        if not any(marker in message for marker in FATAL_QML):
            continue
        if page and page not in message:
            continue
        fatal.append(message)
    return fatal


@pytest.fixture()
def gui(settings, qt_app, monkeypatch):
    monkeypatch.setenv("QT_QUICK_CONTROLS_STYLE", "Material")
    fake = make_fake()
    engine = QQmlApplicationEngine()
    backend = Backend(settings, transport=fake, parent=engine)
    engine.rootContext().setContextProperty("backend", backend)
    messages = []
    from PySide6.QtCore import qInstallMessageHandler

    def handler(mode, ctx, msg):
        messages.append(msg)

    old = qInstallMessageHandler(handler)
    engine.load(QUrl.fromLocalFile(str(QML_DIR / "Main.qml")))
    assert engine.rootObjects(), "không tải được Main.qml"
    backend.start()
    assert pump(qt_app, lambda: backend.mangaModel.rowCount() == 3), "danh sách không tải xong"
    yield app_view(engine), engine, backend, fake, messages
    qInstallMessageHandler(old)
    backend.shutdown()


def app_view(engine):
    """Cửa sổ gốc dưới dạng QQuickWindow để chụp ảnh được."""
    import shiboken6
    from PySide6.QtQuick import QQuickWindow

    return shiboken6.wrapInstance(
        shiboken6.getCppPointer(engine.rootObjects()[0])[0], QQuickWindow
    )


def test_main_window_loads_and_fills_feed(gui):
    view, engine, backend, fake, messages = gui
    assert engine.rootObjects(), "không tải được Main.qml"
    assert pump(QGuiApplication.instance(), lambda: backend.mangaModel.rowCount() == 3)
    fatal = qml_errors(messages)
    assert not fatal, fatal


def test_every_page_instantiates_without_errors(gui):
    view, engine, backend, fake, messages = gui
    assert pump(QGuiApplication.instance(), lambda: backend.mangaModel.rowCount() == 3)
    delegate_model = {
        # Vai trò mà các delegate đọc lúc dựng (MangaCard, ChapterItem).
        "index": 0,
        "id": "a1a1a1a1",
        "title": "Đảo Hải Tặc",
        "cover": "image://manga/https%3A%2F%2Fuploads.example%2Fa1.jpg",
        "coverFull": "https://uploads.example/a1.jpg",
        "description": "Truyện kiểm thử.",
        "author": "Oda",
        "artist": "Oda",
        "status": "Đang ra",
        "inLibrary": False,
        "progressText": "",
        "statusText": "Đang ra",
        "label": "Chương 10 - Cuộc chiến",
        "pages": 3,
        "language": "vi",
        "publishedAt": "2024-05-01T00:00:00+00:00",
        "downloaded": False,
        "url": "image://manga/1.png",
        "source": "mangadex",
    }
    for page in (
        "LibraryPage.qml",
        "ExplorePage.qml",
        "HistoryPage.qml",
        "DownloadsPage.qml",
        "SettingsPage.qml",
        "DetailsPage.qml",
        "ReaderPage.qml",
        "MangaCard.qml",
        "ChapterItem.qml",
    ):
        component = QQmlComponent(engine, QUrl.fromLocalFile(str(QML_DIR / page)))
        assert component.isReady(), f"{page} không tạo được: {component.errors()}"
        ctx = QQmlContext(engine.rootContext())
        ctx.setContextProperty("backend", backend)
        ctx.setContextProperty("model", delegate_model)
        obj = component.create(ctx)
        assert obj is not None, f"{page} tạo ra null: {component.errors()}"
        fatal = qml_errors(messages, page)
        assert not fatal, (page, fatal)


def test_reader_page_shows_pages_after_opening_chapter(gui):
    view, engine, backend, fake, messages = gui
    backend.openManga(0)
    assert pump(QGuiApplication.instance(), lambda: backend.chapterModel.rowCount() == 4)
    backend.openChapter(0)
    assert pump(QGuiApplication.instance(), lambda: backend.readerCount == 3)
    component = QQmlComponent(engine, QUrl.fromLocalFile(str(QML_DIR / "ReaderPage.qml")))
    obj = component.create(QQmlContext(engine.rootContext()))
    assert obj is not None
    fatal = qml_errors(messages)
    assert not fatal, fatal


def test_navigation_between_sections(gui):
    """Bấm hết các mục trên thanh điều hướng không được có lỗi JavaScript."""
    view, engine, backend, fake, messages = gui
    root = engine.rootObjects()[0]
    for section in ("explore", "history", "downloads", "settings", "library"):
        root.showSection(section)
        QGuiApplication.instance().processEvents()
    assert root.property("section") == "library"
    fatal = qml_errors(messages)
    assert not fatal, fatal


def test_qml_only_uses_backend_members_that_exist():
    """Chặn lỗi gõ sai tên thuộc tính/slot: mọi `backend.xxx` phải có thật.

    QML chỉ báo lỗi lúc chạy nên bài này đối chiếu tĩnh danh sách dùng trong QML với
    thuộc tính/tín hiệu/slot của Backend.
    """
    import re

    from PySide6.QtCore import QObject

    backend_members = set(dir(Backend))
    for path in sorted(QML_DIR.glob("*.qml")):
        text = path.read_text(encoding="utf-8")
        used = set(re.findall(r"\bbackend\.([A-Za-z_][A-Za-z0-9_]*)", text))
        missing = {name for name in used if name not in backend_members}
        assert not missing, f"{path.name} dùng backend.{sorted(missing)} không tồn tại"
        # Tín hiệu backend dùng trong Connections phải là Signal thật.
        for name in re.findall(r"function on([A-Z][A-Za-z0-9]*)\(\)", text):
            signal = name[0].lower() + name[1:]
            assert hasattr(Backend, signal), f"{path.name} bắt tín hiệu {signal} không tồn tại"


def test_screenshot_of_main_window(gui, tmp_path):
    """Chụp màn hình thật (bật bằng ANIOS_MANGA_SHOT) để xem bố cục."""
    shot = os.environ.get("ANIOS_MANGA_SHOT")
    if not shot:
        pytest.skip("đặt ANIOS_MANGA_SHOT=/đường/dẫn.png để chụp màn hình")
    view, engine, backend, fake, messages = gui
    assert pump(QGuiApplication.instance(), lambda: backend.mangaModel.rowCount() == 3)
    grab = view.contentItem().grabToImage()
    assert pump(QGuiApplication.instance(), lambda: not grab.image().isNull(), timeout=10)
    assert grab.image().save(shot)
