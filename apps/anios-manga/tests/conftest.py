import base64
import json
import os
import sys
import time
from pathlib import Path

import pytest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

FIXTURES = Path(__file__).parent / "fixtures"

# Ảnh PNG 1x1 hợp lệ, dùng để kiểm thử nhà cung cấp ảnh và bộ tải xuống.
PNG_BYTES = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx"
    "iwAAAABJRU5ErkJggg=="
)


def load_fixture(name: str):
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


class FakeMangaDex:
    """Transport giả lập API MangaDex: ghi lại yêu cầu và trả fixture theo đường dẫn."""

    def __init__(self):
        self.calls = []
        self.fail = {}  # đường dẫn -> (status, thông báo)
        self.pages = ["1.png", "2.png", "3.png"]

    def __call__(self, method, url, headers, body):
        self.calls.append((method, url, dict(headers), body))
        path = url.split("?")[0]
        for needle, (status, message) in self.fail.items():
            if needle in url:
                return status, json.dumps({"result": "error", "errors": [{"detail": message}]}), {}
        # Ảnh (bìa + trang truyện) luôn trả về PNG mẫu. Fixture dùng host thật
        # uploads.mangadex.org nên phải bắt cả host đó, không chỉ host giả.
        if path.startswith(("https://cdn.example/", "https://uploads.example/")) or (
            "uploads.mangadex.org/covers/" in url
        ):
            raw = PNG_BYTES
            return 200, raw.decode("utf-8", "surrogateescape"), {"Content-Type": "image/png"}
        if path.endswith("/manga") or "/manga?" in url:
            return 200, json.dumps(self._listing(url)), {}
        if "/feed" in path:
            return 200, json.dumps(load_fixture("feed.json")), {}
        if "/at-home/server/" in path:
            return 200, json.dumps(
                {
                    "result": "ok",
                    "baseUrl": "https://cdn.example",
                    "chapter": {"hash": "abc123", "data": self.pages, "dataSaver": ["s.png"]},
                }
            ), {}
        if path.endswith("/manga/tag"):
            return 200, json.dumps(load_fixture("tags.json")), {}
        if "/manga/" in path:
            payload = dict(load_fixture("manga_details.json"))
            # Mỗi truyện trả về id của chính nó: nhờ vậy kiểm thử phân biệt được
            # hai yêu cầu chi tiết gần như đồng thời.
            payload["data"] = dict(payload["data"])
            payload["data"]["id"] = path.rsplit("/", 1)[-1]
            return 200, json.dumps(payload), {}
        return 404, json.dumps({"result": "error"}), {}

    def _listing(self, url):
        query = url.split("?", 1)[1] if "?" in url else ""
        offset = 0
        for part in query.split("&"):
            if part.startswith("offset="):
                offset = int(part.split("=", 1)[1])
        if offset >= 48:
            payload = load_fixture("manga_list_page3.json")
        elif offset >= 24:
            payload = load_fixture("manga_list_page2.json")
        else:
            payload = load_fixture("manga_list.json")
        payload = dict(payload)
        payload["offset"] = offset
        return payload

    def requests_to(self, needle):
        return [c for c in self.calls if needle in c[1]]


def make_fake():
    return FakeMangaDex()


def pump(app, predicate, timeout=8.0):
    """Chạy event loop cho tới khi predicate đúng (backend làm việc ở luồng nền)."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        app.processEvents()
        if predicate():
            return True
        time.sleep(0.01)
    return False


@pytest.fixture(scope="session")
def qt_app():
    import pytest

    from PySide6.QtGui import QGuiApplication

    app = QGuiApplication.instance() or QGuiApplication([])
    return app


@pytest.fixture()
def settings(tmp_path, monkeypatch):
    from anios_manga.settings import Settings

    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "data"))
    monkeypatch.setenv("ANIOS_MANGA_CONFIG", str(tmp_path / "config.json"))
    return Settings()


@pytest.fixture()
def fake():
    return make_fake()
