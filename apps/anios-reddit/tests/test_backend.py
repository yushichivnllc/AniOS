import time

import pytest
from PySide6.QtGui import QGuiApplication

from anios_reddit.api import RedditClient
from anios_reddit.backend import Backend
from anios_reddit.settings import Settings
from conftest import make_fake


@pytest.fixture(scope="module")
def app():
    return QGuiApplication.instance() or QGuiApplication([])


def pump_until(app, predicate, timeout=5.0):
    end = time.time() + timeout
    while time.time() < end:
        app.processEvents()
        if predicate():
            return True
        time.sleep(0.01)
    return False


def make_backend(tmp_path, fake, client_id="abcdef1234"):
    settings = Settings(client_id=client_id, subreddits=["linux", "archlinux"], last_subreddit="linux")
    settings.save(tmp_path / "config.json")
    def factory(s):
        return RedditClient(s.client_id, transport=fake)

    backend = Backend(settings, client_factory=factory)
    return backend


@pytest.fixture(autouse=True)
def isolated_config(tmp_path, monkeypatch):
    monkeypatch.setenv("ANIOS_REDDIT_CONFIG", str(tmp_path / "config.json"))


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
    backend.loadSubreddit("linux", "hot")
    assert pump_until(app, lambda: backend.postModel.rowCount() == 4)
    assert backend.canLoadMore is True
    assert backend.busy is False
    backend.loadMore()
    assert pump_until(app, lambda: backend.postModel.rowCount() == 5)
    assert backend.canLoadMore is False
    assert backend.postModel.row(4)["title"].startswith("Mẹo nhỏ")


def test_last_request_wins_when_user_switches_subreddit(app, tmp_path):
    fake = make_fake()
    backend = make_backend(tmp_path, fake)
    backend.loadSubreddit("linux", "hot")
    backend.loadSubreddit("archlinux", "hot")
    assert pump_until(app, lambda: backend.postModel.rowCount() == 1)
    time.sleep(0.2)
    app.processEvents()
    assert backend.postModel.rowCount() == 1
    assert backend.subreddit == "archlinux"
    assert backend.postModel.row(0)["subreddit"] == "archlinux"


def test_sort_and_subreddit_are_remembered_in_settings(app, tmp_path):
    fake = make_fake()
    backend = make_backend(tmp_path, fake)
    backend.loadSubreddit("r/archlinux/", "new")
    assert backend.subreddit == "archlinux"
    assert backend.sort == "new"
    saved = Settings.load(tmp_path / "config.json")
    assert saved.last_subreddit == "archlinux"
    assert saved.last_sort == "new"


def test_invalid_sort_falls_back_to_hot(app, tmp_path):
    backend = make_backend(tmp_path, make_fake())
    backend.loadSubreddit("linux", "weird")
    assert backend.sort == "hot"


def test_open_post_loads_comments(app, tmp_path):
    backend = make_backend(tmp_path, make_fake())
    backend.loadSubreddit("linux", "hot")
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
    backend.loadSubreddit("linux", "hot")
    assert pump_until(app, lambda: backend.status != "")
    assert "403" in backend.status
    assert backend.busy is False


def test_search_uses_search_endpoint(app, tmp_path):
    fake = make_fake()
    backend = make_backend(tmp_path, fake)
    backend.search("waydroid")
    assert pump_until(app, lambda: backend.postModel.rowCount() == 1)
    assert fake.requests_to("/search")


def test_theme_and_subreddit_management_persist(app, tmp_path):
    backend = make_backend(tmp_path, make_fake())
    backend.setTheme("light")
    backend.addSubreddit("r/Python")
    backend.addSubreddit("python")  # trùng, không thêm nữa
    backend.removeSubreddit("linux")
    saved = Settings.load(tmp_path / "config.json")
    assert saved.theme == "light"
    assert "Python" in saved.subreddits and saved.subreddits.count("Python") == 1
    assert "linux" not in saved.subreddits
