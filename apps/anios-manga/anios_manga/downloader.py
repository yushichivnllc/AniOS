"""Tải một chương về máy để đọc offline.

Mỗi chương là một thư mục chứa ảnh đánh số (`0001.jpg`, `0002.jpg`...) kèm
`meta.json` mô tả nguồn gốc. Tải lại thì bỏ qua các ảnh đã có, nên mất mạng giữa
chừng chỉ cần chạy lại là tiếp tục chứ không tải lại từ đầu.
"""
from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Callable, List, Optional

from .http import MangaError, default_bytes_transport, request_bytes
from .paths import chapter_dir
from .settings import Settings
from .sources.base import Chapter, MangaSource
from .util import format_size

ProgressCallback = Callable[[int, int], None]


def downloaded_pages(path: Path) -> List[str]:
    """Đường dẫn `file://` của các ảnh trong thư mục đã tải, theo thứ tự đọc."""
    if not path.is_dir():
        return []
    images = sorted(
        (p for p in path.iterdir() if p.is_file() and p.suffix.lower() in
         (".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".avif")),
        key=lambda p: p.name,
    )
    return [img.resolve().as_uri() for img in images]


def download_chapter(
    *,
    source: MangaSource,
    manga_id: str,
    manga_title: str,
    chapter: Chapter,
    settings: Settings,
    transport=default_bytes_transport,
    progress: Optional[ProgressCallback] = None,
) -> dict:
    """Tải toàn bộ ảnh của `chapter`; trả về thông tin để ghi vào kho dữ liệu."""
    # Chạy thật không truyền transport: phải tự rơi về bản giữ nguyên byte của ảnh.
    if transport is None:
        transport = default_bytes_transport
    dest = chapter_dir(settings, source.id, manga_id, chapter.id)
    dest.mkdir(parents=True, exist_ok=True)
    urls = source.page_urls(chapter, data_saver=settings.data_saver)
    if not urls:
        raise MangaError("Chương này không có ảnh để tải.")

    total = len(urls)
    for index, url in enumerate(urls, start=1):
        suffix = _suffix_of(url)
        target = dest / f"{index:04d}{suffix}"
        if target.is_file() and target.stat().st_size > 0:
            if progress:
                progress(index, total)
            continue
        data = request_bytes(url, transport=transport, action="tải ảnh truyện")
        tmp = target.with_suffix(".part")
        tmp.write_bytes(data)
        tmp.replace(target)
        if progress:
            progress(index, total)

    meta = {
        "source": source.id,
        "manga_id": manga_id,
        "manga_title": manga_title,
        "chapter_id": chapter.id,
        "chapter_label": _chapter_label(chapter),
        "pages": total,
        "created_at": time.time(),
    }
    (dest / "meta.json").write_text(
        json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    size = sum(p.stat().st_size for p in dest.iterdir() if p.is_file())
    return {
        "path": str(dest),
        "pages": total,
        "size": size,
        "size_text": format_size(size),
    }


def _suffix_of(url: str) -> str:
    """Lấy đuôi file từ URL, bỏ query string; mặc định .jpg."""
    from urllib.parse import unquote, urlsplit

    name = unquote(urlsplit(url).path).rsplit("/", 1)[-1]
    if "." in name:
        suffix = name[name.rfind("."):].lower()
        if suffix in (".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".avif"):
            return suffix
    return ".jpg"


def _chapter_label(chapter: Chapter) -> str:
    from .util import chapter_label

    return chapter_label(chapter.volume, chapter.number, chapter.title)


def read_meta(path: Path) -> dict:
    meta_file = Path(path) / "meta.json"
    try:
        return json.loads(meta_file.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
