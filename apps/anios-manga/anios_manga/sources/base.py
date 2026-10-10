"""Hợp đồng chung cho mọi nguồn truyện và kiểu dữ liệu dùng chung.

Thêm nguồn mới = viết một lớp cài đặt `MangaSource` rồi đăng ký trong
`anios_manga/sources/__init__.py`. Backend và QML không cần biết nguồn là ai:
chúng chỉ làm việc với `Manga`, `Chapter` và danh sách URL ảnh.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import List, Optional

STATUS_LABELS = {
    "ongoing": "Đang ra",
    "completed": "Đã hoàn thành",
    "hiatus": "Tạm ngưng",
    "cancelled": "Đã huỷ",
    "releasing": "Đang ra",
}


def status_label(value: str) -> str:
    return STATUS_LABELS.get((value or "").strip().lower(), "")


@dataclass(slots=True)
class Manga:
    source: str
    id: str
    title: str
    cover_url: str = ""
    cover_thumb: str = ""  # ảnh bìa bản nhỏ cho lưới kết quả (nhẹ hơn nhiều)
    description: str = ""
    author: str = ""
    artist: str = ""
    status: str = ""
    tags: List[str] = field(default_factory=list)
    year: Optional[int] = None
    url: str = ""
    alt_title: str = ""
    nsfw: bool = False


@dataclass(slots=True)
class Chapter:
    id: str
    number: str = ""
    volume: str = ""
    title: str = ""
    language: str = ""
    pages: int = 0
    published_at: str = ""
    external: bool = False  # chương chỉ host bên ngoài (không đọc được trong app)


@dataclass(slots=True)
class Listing:
    items: List[Manga] = field(default_factory=list)
    has_more: bool = False


class MangaSource:
    """Giao diện tối thiểu một nguồn truyện phải có."""

    id: str = ""
    name: str = ""
    offline: bool = False  # True = không cần mạng (thư viện cục bộ)

    def popular(self, page: int = 0) -> Listing:
        raise NotImplementedError

    def latest(self, page: int = 0) -> Listing:
        raise NotImplementedError

    def search(self, query: str, page: int = 0) -> Listing:
        raise NotImplementedError

    def details(self, manga_id: str) -> Manga:
        raise NotImplementedError

    def chapters(self, manga_id: str, languages: Optional[List[str]] = None) -> List[Chapter]:
        raise NotImplementedError

    def page_urls(self, chapter: Chapter, *, data_saver: bool = False) -> List[str]:
        raise NotImplementedError

    def prepare_pages(self, chapter: Chapter, *, data_saver: bool = False) -> List[str]:
        """URL ảnh của một chương, sẵn sàng đưa vào reader.

        Mặc định chính là `page_urls`. Nguồn cục bộ ghi đè để giải nén chương trước
        rồi trả về đường dẫn `file://` (QML không đọc được file nén).
        """
        return self.page_urls(chapter, data_saver=data_saver)

    def tags(self) -> List[dict]:
        """Danh sách thể loại để làm bộ lọc: [{"id": ..., "name": ...}, ...]."""
        return []

    def manga_url(self, manga_id: str) -> str:
        return ""
