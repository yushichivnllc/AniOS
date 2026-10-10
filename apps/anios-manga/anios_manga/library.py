"""Kho dữ liệu cục bộ (SQLite): kệ sách, lịch sử đọc, truyện đã tải.

Một file duy nhất `library.db` trong thư mục dữ liệu của app. Backend gọi các hàm
này từ luồng nền nên mọi thao tác đều khoá bằng một lock; sqlite3 mở với
`check_same_thread=False` để dùng chung một kết nối.
"""
from __future__ import annotations

import sqlite3
import threading
import time
from pathlib import Path
from typing import Dict, List, Optional

from .sources.base import Manga

DEFAULT_CATEGORY = "Mặc định"

SCHEMA = """
CREATE TABLE IF NOT EXISTS favorites (
    source     TEXT NOT NULL,
    manga_id   TEXT NOT NULL,
    title      TEXT NOT NULL DEFAULT '',
    cover      TEXT NOT NULL DEFAULT '',
    author     TEXT NOT NULL DEFAULT '',
    category   TEXT NOT NULL DEFAULT 'Mặc định',
    added_at   REAL NOT NULL DEFAULT 0,
    PRIMARY KEY (source, manga_id)
);
CREATE TABLE IF NOT EXISTS categories (
    name       TEXT PRIMARY KEY,
    created_at REAL NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS progress (
    source       TEXT NOT NULL,
    manga_id     TEXT NOT NULL,
    chapter_id   TEXT NOT NULL DEFAULT '',
    chapter_label TEXT NOT NULL DEFAULT '',
    page         INTEGER NOT NULL DEFAULT 0,
    updated_at   REAL NOT NULL DEFAULT 0,
    PRIMARY KEY (source, manga_id)
);
CREATE TABLE IF NOT EXISTS history (
    source      TEXT NOT NULL,
    manga_id    TEXT NOT NULL,
    title       TEXT NOT NULL DEFAULT '',
    cover       TEXT NOT NULL DEFAULT '',
    updated_at  REAL NOT NULL DEFAULT 0,
    PRIMARY KEY (source, manga_id)
);
CREATE TABLE IF NOT EXISTS downloads (
    source       TEXT NOT NULL,
    manga_id     TEXT NOT NULL,
    chapter_id   TEXT NOT NULL,
    chapter_label TEXT NOT NULL DEFAULT '',
    manga_title  TEXT NOT NULL DEFAULT '',
    path         TEXT NOT NULL DEFAULT '',
    pages        INTEGER NOT NULL DEFAULT 0,
    size         INTEGER NOT NULL DEFAULT 0,
    created_at   REAL NOT NULL DEFAULT 0,
    PRIMARY KEY (source, manga_id, chapter_id)
);
"""


class Library:
    def __init__(self, path: Path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.RLock()
        self._conn = sqlite3.connect(str(self.path), check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self._conn.execute("PRAGMA journal_mode=WAL")
        self._conn.execute("PRAGMA foreign_keys=ON")
        with self._lock:
            self._conn.executescript(SCHEMA)
            self._conn.execute(
                "INSERT OR IGNORE INTO categories (name, created_at) VALUES (?, ?)",
                (DEFAULT_CATEGORY, time.time()),
            )
            self._conn.commit()

    def close(self) -> None:
        with self._lock:
            self._conn.close()

    # ------------------------------------------------------------------ kệ sách
    def add_favorite(self, manga: Manga, category: str = DEFAULT_CATEGORY) -> None:
        with self._lock:
            self._conn.execute(
                """INSERT INTO favorites (source, manga_id, title, cover, author, category, added_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?)
                   ON CONFLICT(source, manga_id) DO UPDATE SET
                       title=excluded.title, cover=excluded.cover, author=excluded.author,
                       category=excluded.category""",
                (
                    manga.source,
                    manga.id,
                    manga.title,
                    manga.cover_thumb or manga.cover_url,
                    manga.author,
                    category or DEFAULT_CATEGORY,
                    time.time(),
                ),
            )
            self._conn.commit()

    def remove_favorite(self, source: str, manga_id: str) -> None:
        with self._lock:
            self._conn.execute(
                "DELETE FROM favorites WHERE source = ? AND manga_id = ?", (source, manga_id)
            )
            self._conn.commit()

    def is_favorite(self, source: str, manga_id: str) -> bool:
        with self._lock:
            row = self._conn.execute(
                "SELECT 1 FROM favorites WHERE source = ? AND manga_id = ?", (source, manga_id)
            ).fetchone()
        return row is not None

    def list_favorites(self, category: Optional[str] = None) -> List[dict]:
        query = "SELECT * FROM favorites"
        params: tuple = ()
        if category:
            query += " WHERE category = ?"
            params = (category,)
        query += " ORDER BY added_at DESC"
        with self._lock:
            rows = self._conn.execute(query, params).fetchall()
        return [dict(r) for r in rows]

    def set_favorite_category(self, source: str, manga_id: str, category: str) -> None:
        with self._lock:
            self._conn.execute(
                "UPDATE favorites SET category = ? WHERE source = ? AND manga_id = ?",
                (category or DEFAULT_CATEGORY, source, manga_id),
            )
            self._conn.commit()

    # ------------------------------------------------------------------ thể loại kệ
    def categories(self) -> List[str]:
        with self._lock:
            rows = self._conn.execute("SELECT name FROM categories ORDER BY created_at").fetchall()
        return [r["name"] for r in rows]

    def add_category(self, name: str) -> None:
        name = (name or "").strip()
        if not name:
            return
        with self._lock:
            self._conn.execute(
                "INSERT OR IGNORE INTO categories (name, created_at) VALUES (?, ?)",
                (name, time.time()),
            )
            self._conn.commit()

    def remove_category(self, name: str) -> None:
        name = (name or "").strip()
        if not name or name == DEFAULT_CATEGORY:
            return
        with self._lock:
            self._conn.execute("DELETE FROM categories WHERE name = ?", (name,))
            # Truyện trong thể loại bị xoá quay về "Mặc định" chứ không mất khỏi kệ.
            self._conn.execute(
                "UPDATE favorites SET category = ? WHERE category = ?", (DEFAULT_CATEGORY, name)
            )
            self._conn.commit()

    # ------------------------------------------------------------------ tiến độ đọc
    def set_progress(
        self, source: str, manga_id: str, chapter_id: str, chapter_label: str, page: int
    ) -> None:
        with self._lock:
            self._conn.execute(
                """INSERT INTO progress (source, manga_id, chapter_id, chapter_label, page, updated_at)
                   VALUES (?, ?, ?, ?, ?, ?)
                   ON CONFLICT(source, manga_id) DO UPDATE SET
                       chapter_id=excluded.chapter_id, chapter_label=excluded.chapter_label,
                       page=excluded.page, updated_at=excluded.updated_at""",
                (source, manga_id, chapter_id, chapter_label, int(page), time.time()),
            )
            self._conn.commit()

    def get_progress(self, source: str, manga_id: str) -> Optional[dict]:
        with self._lock:
            row = self._conn.execute(
                "SELECT * FROM progress WHERE source = ? AND manga_id = ?", (source, manga_id)
            ).fetchone()
        return dict(row) if row else None

    def history(self, limit: int = 100) -> List[dict]:
        with self._lock:
            rows = self._conn.execute(
                """SELECT h.*, p.chapter_id, p.chapter_label, p.page
                   FROM history h LEFT JOIN progress p
                     ON p.source = h.source AND p.manga_id = h.manga_id
                   ORDER BY h.updated_at DESC LIMIT ?""",
                (int(limit),),
            ).fetchall()
        return [dict(r) for r in rows]

    def touch_history(self, manga: Manga) -> None:
        """Ghi nhận vừa mở truyện (dùng cho trang Lịch sử)."""
        with self._lock:
            self._conn.execute(
                """INSERT INTO history (source, manga_id, title, cover, updated_at)
                   VALUES (?, ?, ?, ?, ?)
                   ON CONFLICT(source, manga_id) DO UPDATE SET
                       title=excluded.title, cover=excluded.cover, updated_at=excluded.updated_at""",
                (
                    manga.source,
                    manga.id,
                    manga.title,
                    manga.cover_thumb or manga.cover_url,
                    time.time(),
                ),
            )
            self._conn.commit()

    def remove_history(self, source: str, manga_id: str) -> None:
        with self._lock:
            self._conn.execute(
                "DELETE FROM history WHERE source = ? AND manga_id = ?", (source, manga_id)
            )
            self._conn.execute(
                "DELETE FROM progress WHERE source = ? AND manga_id = ?", (source, manga_id)
            )
            self._conn.commit()

    def clear_history(self) -> None:
        with self._lock:
            self._conn.execute("DELETE FROM history")
            self._conn.execute("DELETE FROM progress")
            self._conn.commit()

    # ------------------------------------------------------------------ tải xuống
    def add_download(
        self,
        source: str,
        manga_id: str,
        chapter_id: str,
        chapter_label: str,
        manga_title: str,
        path: str,
        pages: int,
        size: int,
    ) -> None:
        with self._lock:
            self._conn.execute(
                """INSERT INTO downloads (source, manga_id, chapter_id, chapter_label, manga_title,
                                          path, pages, size, created_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                   ON CONFLICT(source, manga_id, chapter_id) DO UPDATE SET
                       chapter_label=excluded.chapter_label, manga_title=excluded.manga_title,
                       path=excluded.path, pages=excluded.pages, size=excluded.size""",
                (
                    source,
                    manga_id,
                    chapter_id,
                    chapter_label,
                    manga_title,
                    path,
                    int(pages),
                    int(size),
                    time.time(),
                ),
            )
            self._conn.commit()

    def remove_download(self, source: str, manga_id: str, chapter_id: str) -> Optional[dict]:
        with self._lock:
            row = self._conn.execute(
                "SELECT * FROM downloads WHERE source = ? AND manga_id = ? AND chapter_id = ?",
                (source, manga_id, chapter_id),
            ).fetchone()
            if row is None:
                return None
            self._conn.execute(
                "DELETE FROM downloads WHERE source = ? AND manga_id = ? AND chapter_id = ?",
                (source, manga_id, chapter_id),
            )
            self._conn.commit()
        return dict(row) if row else None

    def downloads(self) -> List[dict]:
        with self._lock:
            rows = self._conn.execute(
                "SELECT * FROM downloads ORDER BY created_at DESC"
            ).fetchall()
        return [dict(r) for r in rows]

    def downloaded_chapter_ids(self, source: str, manga_id: str) -> List[str]:
        with self._lock:
            rows = self._conn.execute(
                "SELECT chapter_id FROM downloads WHERE source = ? AND manga_id = ?",
                (source, manga_id),
            ).fetchall()
        return [r["chapter_id"] for r in rows]

    def download_for(self, source: str, manga_id: str, chapter_id: str) -> Optional[dict]:
        with self._lock:
            row = self._conn.execute(
                "SELECT * FROM downloads WHERE source = ? AND manga_id = ? AND chapter_id = ?",
                (source, manga_id, chapter_id),
            ).fetchone()
        return dict(row) if row else None

    def total_download_size(self) -> int:
        with self._lock:
            row = self._conn.execute("SELECT COALESCE(SUM(size), 0) AS total FROM downloads").fetchone()
        return int(row["total"]) if row else 0

    def stats(self) -> Dict[str, int]:
        """Số liệu ngắn cho trang Cài đặt."""
        with self._lock:
            favorites = self._conn.execute("SELECT COUNT(*) AS n FROM favorites").fetchone()["n"]
            chapters = self._conn.execute("SELECT COUNT(*) AS n FROM downloads").fetchone()["n"]
        return {"favorites": int(favorites), "chapters": int(chapters)}
