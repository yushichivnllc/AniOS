"""Cầu nối Python ↔ QML: tải dữ liệu ở luồng nền, trả kết quả về luồng giao diện.

Mô hình giống apps/anios-reddit: mọi thao tác mạng/đĩa chạy trong
`threading.Thread`, kết quả quay về luồng giao diện qua tín hiệu `_resultReady`
kèm mã yêu cầu để bỏ qua kết quả cũ (người dùng bấm nhanh hơn tốc độ tải).
"""
from __future__ import annotations

import threading
import time
from pathlib import Path
from typing import Callable, List, Optional

from PySide6.QtCore import Property, QObject, QUrl, Signal, Slot
from PySide6.QtGui import QDesktopServices

from . import __version__
from .downloader import download_chapter, downloaded_pages, read_meta
from .http import MangaError
from .library import DEFAULT_CATEGORY, Library
from .models import (
    CHAPTER_ROLES,
    DOWNLOAD_ROLES,
    HISTORY_ROLES,
    MANGA_ROLES,
    PAGE_ROLES,
    DictListModel,
)
from .paths import chapter_dir, ensure_dirs
from .settings import READER_MODES, THEMES, Settings
from .sources import build_sources, source_labels
from .sources.base import Chapter, Manga, status_label
from .util import chapter_label, format_size

BROWSE_MODES = ("popular", "latest")


def _image_source(url: str) -> str:
    """Bọc URL ảnh thành nguồn `image://manga/...` cho QML."""
    from urllib.parse import quote

    if not url:
        return ""
    return f"image://manga/{quote(url, safe='')}"


def _relative_time(timestamp: float, now: Optional[float] = None) -> str:
    if not timestamp:
        return ""
    delta = max(0, int((now if now is not None else time.time()) - timestamp))
    units = (
        (365 * 86400, "năm"),
        (30 * 86400, "tháng"),
        (7 * 86400, "tuần"),
        (86400, "ngày"),
        (3600, "giờ"),
        (60, "phút"),
    )
    for seconds, label in units:
        if delta >= seconds:
            return f"{delta // seconds} {label} trước"
    return "vừa xong"


class Backend(QObject):
    busyChanged = Signal()
    statusChanged = Signal()
    listingChanged = Signal()
    chaptersChanged = Signal()
    currentMangaChanged = Signal()
    readerChanged = Signal()
    libraryChanged = Signal()
    historyChanged = Signal()
    downloadsChanged = Signal()
    settingsChanged = Signal()
    favoriteChanged = Signal()
    categoriesChanged = Signal()
    readerOpened = Signal()  # trang ảnh đã sẵn sàng: QML đẩy trang đọc lên
    _resultReady = Signal(object)  # (kind, req, result, error)

    def __init__(self, settings: Settings, transport=None, parent=None):
        """`transport` chỉ dùng khi kiểm thử: thay urllib bằng bản giả trả fixture."""
        super().__init__(parent)
        self._settings = settings
        self._transport = transport
        ensure_dirs(settings)
        self._library = Library(settings.data_path / "library.db")
        self._sources = build_sources(settings, transport=self._transport)
        self._source_id = settings.source if settings.source in self._sources else "mangadex"

        self._manga = DictListModel(MANGA_ROLES, self)
        self._chapters_model = DictListModel(CHAPTER_ROLES, self)
        self._pages_model = DictListModel(PAGE_ROLES, self)
        self._library_model = DictListModel(MANGA_ROLES, self)
        self._history_model = DictListModel(HISTORY_ROLES, self)
        self._downloads_model = DictListModel(DOWNLOAD_ROLES, self)

        self._chapters: List[Chapter] = []
        self._current_manga: dict = {}
        self._browse_mode = "popular"
        self._query = ""
        self._page = 0
        self._has_more = False
        self._tags: List[dict] = []

        self._reader: dict = {
            "mangaId": "",
            "chapterId": "",
            "chapterIndex": -1,
            "title": "",
            "label": "",
        }
        self._reader_index = 0
        self._reader_pages: List[str] = []

        self._busy = False
        self._status = ""
        self._library_category = ""
        self._pending_chapter_id = ""
        self._listing_req = 0
        self._detail_req = 0
        self._chapter_req = 0
        self._page_req = 0
        self._resultReady.connect(self._on_result)

    # ------------------------------------------------------------------ thuộc tính chung
    @Property(bool, notify=busyChanged)
    def busy(self) -> bool:
        return self._busy

    @Property(str, notify=statusChanged)
    def status(self) -> str:
        return self._status

    @Property(str, notify=settingsChanged)
    def version(self) -> str:
        return __version__

    @Property(list, notify=settingsChanged)
    def sources(self) -> list:
        return source_labels(self._sources)

    @Property(str, notify=settingsChanged)
    def currentSource(self) -> str:  # noqa: N802
        return self._source_id

    @Property(list, constant=True)
    def browseModes(self) -> list:  # noqa: N802
        return list(BROWSE_MODES)

    @Property(str, notify=listingChanged)
    def browseMode(self) -> str:  # noqa: N802
        return self._browse_mode

    @Property(str, notify=listingChanged)
    def query(self) -> str:
        return self._query

    @Property(bool, notify=listingChanged)
    def canLoadMore(self) -> bool:  # noqa: N802
        return self._has_more and not self._source().offline

    @Property(list, notify=listingChanged)
    def tags(self) -> list:
        return [dict(t) for t in self._tags]

    @Property(str, notify=settingsChanged)
    def exploreTag(self) -> str:  # noqa: N802
        return self._settings.explore_tag

    # ------------------------------------------------------------------ model cho QML
    @Property(QObject, constant=True)
    def mangaModel(self) -> QObject:  # noqa: N802
        return self._manga

    @Property(QObject, constant=True)
    def chapterModel(self) -> QObject:  # noqa: N802
        return self._chapters_model

    @Property(QObject, constant=True)
    def pageModel(self) -> QObject:  # noqa: N802
        return self._pages_model

    @Property(QObject, constant=True)
    def libraryModel(self) -> QObject:  # noqa: N802
        return self._library_model

    @Property(QObject, constant=True)
    def historyModel(self) -> QObject:  # noqa: N802
        return self._history_model

    @Property(QObject, constant=True)
    def downloadsModel(self) -> QObject:  # noqa: N802
        return self._downloads_model

    @Property("QVariantMap", notify=currentMangaChanged)
    def currentManga(self) -> dict:  # noqa: N802
        return self._current_manga

    @Property(bool, notify=favoriteChanged)
    def favorite(self) -> bool:
        return bool(
            self._current_manga
            and self._library.is_favorite(
                self._current_manga.get("source", ""), self._current_manga.get("id", "")
            )
        )

    @Property(str, notify=favoriteChanged)
    def favoriteCategory(self) -> str:  # noqa: N802
        if not self._current_manga:
            return ""
        for row in self._library.list_favorites():
            if row["source"] == self._current_manga.get("source") and row["manga_id"] == self._current_manga.get("id"):
                return row["category"]
        return ""

    @Property(list, notify=categoriesChanged)
    def categories(self) -> list:
        return self._library.categories()

    @Property(str, notify=libraryChanged)
    def libraryCategory(self) -> str:  # noqa: N802
        return self._library_category

    @Property(bool, notify=favoriteChanged)
    def hasProgress(self) -> bool:  # noqa: N802
        """Truyện đang xem có tiến độ đọc đã lưu (để hiện nút Đọc tiếp)."""
        manga_id = self._current_manga.get("id", "")
        if not manga_id:
            return False
        progress = self._library.get_progress(self._current_manga.get("source", ""), manga_id)
        return bool(progress and progress.get("chapter_id"))

    @Property(list, constant=True)
    def readerModeOptions(self) -> list:  # noqa: N802
        return [
            {"id": "webtoon", "name": "Cuộn dọc (webtoon)"},
            {"id": "paged", "name": "Từng trang (trái sang phải)"},
            {"id": "rtl", "name": "Từng trang (phải sang trái)"},
        ]

    # ------------------------------------------------------------------ reader
    @Property(QObject, notify=readerChanged)
    def readerPages(self) -> QObject:  # noqa: N802
        return self._pages_model

    @Property(int, notify=readerChanged)
    def readerIndex(self) -> int:  # noqa: N802
        return self._reader_index

    @Property(int, notify=readerChanged)
    def readerCount(self) -> int:  # noqa: N802
        return len(self._reader_pages)

    @Property(str, notify=readerChanged)
    def readerTitle(self) -> str:  # noqa: N802
        return self._reader.get("title", "")

    @Property(str, notify=readerChanged)
    def readerLabel(self) -> str:  # noqa: N802
        return self._reader.get("label", "")

    @Property(bool, notify=readerChanged)
    def canPrevChapter(self) -> bool:  # noqa: N802
        # Danh sách chương xếp mới nhất trước: "chương trước" là chương cũ hơn.
        return 0 <= self._reader.get("chapterIndex", -1) < len(self._chapters) - 1

    @Property(bool, notify=readerChanged)
    def canNextChapter(self) -> bool:  # noqa: N802
        return self._reader.get("chapterIndex", -1) > 0

    @Property(bool, notify=readerChanged)
    def readerReady(self) -> bool:  # noqa: N802
        return bool(self._reader_pages)

    @Property(str, notify=readerChanged)
    def readerProgressText(self) -> str:  # noqa: N802
        if not self._reader_pages:
            return ""
        return f"Trang {self._reader_index + 1}/{len(self._reader_pages)}"

    # ------------------------------------------------------------------ cài đặt
    @Property(bool, notify=settingsChanged)
    def darkTheme(self) -> bool:  # noqa: N802
        return self._settings.theme == "dark"

    @Property(list, constant=True)
    def themes(self) -> list:
        return list(THEMES)

    @Property(list, constant=True)
    def readerModes(self) -> list:  # noqa: N802
        return list(READER_MODES)

    @Property(str, notify=settingsChanged)
    def readerMode(self) -> str:  # noqa: N802
        return self._settings.reader_mode

    @Property(str, notify=settingsChanged)
    def language(self) -> str:
        return self._settings.languages[0] if self._settings.languages else "vi"

    @Property(bool, notify=settingsChanged)
    def dataSaver(self) -> bool:  # noqa: N802
        return self._settings.data_saver

    @Property(bool, notify=settingsChanged)
    def nsfw(self) -> bool:
        return self._settings.nsfw

    @Property(str, notify=settingsChanged)
    def localDir(self) -> str:  # noqa: N802
        return self._settings.local_dir

    @Property(str, notify=settingsChanged)
    def dataDir(self) -> str:  # noqa: N802
        return str(self._settings.data_path)

    @Property(str, notify=downloadsChanged)
    def downloadSizeText(self) -> str:  # noqa: N802
        return format_size(self._library.total_download_size())

    @Property(int, notify=libraryChanged)
    def favoriteCount(self) -> int:  # noqa: N802
        return int(self._library.stats()["favorites"])

    # ================================================================== slot: duyệt
    @Slot()
    def refresh(self):
        self._load_listing(reset=True)

    @Slot(str)
    def setBrowseMode(self, mode: str):  # noqa: N802
        if mode in BROWSE_MODES and mode != self._browse_mode:
            self._browse_mode = mode
            self._query = ""
            self.listingChanged.emit()
        self._load_listing(reset=True)

    @Slot(str)
    def search(self, query: str):
        self._query = (query or "").strip()
        self._browse_mode = "search"
        self.listingChanged.emit()
        self._load_listing(reset=True)

    @Slot()
    def loadMore(self):  # noqa: N802
        if self._busy or not self.canLoadMore:
            return
        self._load_listing(reset=False)

    @Slot(str)
    def setSource(self, source_id: str):  # noqa: N802
        if source_id not in self._sources:
            return
        self._source_id = source_id
        self._settings.source = source_id
        self._save_settings()
        self._tags = []
        self._manga.clear()
        self._current_manga = {}
        self.currentMangaChanged.emit()
        self.settingsChanged.emit()
        self.listingChanged.emit()
        if not self._source().offline:
            self._load_tags()
        self._load_listing(reset=True)

    @Slot(str)
    def setExploreTag(self, tag_id: str):  # noqa: N802
        self._settings.explore_tag = tag_id or ""
        self._save_settings()
        self.settingsChanged.emit()
        self._load_listing(reset=True)

    # ================================================================== slot: chi tiết
    @Slot(int)
    def openManga(self, index: int):  # noqa: N802
        row = self._manga.row(index)
        if row:
            self.openMangaById(row["source"], row["id"])

    @Slot(str, str)
    def openMangaById(self, source_id: str, manga_id: str):  # noqa: N802
        if source_id not in self._sources:
            self._set_status("Nguồn truyện không còn trong cài đặt.")
            return
        self._pending_chapter_id = ""
        self._source_id = source_id
        self._settings.source = source_id
        self._save_settings()
        self._detail_req += 1
        req = self._detail_req
        self._set_busy(True)
        self._set_status("")
        self._run("details", req, lambda: self._sources[source_id].details(manga_id))

    @Slot(str, str, str)
    def openMangaAndChapter(self, source_id: str, manga_id: str, chapter_id: str):  # noqa: N802
        """Mở truyện rồi nhảy thẳng vào một chương (dùng cho Kệ sách và Tải xuống).

        Danh sách chương tải ở luồng nền nên không thể mở chương ngay được: id chương
        được giữ lại và mở khi danh sách chương về tới.
        """
        self.openMangaById(source_id, manga_id)
        # Đặt sau openMangaById: hàm đó xoá chương chờ mở.
        self._pending_chapter_id = chapter_id or ""

    @Slot()
    def closeManga(self):  # noqa: N802
        self._detail_req += 1
        self._current_manga = {}
        self._chapters = []
        self._chapters_model.clear()
        self.currentMangaChanged.emit()
        self.chaptersChanged.emit()
        self.favoriteChanged.emit()

    # ================================================================== slot: kệ sách
    @Slot()
    def toggleFavorite(self):  # noqa: N802
        if not self._current_manga:
            return
        source = self._current_manga["source"]
        manga_id = self._current_manga["id"]
        if self._library.is_favorite(source, manga_id):
            self._library.remove_favorite(source, manga_id)
            self._set_status("Đã bỏ khỏi kệ sách.")
        else:
            manga = Manga(
                source=source,
                id=manga_id,
                title=self._current_manga.get("title", ""),
                cover_url=self._current_manga.get("coverFull", ""),
                cover_thumb=self._current_manga.get("cover", ""),
                description=self._current_manga.get("description", ""),
                author=self._current_manga.get("author", ""),
                artist=self._current_manga.get("artist", ""),
                status=self._current_manga.get("status", ""),
            )
            self._library.add_favorite(manga, DEFAULT_CATEGORY)
            self._set_status("Đã thêm vào kệ sách.")
        self.favoriteChanged.emit()
        self.libraryChanged.emit()
        self._refresh_library_model()

    @Slot(str)
    def setFavoriteCategory(self, name: str):  # noqa: N802
        if not self._current_manga:
            return
        self._library.add_category(name)
        self._library.set_favorite_category(
            self._current_manga["source"], self._current_manga["id"], name
        )
        self.categoriesChanged.emit()
        self.favoriteChanged.emit()
        self._refresh_library_model()

    @Slot(str)
    def addCategory(self, name: str):  # noqa: N802
        self._library.add_category(name)
        self.categoriesChanged.emit()

    @Slot(str)
    def removeCategory(self, name: str):  # noqa: N802
        self._library.remove_category(name)
        self.categoriesChanged.emit()
        self._refresh_library_model()

    @Slot(str)
    def setLibraryCategory(self, category: str):  # noqa: N802
        self._library_category = category or ""
        self.libraryChanged.emit()
        self._refresh_library_model()

    @Slot()
    def refreshLibrary(self):  # noqa: N802
        self._refresh_library_model()

    # ================================================================== slot: lịch sử
    @Slot()
    def refreshHistory(self):  # noqa: N802
        rows = []
        for entry in self._library.history():
            rows.append(
                {
                    "source": entry["source"],
                    "mangaId": entry["manga_id"],
                    "title": entry["title"],
                    "cover": _image_source(entry["cover"]),
                    "chapterId": entry.get("chapter_id") or "",
                    "chapterLabel": entry.get("chapter_label") or "",
                    "page": int(entry.get("page") or 0),
                    "updatedAt": entry["updated_at"],
                    "updatedText": _relative_time(entry["updated_at"]),
                }
            )
        self._history_model.set_rows(rows)
        self.historyChanged.emit()

    @Slot(int)
    def removeHistory(self, index: int):  # noqa: N802
        row = self._history_model.row(index)
        if not row:
            return
        self._library.remove_history(row["source"], row["mangaId"])
        self.refreshHistory()

    @Slot()
    def clearHistory(self):  # noqa: N802
        self._library.clear_history()
        self.refreshHistory()

    # ================================================================== slot: tải xuống
    @Slot()
    def downloadCurrentChapter(self):  # noqa: N802
        chapter = self._current_chapter()
        if chapter is None:
            return
        manga_id = self._reader.get("mangaId") or self._current_manga.get("id", "")
        title = self._reader.get("title") or self._current_manga.get("title", "")
        self._set_busy(True)
        self._set_status("Đang tải chương về máy...")
        self._run(
            "download",
            self._page_req + 1,
            lambda: self._do_download(manga_id, title, chapter),
        )

    @Slot(str)
    def downloadChapterById(self, chapter_id: str):  # noqa: N802
        """Tải một chương bất kỳ trong danh sách chương (nút tải ở trang chi tiết)."""
        chapter = next((ch for ch in self._chapters if ch.id == chapter_id), None)
        if chapter is None:
            self._set_status("Không tìm thấy chương cần tải.")
            return
        manga_id = self._current_manga.get("id", "")
        title = self._current_manga.get("title", "")
        self._set_busy(True)
        self._set_status("Đang tải chương về máy...")
        self._run(
            "download",
            self._page_req + 1,
            lambda: self._do_download(manga_id, title, chapter),
        )

    def _do_download(self, manga_id: str, title: str, chapter: Chapter) -> dict:
        source = self._source()
        info = download_chapter(
            source=source,
            manga_id=manga_id,
            manga_title=title,
            chapter=chapter,
            settings=self._settings,
            transport=self._transport,
        )
        self._library.add_download(
            source.id,
            manga_id,
            chapter.id,
            chapter_label(chapter.volume, chapter.number, chapter.title),
            title,
            info["path"],
            info["pages"],
            info["size"],
        )
        return info

    @Slot()
    def refreshDownloads(self):  # noqa: N802
        rows = []
        for entry in self._library.downloads():
            rows.append(
                {
                    "source": entry["source"],
                    "mangaId": entry["manga_id"],
                    "chapterId": entry["chapter_id"],
                    "label": entry["chapter_label"],
                    "title": entry["manga_title"],
                    "pages": entry["pages"],
                    "sizeText": format_size(entry["size"]),
                    "path": entry["path"],
                }
            )
        self._downloads_model.set_rows(rows)
        self.downloadsChanged.emit()

    @Slot(int)
    def deleteDownload(self, index: int):  # noqa: N802
        row = self._downloads_model.row(index)
        if not row:
            return
        removed = self._library.remove_download(row["source"], row["mangaId"], row["chapterId"])
        if removed:
            import shutil

            shutil.rmtree(removed["path"], ignore_errors=True)
        self.refreshDownloads()
        self.chaptersChanged.emit()

    @Slot(int)
    def openDownload(self, index: int):  # noqa: N802
        row = self._downloads_model.row(index)
        if row:
            self.openChapterById(row["chapterId"])

    # ================================================================== slot: reader
    @Slot(int)
    def openChapter(self, index: int):  # noqa: N802
        row = self._chapters_model.row(index)
        if row:
            self.openChapterById(row["id"])

    @Slot(str)
    def openChapterById(self, chapter_id: str):  # noqa: N802
        chapter_index = next(
            (i for i, ch in enumerate(self._chapters) if ch.id == chapter_id), -1
        )
        if chapter_index < 0:
            self._set_status("Không tìm thấy chương này.")
            return
        chapter = self._chapters[chapter_index]
        manga_id = self._current_manga.get("id", "")
        title = self._current_manga.get("title", "")
        self._page_req += 1
        req = self._page_req
        self._set_busy(True)
        self._set_status("Đang mở chương...")
        self._run(
            "pages",
            req,
            lambda: self._resolve_pages(manga_id, title, chapter, chapter_index),
        )

    def _resolve_pages(self, manga_id, title, chapter, chapter_index) -> dict:
        source = self._source()
        # Đã tải về máy thì đọc từ đĩa, khỏi tốn mạng.
        record = self._library.download_for(source.id, manga_id, chapter.id)
        if record and Path(record["path"]).is_dir():
            urls = downloaded_pages(Path(record["path"]))
            origin = "download"
        else:
            urls = source.prepare_pages(chapter, data_saver=self._settings.data_saver)
            origin = source.id
        if not urls:
            raise MangaError("Chương này chưa có ảnh để đọc.")
        return {
            "mangaId": manga_id,
            "chapterId": chapter.id,
            "chapterIndex": chapter_index,
            "title": title,
            "label": chapter_label(chapter.volume, chapter.number, chapter.title),
            "urls": urls,
            "origin": origin,
            "chapter": chapter,
        }

    @Slot()
    def openContinue(self):  # noqa: N802
        """Mở đúng chương/trang đang đọc dở (dùng cho trang Lịch sử và Kệ sách)."""
        manga_id = self._current_manga.get("id", "")
        if not manga_id:
            return
        progress = self._library.get_progress(self._source_id, manga_id)
        chapter_id = (progress or {}).get("chapter_id") or ""
        if not chapter_id:
            self._set_status("Chưa có tiến độ đọc cho truyện này.")
            return
        if self._chapters:
            self.openChapterById(chapter_id)
        else:
            # Chương chưa tải xong: nhớ lại rồi mở khi danh sách chương về tới.
            self._pending_chapter_id = chapter_id

    @Slot(int)
    def readerSetPage(self, index: int):  # noqa: N802
        if not (0 <= index < len(self._reader_pages)):
            return
        if index == self._reader_index:
            return
        self._reader_index = index
        self.readerChanged.emit()
        self._save_progress()

    @Slot()
    def readerNextChapter(self):  # noqa: N802
        index = self._reader.get("chapterIndex", -1) - 1
        if 0 <= index < len(self._chapters):
            self.openChapterById(self._chapters[index].id)

    @Slot()
    def readerPrevChapter(self):  # noqa: N802
        index = self._reader.get("chapterIndex", -1) + 1
        if 0 <= index < len(self._chapters):
            self.openChapterById(self._chapters[index].id)

    @Slot()
    def closeReader(self):  # noqa: N802
        self._page_req += 1
        self._reader_pages = []
        self._reader_index = 0
        self._pages_model.clear()
        self.readerChanged.emit()

    @Slot(str)
    def setReaderMode(self, mode: str):  # noqa: N802
        if mode in READER_MODES and mode != self._settings.reader_mode:
            self._settings.reader_mode = mode
            self._save_settings()
            self.settingsChanged.emit()

    # ================================================================== slot: cài đặt
    @Slot(str)
    def setTheme(self, theme: str):  # noqa: N802
        if theme in THEMES:
            self._settings.theme = theme
            self._save_settings()
            self.settingsChanged.emit()

    @Slot(str)
    def setLanguage(self, language: str):  # noqa: N802
        language = (language or "").strip().lower()
        if not language:
            return
        langs = [language] + [x for x in self._settings.languages if x != language]
        self._settings.languages = langs[:3]
        self._save_settings()
        self._rebuild_online_sources()
        self.settingsChanged.emit()
        self._load_listing(reset=True)

    @Slot(bool)
    def setDataSaver(self, value: bool):  # noqa: N802
        self._settings.data_saver = bool(value)
        self._save_settings()
        self._rebuild_online_sources()
        self.settingsChanged.emit()

    @Slot(bool)
    def setNsfw(self, value: bool):  # noqa: N802
        self._settings.nsfw = bool(value)
        self._save_settings()
        self._rebuild_online_sources()
        self.settingsChanged.emit()
        self._load_listing(reset=True)

    @Slot(str)
    def setLocalDir(self, path: str):  # noqa: N802
        self._settings.local_dir = path or ""
        self._save_settings()
        self._rebuild_online_sources()
        self.settingsChanged.emit()
        self._load_listing(reset=True)

    @Slot()
    def openDataDir(self):  # noqa: N802
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(self._settings.data_path)))

    @Slot()
    def openLocalDir(self):  # noqa: N802
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(self._settings.local_path)))

    # ================================================================== nội bộ
    def _source(self):
        return self._sources[self._source_id]

    def _save_settings(self):
        try:
            self._settings.save()
        except OSError as exc:
            self._set_status(f"Không lưu được cấu hình: {exc}")

    def _rebuild_online_sources(self):
        """Cấu hình đổi (ngôn ngữ, 18+, data saver) thì dựng lại nguồn MangaDex."""
        self._sources = build_sources(self._settings, transport=self._transport)
        self._source_id = (
            self._settings.source
            if self._settings.source in self._sources
            else "mangadex"
        )

    def _set_busy(self, value: bool):
        if self._busy != value:
            self._busy = value
            self.busyChanged.emit()

    def _set_status(self, text: str):
        if self._status != text:
            self._status = text
            self.statusChanged.emit()

    def _load_tags(self):
        if self._source().offline:
            self._tags = []
            return
        self._run("tags", 0, lambda: self._source().tags())

    def _load_listing(self, reset: bool):
        if reset:
            self._page = 0
            self._listing_req += 1
        req = self._listing_req
        source = self._source()
        self._set_busy(True)
        self._set_status("")
        page = self._page

        def work():
            if source.offline:
                if self._browse_mode == "search" and self._query:
                    return source.search(self._query)
                if self._browse_mode == "latest":
                    return source.latest()
                return source.popular()
            if self._browse_mode == "search" and self._query:
                return source.search(self._query, page)
            if self._browse_mode == "latest":
                return source.latest(page)
            return source.popular(page)

        self._run("listing", req, work, append=not reset)

    def _run(self, kind: str, req: int, fn: Callable, append: bool = False):
        def work():
            try:
                result = fn()
                self._resultReady.emit((kind, req, append, result, ""))
            except MangaError as exc:
                self._resultReady.emit((kind, req, append, None, str(exc)))
            except Exception as exc:  # noqa: BLE001 - lỗi lạ cũng không được làm sập giao diện
                self._resultReady.emit((kind, req, append, None, f"Lỗi không mong đợi: {exc}"))

        threading.Thread(target=work, daemon=True).start()

    @Slot(object)
    def _on_result(self, payload):
        kind, req, append, result, error = payload
        if kind == "listing":
            if req != self._listing_req:
                return
            self._set_busy(False)
            if error:
                self._set_status(error)
                return
            rows = [self._manga_row(item) for item in result.items]
            if append:
                self._manga.append_rows(rows)
            else:
                self._manga.set_rows(rows)
            self._page += 1
            self._has_more = result.has_more
            if not rows and not append:
                self._set_status("Không có truyện nào khớp.")
            self.listingChanged.emit()
        elif kind == "tags":
            if error or not result:
                return
            self._tags = result
            self.listingChanged.emit()
        elif kind == "details":
            if req != self._detail_req:
                return
            self._set_busy(False)
            if error:
                self._set_status(error)
                return
            self._current_manga = self._manga_row(result)
            self.currentMangaChanged.emit()
            self.favoriteChanged.emit()
            self._chapter_req += 1
            chapter_req = self._chapter_req
            manga_id = result.id
            source_id = result.source
            self._set_busy(True)
            self._run(
                "chapters",
                chapter_req,
                lambda: self._sources[source_id].chapters(manga_id, self._settings.languages),
            )
        elif kind == "chapters":
            if req != self._chapter_req:
                return
            self._set_busy(False)
            if error:
                self._set_status(error)
                return
            self._chapters = list(result)
            downloaded = set(
                self._library.downloaded_chapter_ids(
                    self._current_manga.get("source", ""), self._current_manga.get("id", "")
                )
            )
            self._chapters_model.set_rows(
                [self._chapter_row(ch, ch.id in downloaded) for ch in self._chapters]
            )
            self.chaptersChanged.emit()
            if self._pending_chapter_id:
                pending = self._pending_chapter_id
                self._pending_chapter_id = ""
                self.openChapterById(pending)
        elif kind == "pages":
            if req != self._page_req:
                return
            self._set_busy(False)
            if error:
                self._set_status(error)
                return
            self._reader = {
                "mangaId": result["mangaId"],
                "chapterId": result["chapterId"],
                "chapterIndex": result["chapterIndex"],
                "title": result["title"],
                "label": result["label"],
            }
            self._reader_pages = [_image_source(url) for url in result["urls"]]
            progress = self._library.get_progress(
                self._current_manga.get("source", ""), result["mangaId"]
            )
            start = 0
            if progress and progress.get("chapter_id") == result["chapterId"]:
                start = min(max(0, int(progress.get("page") or 0)), len(self._reader_pages) - 1)
            self._reader_index = start
            self._pages_model.set_rows(
                [
                    {"index": i, "url": url, "source": result["origin"]}
                    for i, url in enumerate(self._reader_pages)
                ]
            )
            self.readerChanged.emit()
            self.readerOpened.emit()
            self._record_reading(result)
        elif kind == "download":
            self._set_busy(False)
            if error:
                self._set_status(f"Tải chương thất bại: {error}")
                return
            self._set_status("Đã tải xong chương.")
            self.refreshDownloads()
            downloaded = set(
                self._library.downloaded_chapter_ids(
                    self._current_manga.get("source", ""), self._current_manga.get("id", "")
                )
            )
            for i, ch in enumerate(self._chapters):
                if ch.id in downloaded:
                    self._chapters_model.update_row(i, {"downloaded": True})
            self.chaptersChanged.emit()

    # ------------------------------------------------------------------ dựng dòng model
    def _manga_row(self, manga: Manga) -> dict:
        in_library = self._library.is_favorite(manga.source, manga.id)
        progress = self._library.get_progress(manga.source, manga.id)
        return {
            "source": manga.source,
            "id": manga.id,
            "title": manga.title,
            "cover": _image_source(manga.cover_thumb or manga.cover_url),
            "coverFull": manga.cover_url,
            "description": manga.description,
            "author": manga.author,
            "artist": manga.artist,
            "status": manga.status,
            "statusText": status_label(manga.status),
            "tags": list(manga.tags),
            "tagsText": ", ".join(manga.tags[:6]),
            "year": manga.year if manga.year else 0,
            "url": manga.url,
            "nsfw": manga.nsfw,
            "inLibrary": in_library,
            "progressText": (progress or {}).get("chapter_label", ""),
            "progressChapterId": (progress or {}).get("chapter_id", ""),
            "altTitle": manga.alt_title,
        }

    def _chapter_row(self, chapter: Chapter, downloaded: bool) -> dict:
        return {
            "id": chapter.id,
            "label": chapter_label(chapter.volume, chapter.number, chapter.title),
            "volume": chapter.volume,
            "number": chapter.number,
            "title": chapter.title,
            "language": chapter.language,
            "pages": chapter.pages,
            "publishedAt": chapter.published_at,
            "downloaded": downloaded,
            "external": chapter.external,
        }

    def _refresh_library_model(self):
        rows = []
        for entry in self._library.list_favorites(self._library_category or None):
            progress = self._library.get_progress(entry["source"], entry["manga_id"]) or {}
            rows.append(
                {
                    "source": entry["source"],
                    "id": entry["manga_id"],
                    "title": entry["title"],
                    "cover": _image_source(entry["cover"]),
                    "coverFull": entry["cover"],
                    "description": "",
                    "author": entry["author"],
                    "artist": "",
                    "status": "",
                    "statusText": "",
                    "tags": [],
                    "tagsText": "",
                    "year": 0,
                    "url": "",
                    "nsfw": False,
                    "inLibrary": True,
                    "progressText": progress.get("chapter_label", ""),
                    "progressChapterId": progress.get("chapter_id", ""),
                    "altTitle": "",
                }
            )
        self._library_model.set_rows(rows)
        self.libraryChanged.emit()

    def _current_chapter(self) -> Optional[Chapter]:
        chapter_id = self._reader.get("chapterId", "")
        for chapter in self._chapters:
            if chapter.id == chapter_id:
                return chapter
        return None

    def _record_reading(self, payload: dict):
        """Ghi lịch sử + tiến độ đọc mỗi khi mở chương."""
        source_id = self._current_manga.get("source", "")
        manga_id = payload["mangaId"]
        self._library.set_progress(
            source_id,
            manga_id,
            payload["chapterId"],
            payload["label"],
            self._reader_index,
        )
        manga = Manga(
            source=source_id,
            id=manga_id,
            title=payload["title"],
            cover_url=self._current_manga.get("coverFull", ""),
            cover_thumb=self._current_manga.get("cover", ""),
        )
        self._library.touch_history(manga)
        self.historyChanged.emit()

    def _save_progress(self):
        if not self._reader.get("chapterId"):
            return
        self._library.set_progress(
            self._current_manga.get("source", ""),
            self._reader.get("mangaId", ""),
            self._reader.get("chapterId", ""),
            self._reader.get("label", ""),
            self._reader_index,
        )

    # ------------------------------------------------------------------ khởi động
    def start(self):
        """Nạp dữ liệu ban đầu: kệ sách, lịch sử, tải xuống và trang khám phá."""
        self._refresh_library_model()
        self.refreshHistory()
        self.refreshDownloads()
        if not self._source().offline:
            self._load_tags()
        self._load_listing(reset=True)

    def shutdown(self):
        try:
            self._library.close()
        except Exception:  # noqa: BLE001 - đóng kho dữ liệu lúc thoát, lỗi thì thôi
            pass
