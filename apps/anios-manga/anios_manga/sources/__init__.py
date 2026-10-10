"""Danh sách nguồn truyện có sẵn.

Thêm nguồn mới: viết lớp cài đặt `MangaSource` rồi đăng ký một dòng trong
`build_sources()`. Backend và QML chỉ làm việc với giao diện chung.
"""
from __future__ import annotations

from typing import Dict, List, Optional

from ..paths import local_extract_dir
from ..settings import Settings
from .base import MangaSource
from .local import LocalSource
from .mangadex import MangaDexSource

SOURCE_IDS = ("mangadex", "local")


def build_sources(settings: Settings, transport=None) -> Dict[str, MangaSource]:
    """Tạo dict {id: nguồn} theo cấu hình hiện tại."""
    sources: Dict[str, MangaSource] = {
        "mangadex": MangaDexSource(
            nsfw=settings.nsfw,
            languages=settings.languages,
            data_saver=settings.data_saver,
            transport=transport,
        ),
        "local": LocalSource(settings.local_path, local_extract_dir(settings)),
    }
    return sources


def source_labels(sources: Optional[Dict[str, MangaSource]] = None) -> List[dict]:
    """Danh sách {id, name, offline} để hiển thị trong combobox Cài đặt."""
    srcs = sources if sources is not None else {}
    return [{"id": s.id, "name": s.name, "offline": s.offline} for s in srcs.values()]
