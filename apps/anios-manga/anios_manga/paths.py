"""Đường dẫn dữ liệu của AniOS Manga (theo chuẩn XDG).

Toàn bộ dữ liệu người dùng nằm trong MỘT thư mục để dễ sao lưu/xoá:

    ~/.local/share/anios-manga/
        library.db          kệ sách, lịch sử đọc, danh sách tải xuống
        cache/images/       ảnh bìa và ảnh trang đã tải một lần
        downloads/          truyện tải về để đọc offline
        local/              bản giải nén tạm của chương CBZ/ZIP
"""
from __future__ import annotations

from pathlib import Path

from .settings import Settings


def data_root(settings: Settings) -> Path:
    return Path(settings.data_path)


def db_path(settings: Settings) -> Path:
    return data_root(settings) / "library.db"


def cache_dir(settings: Settings) -> Path:
    return data_root(settings) / "cache" / "images"


def download_dir(settings: Settings) -> Path:
    return data_root(settings) / "downloads"


def local_extract_dir(settings: Settings) -> Path:
    return data_root(settings) / "local"


def ensure_dirs(settings: Settings) -> None:
    for path in (
        data_root(settings),
        db_path(settings).parent,
        cache_dir(settings),
        download_dir(settings),
        local_extract_dir(settings),
    ):
        path.mkdir(parents=True, exist_ok=True)


def chapter_dir(settings: Settings, source_id: str, manga_id: str, chapter_id: str) -> Path:
    """Thư mục chứa ảnh một chương đã tải về (đường dẫn an toàn cho mọi id)."""
    from .util import safe_name

    base = download_dir(settings) / safe_name(source_id) / safe_name(manga_id)
    return base / safe_name(chapter_id)
