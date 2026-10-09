"""Kiểm thử khói: nạp toàn bộ QML bằng dữ liệu giả, không cần mạng."""
import os
import time

import pytest

pytest.importorskip("PySide6.QtQml")

from PySide6.QtCore import QUrl  # noqa: E402
from PySide6.QtGui import QGuiApplication  # noqa: E402
from PySide6.QtQml import QQmlApplicationEngine  # noqa: E402

from anios_reddit.__main__ import QML_DIR  # noqa: E402
from anios_reddit.api import RedditClient  # noqa: E402
from anios_reddit.backend import Backend  # noqa: E402
from anios_reddit.settings import Settings  # noqa: E402
from conftest import make_fake  # noqa: E402


@pytest.fixture
def gui(tmp_path, monkeypatch):
    monkeypatch.setenv("ANIOS_REDDIT_CONFIG", str(tmp_path / "config.json"))
    monkeypatch.setenv("QT_QUICK_CONTROLS_STYLE", "Material")
    app = QGuiApplication.instance() or QGuiApplication([])
    fake = make_fake()
    settings = Settings(client_id="abcdef1234", last_sort="hot")
    engine = QQmlApplicationEngine()
    backend = Backend(settings, client_factory=lambda s: RedditClient(s.client_id, transport=fake), parent=engine)
    engine.rootContext().setContextProperty("backend", backend)
    messages = []
    from PySide6.QtCore import qInstallMessageHandler

    def handler(mode, ctx, msg):
        messages.append(msg)

    old = qInstallMessageHandler(handler)
    engine.load(QUrl.fromLocalFile(str(QML_DIR / "Main.qml")))
    yield app, engine, backend, fake, messages
    qInstallMessageHandler(old)


def _pump(app, predicate, timeout=6.0):
    end = time.time() + timeout
    while time.time() < end:
        app.processEvents()
        if predicate():
            return True
        time.sleep(0.01)
    return False


def test_main_window_loads_and_fills_feed(gui):
    app, engine, backend, fake, messages = gui
    assert engine.rootObjects(), "không tải được Main.qml"
    assert _pump(app, lambda: backend.postModel.rowCount() == 4)
    fatal = [m for m in messages if "TypeError" in m or "ReferenceError" in m]
    assert not fatal, fatal


def test_setup_page_is_shown_without_client_id(tmp_path, monkeypatch):
    monkeypatch.setenv("ANIOS_REDDIT_CONFIG", str(tmp_path / "config.json"))
    app = QGuiApplication.instance() or QGuiApplication([])
    engine = QQmlApplicationEngine()
    backend = Backend(Settings(client_id=""), client_factory=lambda s: RedditClient("x", transport=make_fake()),
                      parent=engine)
    engine.rootContext().setContextProperty("backend", backend)
    engine.load(QUrl.fromLocalFile(str(QML_DIR / "Main.qml")))
    assert engine.rootObjects()
    assert backend.postModel.rowCount() == 0


@pytest.mark.skipif(not os.environ.get("ANIOS_REDDIT_SHOT"), reason="đặt ANIOS_REDDIT_SHOT=/đường/dẫn.png để chụp màn hình")
def test_screenshot(gui):
    app, engine, backend, fake, messages = gui
    import shiboken6
    from PySide6.QtQuick import QQuickWindow

    root = shiboken6.wrapInstance(shiboken6.getCppPointer(engine.rootObjects()[0])[0], QQuickWindow)
    _pump(app, lambda: backend.postModel.rowCount() == 4)
    _pump(app, lambda: False, timeout=0.5)
    grab = root.contentItem().grabToImage()
    _pump(app, lambda: not grab.image().isNull())
    assert grab.image().save(os.environ["ANIOS_REDDIT_SHOT"])


@pytest.mark.parametrize("page", ["PostPage.qml", "SetupPage.qml", "FeedPage.qml"])
def test_pages_instantiate_without_errors(gui, page):
    """Mỗi trang phải tạo được độc lập (trang bài viết được đẩy vào StackView sau khi mở bài)."""
    from PySide6.QtQml import QQmlComponent, QQmlContext

    app, engine, backend, fake, messages = gui
    backend.refresh()
    assert _pump(app, lambda: backend.postModel.rowCount() == 4)
    backend.openPost(1)
    assert _pump(app, lambda: backend.commentModel.rowCount() == 4)
    component = QQmlComponent(engine, QUrl.fromLocalFile(str(QML_DIR / page)))
    ctx = QQmlContext(engine.rootContext())
    ctx.setContextProperty("backend", backend)
    obj = component.create(ctx)
    app.processEvents()
    assert obj is not None, component.errors()
    fatal = [m for m in messages if ("TypeError" in m or "ReferenceError" in m) and page in m]
    assert not fatal, fatal
