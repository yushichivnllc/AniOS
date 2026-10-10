"""Kiểm thử kho dữ liệu SQLite: kệ sách, thể loại, tiến độ, lịch sử, tải xuống."""
from __future__ import annotations

import time

from anios_manga.library import DEFAULT_CATEGORY, Library
from anios_manga.sources.base import Manga


def manga(manga_id="m1", title="One Piece", source="mangadex"):
    return Manga(source=source, id=manga_id, title=title, cover_thumb="https://x/cover.jpg",
                 author="Oda", status="ongoing")


def test_favorites_round_trip(tmp_path):
    lib = Library(tmp_path / "library.db")
    lib.add_favorite(manga())
    assert lib.is_favorite("mangadex", "m1")
    rows = lib.list_favorites()
    assert len(rows) == 1
    assert rows[0]["title"] == "One Piece"
    assert rows[0]["category"] == DEFAULT_CATEGORY
    lib.remove_favorite("mangadex", "m1")
    assert not lib.is_favorite("mangadex", "m1")
    lib.close()


def test_favorite_is_upsert_not_duplicated(tmp_path):
    lib = Library(tmp_path / "library.db")
    lib.add_favorite(manga())
    lib.add_favorite(manga(title="Đảo Hải Tặc"), category="Yêu thích")
    rows = lib.list_favorites()
    assert len(rows) == 1
    assert rows[0]["title"] == "Đảo Hải Tặc"
    assert rows[0]["category"] == "Yêu thích"
    lib.close()


def test_favorites_filter_by_category(tmp_path):
    lib = Library(tmp_path / "library.db")
    lib.add_favorite(manga("m1"), category="A")
    lib.add_favorite(manga("m2", title="Berserk"), category="B")
    assert [r["manga_id"] for r in lib.list_favorites("A")] == ["m1"]
    assert len(lib.list_favorites()) == 2
    lib.close()


def test_categories_can_be_removed_and_reassign(tmp_path):
    lib = Library(tmp_path / "library.db")
    lib.add_category("Tu tiên")
    assert "Tu tiên" in lib.categories()
    lib.add_favorite(manga("m1"), category="Tu tiên")
    lib.remove_category("Tu tiên")
    assert "Tu tiên" not in lib.categories()
    assert lib.list_favorites()[0]["category"] == DEFAULT_CATEGORY
    lib.close()


def test_default_category_is_never_removed(tmp_path):
    lib = Library(tmp_path / "library.db")
    lib.remove_category(DEFAULT_CATEGORY)
    assert DEFAULT_CATEGORY in lib.categories()
    lib.close()


def test_progress_is_upserted_per_manga(tmp_path):
    lib = Library(tmp_path / "library.db")
    lib.set_progress("mangadex", "m1", "ch-1", "Chương 1", 0)
    lib.set_progress("mangadex", "m1", "ch-2", "Chương 2", 5)
    progress = lib.get_progress("mangadex", "m1")
    assert progress["chapter_id"] == "ch-2"
    assert progress["page"] == 5
    lib.close()


def test_history_joins_progress_and_orders_by_recency(tmp_path):
    lib = Library(tmp_path / "library.db")
    lib.add_favorite(manga("m1"))
    lib.touch_history(manga("m1"))
    lib.set_progress("mangadex", "m1", "ch-9", "Chương 9", 3)
    time.sleep(0.01)
    lib.touch_history(manga("m2", title="Berserk"))
    lib.set_progress("mangadex", "m2", "ch-1", "Chương 1", 0)

    history = lib.history()
    assert [h["manga_id"] for h in history] == ["m2", "m1"]
    assert history[1]["chapter_label"] == "Chương 9"
    assert history[1]["page"] == 3
    lib.close()


def test_history_entry_can_be_removed_with_progress(tmp_path):
    lib = Library(tmp_path / "library.db")
    lib.touch_history(manga("m1"))
    lib.set_progress("mangadex", "m1", "ch-1", "Chương 1", 0)
    lib.remove_history("mangadex", "m1")
    assert lib.history() == []
    assert lib.get_progress("mangadex", "m1") is None
    lib.close()


def test_clear_history_keeps_favorites(tmp_path):
    lib = Library(tmp_path / "library.db")
    lib.add_favorite(manga("m1"))
    lib.touch_history(manga("m1"))
    lib.clear_history()
    assert lib.history() == []
    assert lib.is_favorite("mangadex", "m1")
    lib.close()


def test_downloads_round_trip_and_size(tmp_path):
    lib = Library(tmp_path / "library.db")
    lib.add_download("mangadex", "m1", "ch-1", "Chương 1", "One Piece", "/tmp/dl", 20, 1024)
    lib.add_download("mangadex", "m1", "ch-2", "Chương 2", "One Piece", "/tmp/dl2", 18, 2048)
    assert lib.downloaded_chapter_ids("mangadex", "m1") == ["ch-1", "ch-2"]
    assert lib.total_download_size() == 3072
    assert lib.download_for("mangadex", "m1", "ch-2")["pages"] == 18

    removed = lib.remove_download("mangadex", "m1", "ch-1")
    assert removed["path"] == "/tmp/dl"
    assert lib.remove_download("mangadex", "m1", "ch-1") is None
    lib.close()


def test_stats_counts_favorites_and_downloads(tmp_path):
    lib = Library(tmp_path / "library.db")
    lib.add_favorite(manga("m1"))
    lib.add_favorite(manga("m2", title="Berserk"))
    lib.add_download("mangadex", "m1", "ch-1", "Chương 1", "One Piece", "/tmp/dl", 20, 1)
    assert lib.stats() == {"favorites": 2, "chapters": 1}
    lib.close()
