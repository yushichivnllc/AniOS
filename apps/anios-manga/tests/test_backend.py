"""Kiểm thử tích hợp backend: duyệt, chi tiết, chương, đọc, kệ sách, tải xuống."""
from __future__ import annotations

import pytest

from anios_manga.backend import Backend
from anios_manga.images import image_url
from anios_manga.settings import Settings
from conftest import pump

pytestmark = pytest.mark.usefixtures("qt_app")


@pytest.fixture()
def backend(settings, fake, qt_app):
    backend = Backend(settings, transport=fake)
    backend.start()
    assert pump(qt_app, lambda: backend.mangaModel.rowCount() == 3), "danh sách không tải xong"
    yield backend
    backend.shutdown()


def test_start_loads_popular_listing(backend, fake, qt_app):
    assert pump(qt_app, lambda: backend.mangaModel.rowCount() == 3)
    assert backend.busy is False
    assert backend.browseMode == "popular"
    assert backend.mangaModel.row(0)["title"] == "Đảo Hải Tặc"
    # Ảnh bìa được bọc qua image provider.
    assert backend.mangaModel.row(0)["cover"].startswith("image://manga/")


def test_start_loads_tags(backend, qt_app):
    assert pump(qt_app, lambda: len(backend.tags) == 4)
    assert backend.tags[0]["name"] == "Long Strip"


def test_search_switches_browse_mode(backend, qt_app):
    backend.search("one")
    assert backend.browseMode == "search"
    assert backend.query == "one"
    assert pump(qt_app, lambda: backend.mangaModel.rowCount() == 3)


def test_load_more_appends_page_two(backend, qt_app):
    assert pump(qt_app, lambda: backend.mangaModel.rowCount() == 3)
    assert backend.canLoadMore is True
    backend.loadMore()
    assert pump(qt_app, lambda: backend.mangaModel.rowCount() == 5)
    titles = [backend.mangaModel.row(i)["title"] for i in range(5)]
    assert titles[-2:] == ["Vagabond", "Monster"]


def test_open_manga_loads_details_then_chapters(backend, qt_app):
    assert pump(qt_app, lambda: backend.mangaModel.rowCount() == 3)
    backend.openManga(0)
    assert pump(qt_app, lambda: backend.chapterModel.rowCount() == 4)
    assert backend.currentManga["title"] == "Đảo Hải Tặc"
    assert backend.currentManga["statusText"] == "Đang ra"
    labels = [backend.chapterModel.row(i)["label"] for i in range(4)]
    assert labels == [
        "Chương 10 - Cuộc chiến",
        "Chương 9",
        "Chương 5.5 - Ngoại truyện",
        "Oneshot",
    ]


def test_open_chapter_resolves_pages_and_records_progress(backend, qt_app):
    backend.openManga(0)
    assert pump(qt_app, lambda: backend.chapterModel.rowCount() == 4)
    opened = []
    backend.readerOpened.connect(lambda: opened.append(True))
    backend.openChapter(0)
    assert pump(qt_app, lambda: backend.readerCount == 3)
    assert opened == [True]
    assert backend.readerIndex == 0
    assert backend.readerLabel == "Chương 10 - Cuộc chiến"
    assert backend.readerProgressText == "Trang 1/3"
    assert backend.readerPages.row(2)["url"].endswith("3.png")
    assert backend.hasProgress is True


def test_reader_page_change_saves_progress(backend, qt_app):
    backend.openManga(0)
    assert pump(qt_app, lambda: backend.chapterModel.rowCount() == 4)
    backend.openChapter(0)
    assert pump(qt_app, lambda: backend.readerCount == 3)
    backend.readerSetPage(2)
    assert backend.readerIndex == 2
    progress = backend._library.get_progress("mangadex", backend.currentManga["id"])
    assert progress["page"] == 2
    assert progress["chapter_id"] == "ch-010"


def test_open_continue_reopens_saved_chapter(backend, qt_app):
    backend.openManga(0)
    assert pump(qt_app, lambda: backend.chapterModel.rowCount() == 4)
    backend.openChapter(1)
    assert pump(qt_app, lambda: backend.readerCount == 3)
    backend.closeReader()
    backend.openContinue()
    assert pump(qt_app, lambda: backend.readerLabel == "Chương 9")
    assert backend.readerIndex == 0


def test_chapter_navigation_bounds(backend, qt_app):
    backend.openManga(0)
    assert pump(qt_app, lambda: backend.chapterModel.rowCount() == 4)
    backend.openChapter(0)
    assert pump(qt_app, lambda: backend.readerCount == 3)
    # Danh sách chương mới nhất trước: chương "trước" là chương cũ hơn.
    assert backend.canPrevChapter is True
    assert backend.canNextChapter is False
    backend.readerPrevChapter()
    assert pump(qt_app, lambda: backend.readerLabel == "Chương 9")


def test_favorite_toggles_and_appears_in_library(backend, qt_app):
    backend.openManga(0)
    assert pump(qt_app, lambda: bool(backend.currentManga.get("id")))
    assert backend.favorite is False
    backend.toggleFavorite()
    assert backend.favorite is True
    assert pump(qt_app, lambda: backend.libraryModel.rowCount() == 1)
    assert backend.libraryModel.row(0)["title"] == "Đảo Hải Tặc"
    assert backend.favoriteCount == 1
    backend.toggleFavorite()
    assert backend.favorite is False
    assert pump(qt_app, lambda: backend.libraryModel.rowCount() == 0)


def test_favorite_categories_flow(backend, qt_app):
    backend.openManga(0)
    assert pump(qt_app, lambda: bool(backend.currentManga.get("id")))
    backend.toggleFavorite()
    backend.setFavoriteCategory("Tu tiên")
    assert "Tu tiên" in backend.categories
    assert backend.favoriteCategory == "Tu tiên"
    backend.setLibraryCategory("Tu tiên")
    assert backend.libraryCategory == "Tu tiên"
    assert pump(qt_app, lambda: backend.libraryModel.rowCount() == 1)


def test_download_chapter_marks_downloaded(backend, qt_app, settings):
    backend.openManga(0)
    assert pump(qt_app, lambda: backend.chapterModel.rowCount() == 4)
    assert backend.chapterModel.row(0)["downloaded"] is False
    backend.downloadChapterById(backend.chapterModel.row(0)["id"])
    assert pump(qt_app, lambda: backend.chapterModel.row(0)["downloaded"] is True, timeout=15)
    assert pump(qt_app, lambda: backend.downloadsModel.rowCount() == 1)
    assert backend.downloadsModel.row(0)["pages"] == 3
    assert backend.downloadSizeText != ""


def test_open_manga_and_chapter_waits_for_chapter_list(backend, qt_app):
    # Kệ sách/Tải xuống gọi đường này: chương chỉ mở được sau khi danh sách chương về.
    backend.openMangaAndChapter("mangadex", "a1a1a1a1-1111-4111-8111-111111111111", "ch-009")
    assert pump(qt_app, lambda: backend.readerCount == 3)
    assert backend.readerLabel == "Chương 9"


def test_history_records_reading(backend, qt_app):
    backend.openManga(0)
    assert pump(qt_app, lambda: backend.chapterModel.rowCount() == 4)
    backend.openChapter(0)
    assert pump(qt_app, lambda: backend.readerCount == 3)
    backend.refreshHistory()
    assert backend.historyModel.rowCount() == 1
    assert backend.historyModel.row(0)["title"] == "Đảo Hải Tặc"
    assert backend.historyModel.row(0)["chapterLabel"] == "Chương 10 - Cuộc chiến"


def test_settings_changes_persist(backend, qt_app, tmp_path):
    backend.setTheme("light")
    backend.setReaderMode("rtl")
    backend.setLanguage("en")
    assert backend.darkTheme is False
    assert backend.readerMode == "rtl"
    assert backend.language == "en"
    assert Settings.load(tmp_path / "config.json").theme == "light"
    assert Settings.load(tmp_path / "config.json").reader_mode == "rtl"


def test_switching_to_local_source_works(backend, qt_app, tmp_path, settings):
    manga_dir = tmp_path / "Manga"
    (manga_dir / "Bộ").mkdir(parents=True)
    import zipfile

    with zipfile.ZipFile(manga_dir / "Bộ" / "ch1.cbz", "w") as zf:
        zf.writestr("1.png", b"\x89PNG")
        zf.writestr("2.png", b"\x89PNG")
    backend.setLocalDir(str(manga_dir))
    backend.setSource("local")
    assert backend.currentSource == "local"
    assert pump(qt_app, lambda: backend.mangaModel.rowCount() == 1)
    backend.openManga(0)
    assert pump(qt_app, lambda: backend.chapterModel.rowCount() == 1)
    backend.openChapter(0)
    assert pump(qt_app, lambda: backend.readerCount == 2)
    # Trang cục bộ vẫn đi qua image provider; giải mã id sẽ ra đường dẫn file://.
    url = backend.readerPages.row(0)["url"]
    assert url.startswith("image://manga/")
    assert image_url(url[len("image://manga/"):]).startswith("file://")


def test_network_error_is_reported_in_status(backend, qt_app, fake):
    fake.fail["/manga/"] = (503, "MangaDex đang quá tải")
    backend.openManga(0)
    assert pump(qt_app, lambda: backend.status != "")
    assert "503" in backend.status or "quá tải" in backend.status
    assert backend.busy is False


def test_stale_results_are_discarded(backend, qt_app, fake):
    """Bấm mở hai truyện liên tiếp: kết quả của truyện cũ bị bỏ qua."""
    backend.openManga(0)
    backend.openManga(1)
    assert pump(qt_app, lambda: backend.currentManga.get("id", "").startswith("b2b2b2b2"))


def test_close_manga_clears_state(backend, qt_app):
    backend.openManga(0)
    assert pump(qt_app, lambda: backend.chapterModel.rowCount() == 4)
    backend.closeManga()
    assert backend.currentManga == {}
    assert backend.chapterModel.rowCount() == 0
    assert backend.favorite is False


def test_reader_mode_options_are_labelled(backend):
    options = backend.readerModeOptions
    assert [o["id"] for o in options] == ["webtoon", "paged", "rtl"]
    assert options[0]["name"].startswith("Cuộn")
