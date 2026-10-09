"""Cầu nối Python ↔ QML: tải dữ liệu ở luồng nền, trả kết quả về luồng giao diện."""
from __future__ import annotations

import threading
from typing import Callable, Optional

from PySide6.QtCore import Property, QObject, Signal, Slot

from .api import RedditClient, RedditError, SORTS, TIME_RANGES
from .models import COMMENT_ROLES, POST_ROLES, DictListModel
from .settings import Settings

ClientFactory = Callable[[Settings], RedditClient]


def _default_factory(settings: Settings) -> RedditClient:
    return RedditClient(settings.client_id, contact=settings.contact)


class Backend(QObject):
    busyChanged = Signal()
    statusChanged = Signal()
    feedChanged = Signal()
    currentPostChanged = Signal()
    settingsChanged = Signal()
    _resultReady = Signal(object)  # (kind, request_id, result, error) — gửi từ luồng nền

    def __init__(self, settings: Settings, client_factory: ClientFactory = _default_factory, parent=None):
        super().__init__(parent)
        self._settings = settings
        self._factory = client_factory
        self._client: Optional[RedditClient] = None
        self._posts = DictListModel(POST_ROLES, self)
        self._comments = DictListModel(COMMENT_ROLES, self)
        self._subreddit = settings.last_subreddit if settings.last_subreddit else "all"
        self._sort = settings.last_sort if settings.last_sort in SORTS else "hot"
        self._time_range = "day"
        self._query = ""  # khác rỗng khi đang ở chế độ tìm kiếm
        self._after: Optional[str] = None
        self._busy = False
        self._status = ""
        self._feed_req = 0
        self._comment_req = 0
        self._current_post: dict = {}
        self._resultReady.connect(self._on_result)

    # ------------------------------------------------------------ properties
    @Property(bool, notify=busyChanged)
    def busy(self) -> bool:
        return self._busy

    @Property(str, notify=statusChanged)
    def status(self) -> str:
        return self._status

    @Property(str, notify=feedChanged)
    def subreddit(self) -> str:
        return self._subreddit

    @Property(str, notify=feedChanged)
    def sort(self) -> str:
        return self._sort

    @Property(str, notify=feedChanged)
    def timeRange(self) -> str:  # noqa: N802
        return self._time_range

    @Property(bool, notify=feedChanged)
    def canLoadMore(self) -> bool:  # noqa: N802
        return bool(self._after)

    @Property(bool, notify=settingsChanged)
    def hasClientId(self) -> bool:  # noqa: N802
        return bool(self._settings.client_id.strip())

    @Property(bool, notify=settingsChanged)
    def darkTheme(self) -> bool:  # noqa: N802
        return self._settings.theme == "dark"

    @Property("QVariantList", notify=settingsChanged)
    def subreddits(self) -> list:
        return list(self._settings.subreddits)

    @Property(QObject, constant=True)
    def postModel(self) -> QObject:  # noqa: N802
        return self._posts

    @Property(QObject, constant=True)
    def commentModel(self) -> QObject:  # noqa: N802
        return self._comments

    @Property("QVariantMap", notify=currentPostChanged)
    def currentPost(self) -> dict:  # noqa: N802
        return self._current_post

    @Property(list, constant=True)
    def sorts(self) -> list:
        return list(SORTS)

    @Property(list, constant=True)
    def timeRanges(self) -> list:  # noqa: N802
        return list(TIME_RANGES)

    # ------------------------------------------------------------ slots: feed
    @Slot(str, str)
    def loadSubreddit(self, name: str, sort: str):  # noqa: N802
        name = name.strip().removeprefix("r/").strip("/") or "all"
        self._subreddit = name
        self._sort = sort if sort in SORTS else "hot"
        self._query = ""
        self._settings.last_subreddit = name
        self._settings.last_sort = self._sort
        self._save_settings()
        self._reload()

    @Slot()
    def refresh(self):
        self._reload()

    @Slot(str)
    def setTimeRange(self, value: str):  # noqa: N802
        if value in TIME_RANGES and value != self._time_range:
            self._time_range = value
            self._reload()

    @Slot(str)
    def search(self, query: str):
        self._query = query.strip()
        self._reload()

    @Slot()
    def loadMore(self):  # noqa: N802
        if self._busy or not self._after:
            return
        self._start_feed(self._after, append=True)

    # ------------------------------------------------------------ slots: post
    @Slot(int)
    def openPost(self, index: int):  # noqa: N802
        row = self._posts.row(index)
        if row is None:
            return
        self._current_post = {**row, "commentsLoading": True, "commentsError": ""}
        self._comments.set_rows([])
        self.currentPostChanged.emit()
        self._comment_req += 1
        req = self._comment_req
        post_id = row["id"]
        self._run("comments", req, lambda c: c.comments(post_id))

    @Slot()
    def closePost(self):  # noqa: N802
        self._comment_req += 1  # bỏ kết quả đang chờ
        self._current_post = {}
        self.currentPostChanged.emit()

    # ------------------------------------------------------------ slots: settings
    @Slot(str)
    def saveClientId(self, client_id: str):  # noqa: N802
        self._settings.client_id = client_id.strip()
        self._client = None
        self._save_settings()
        self.settingsChanged.emit()
        if self.hasClientId:
            self._reload()

    @Slot(str)
    def setTheme(self, theme: str):  # noqa: N802
        if theme in ("dark", "light"):
            self._settings.theme = theme
            self._save_settings()
            self.settingsChanged.emit()

    @Slot(str)
    def addSubreddit(self, name: str):  # noqa: N802
        name = name.strip().removeprefix("r/").strip("/")
        if name and name.lower() not in [s.lower() for s in self._settings.subreddits]:
            self._settings.subreddits.append(name)
            self._save_settings()
            self.settingsChanged.emit()

    @Slot(str)
    def removeSubreddit(self, name: str):  # noqa: N802
        self._settings.subreddits = [s for s in self._settings.subreddits if s != name]
        self._save_settings()
        self.settingsChanged.emit()

    # ------------------------------------------------------------ internals
    def _save_settings(self):
        try:
            self._settings.save()
        except OSError as exc:
            self._set_status(f"Không lưu được cấu hình: {exc}")

    def _client_or_none(self) -> Optional[RedditClient]:
        if not self.hasClientId:
            return None
        if self._client is None:
            self._client = self._factory(self._settings)
        return self._client

    def _set_busy(self, value: bool):
        if self._busy != value:
            self._busy = value
            self.busyChanged.emit()

    def _set_status(self, text: str):
        if self._status != text:
            self._status = text
            self.statusChanged.emit()

    def _reload(self):
        self._after = None
        self._feed_req += 1
        self._start_feed(None, append=False)

    def _start_feed(self, after: Optional[str], append: bool):
        client = self._client_or_none()
        if client is None:
            self._set_status("Cần client ID của Reddit trước khi tải bài viết.")
            self.settingsChanged.emit()
            return
        req = self._feed_req
        self._set_busy(True)
        self._set_status("")
        sub, sort, tr, query = self._subreddit, self._sort, self._time_range, self._query
        if query:
            fn = lambda c: c.search(query, after=after)  # noqa: E731
        else:
            fn = lambda c: c.listing(sub, sort, after=after, time_range=tr)  # noqa: E731
        self._run("feed", req, fn, append)

    def _run(self, kind: str, req: int, fn: Callable, append: bool = False):
        client = self._client_or_none()
        if client is None:
            return

        def work():
            try:
                result = fn(client)
                self._resultReady.emit((kind, req, append, result, ""))
            except RedditError as exc:
                self._resultReady.emit((kind, req, append, None, str(exc)))
            except Exception as exc:  # lỗi lạ: vẫn không làm sập giao diện
                self._resultReady.emit((kind, req, append, None, f"Lỗi không mong đợi: {exc}"))

        threading.Thread(target=work, daemon=True).start()

    @Slot(object)
    def _on_result(self, payload):
        kind, req, append, result, error = payload
        if kind == "feed":
            if req != self._feed_req:
                return  # kết quả cũ, đã có yêu cầu mới hơn
            self._set_busy(False)
            if error:
                self._set_status(error)
                return
            self._after = result.after
            if append:
                self._posts.append_rows([dict(p) for p in result.posts])
            else:
                self._posts.set_rows([dict(p) for p in result.posts])
            self.feedChanged.emit()
        elif kind == "comments":
            if req != self._comment_req:
                return
            if error:
                self._current_post = {**self._current_post, "commentsLoading": False, "commentsError": error}
            else:
                self._comments.set_rows(result)
                self._current_post = {**self._current_post, "commentsLoading": False, "commentsError": ""}
            self.currentPostChanged.emit()
