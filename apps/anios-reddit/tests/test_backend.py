import json
import time

import pytest
from PySide6.QtGui import QGuiApplication

from anios_reddit.api import RedditClient
from anios_reddit.backend import Backend
from anios_reddit.settings import Settings
from conftest import load_fixture, make_fake


@pytest.fixture(scope="module")
def app():
    return QGuiApplication.instance() or QGuiApplication([])


@pytest.fixture(autouse=True)
def isolated_config(tmp_path, monkeypatch):
    monkeypatch.setenv("ANIOS_REDDIT_CONFIG", str(tmp_path / "config.json"))


def pump_until(app, predicate, timeout=5.0):
    end = time.time() + timeout
    while time.time() < end:
        app.processEvents()
        if predicate():
            return True
        time.sleep(0.01)
    return False


def make_backend(tmp_path, fake, client_id="abcdef1234"):
    Settings(client_id=client_id).save(tmp_path / "config.json")

    def factory(s):
        return RedditClient(s.client_id, transport=fake)

    return Backend(Settings(client_id=client_id), client_factory=factory)


def test_only_unixporn_is_exposed(app, tmp_path):
    backend = make_backend(tmp_path, make_fake())
    assert backend.subreddit == "unixporn"
    assert not hasattr(backend, "search")
    assert not hasattr(backend, "loadSubreddit")


def test_without_client_id_nothing_is_requested(app, tmp_path):
    fake = make_fake()
    backend = make_backend(tmp_path, fake, client_id="")
    backend.refresh()
    assert fake.calls == []
    assert "client ID" in backend.status
    assert backend.hasClientId is False


def test_refresh_loads_posts_and_loadmore_appends(app, tmp_path):
    fake = make_fake()
    backend = make_backend(tmp_path, fake)
    backend.refresh()
    assert pump_until(app, lambda: backend.postModel.rowCount() == 4)
    assert backend.canLoadMore is True
    assert backend.busy is False
    assert all(r["subreddit"] == "unixporn" for r in backend.postModel.rows())
    backend.loadMore()
    assert pump_until(app, lambda: backend.postModel.rowCount() == 5)
    assert backend.canLoadMore is False
    assert backend.postModel.row(4)["title"].startswith("Mẹo nhỏ")


def test_requests_only_go_to_unixporn(app, tmp_path):
    fake = make_fake()
    backend = make_backend(tmp_path, fake)
    backend.refresh()
    assert pump_until(app, lambda: backend.postModel.rowCount() == 4)
    feed_urls = [c[1] for c in fake.calls if "oauth.reddit.com/r/" in c[1]]
    assert feed_urls and all("/r/unixporn/" in u for u in feed_urls)


def test_last_request_wins_when_user_changes_sort(app, tmp_path):
    fake = make_fake()
    fake.routes = {
        "/r/unixporn/new": lambda: load_fixture("listing_next.json"),
        "/r/unixporn/top": lambda: load_fixture("listing_hot.json"),
    }
    backend = make_backend(tmp_path, fake)
    backend.setSort("new")
    backend.setSort("top")
    assert pump_until(app, lambda: backend.postModel.rowCount() == 4)
    time.sleep(0.2)
    app.processEvents()
    assert backend.postModel.rowCount() == 4
    assert backend.sort == "top"


def test_sort_is_remembered_and_invalid_falls_back(app, tmp_path):
    backend = make_backend(tmp_path, make_fake())
    backend.setSort("new")
    assert backend.sort == "new"
    assert json.loads((tmp_path / "config.json").read_text())["last_sort"] == "new"
    backend.setSort("weird")
    assert backend.sort == "hot"


def test_open_post_loads_comments(app, tmp_path):
    backend = make_backend(tmp_path, make_fake())
    backend.refresh()
    assert pump_until(app, lambda: backend.postModel.rowCount() == 4)
    backend.openPost(1)
    assert backend.currentPost["title"].startswith("Ai đã thử")
    assert pump_until(app, lambda: backend.commentModel.rowCount() == 4)
    assert backend.currentPost["commentsLoading"] is False
    assert backend.commentModel.row(2)["depth"] == 2
    backend.closePost()
    assert backend.currentPost == {}


def test_http_error_becomes_status_message(app, tmp_path):
    fake = make_fake()
    backend = make_backend(tmp_path, fake)
    fake.fail_status = 403
    backend.refresh()
    assert pump_until(app, lambda: backend.status != "")
    assert "403" in backend.status
    assert backend.busy is False


def test_theme_persists(app, tmp_path):
    backend = make_backend(tmp_path, make_fake())
    backend.setTheme("light")
    assert backend.darkTheme is False
    assert Settings.load(tmp_path / "config.json").theme == "light"
