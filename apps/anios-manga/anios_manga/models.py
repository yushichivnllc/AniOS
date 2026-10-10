"""Model danh sách cho QML: một lớp tổng quát dựa trên dict (đúng kiểu apps/anios-reddit)."""
from __future__ import annotations

from typing import Any, Iterable

from PySide6.QtCore import (
    QAbstractListModel,
    QByteArray,
    QModelIndex,
    Qt,
    Signal,
    Slot,
)


class DictListModel(QAbstractListModel):
    def __init__(self, roles: Iterable[str], parent=None):
        super().__init__(parent)
        self._roles = list(roles)
        self._rows: list[dict] = []
        self._role_ids = {Qt.ItemDataRole.UserRole + i + 1: name for i, name in enumerate(self._roles)}

    # -- Qt API
    def roleNames(self):  # noqa: N802 (tên Qt)
        return {rid: QByteArray(name.encode()) for rid, name in self._role_ids.items()}

    def rowCount(self, parent=QModelIndex()):  # noqa: N802
        return 0 if parent.isValid() else len(self._rows)

    def data(self, index, role=Qt.ItemDataRole.DisplayRole):
        if not index.isValid() or not (0 <= index.row() < len(self._rows)):
            return None
        name = self._role_ids.get(role)
        if name is None:
            return None
        return self._rows[index.row()].get(name)

    # -- helpers
    def set_rows(self, rows: list[dict]) -> None:
        self.beginResetModel()
        self._rows = list(rows)
        self.endResetModel()

    def append_rows(self, rows: list[dict]) -> None:
        if not rows:
            return
        start = len(self._rows)
        self.beginInsertRows(QModelIndex(), start, start + len(rows) - 1)
        self._rows.extend(rows)
        self.endInsertRows()

    def clear(self) -> None:
        self.set_rows([])

    @Slot(int, result="QVariant")
    def row(self, index: int) -> dict | None:
        """Lấy một dòng theo vị trí (QML gọi được nên phải là Slot)."""
        if 0 <= index < len(self._rows):
            return dict(self._rows[index])
        return None

    def rows(self) -> list[dict]:
        return list(self._rows)

    def index_of(self, key: str, value: Any) -> int:
        for i, row in enumerate(self._rows):
            if row.get(key) == value:
                return i
        return -1

    def update_row(self, index: int, values: dict[str, Any]) -> None:
        if not (0 <= index < len(self._rows)):
            return
        self._rows[index].update(values)
        idx = self.index(index, 0)
        self.dataChanged.emit(idx, idx, list(self._role_ids.keys()))


# Vai trò của một dòng trong lưới truyện (khám phá / kệ sách / tìm kiếm).
MANGA_ROLES = [
    "source", "id", "title", "cover", "coverFull", "description", "author", "artist",
    "status", "statusText", "tags", "tagsText", "year", "url", "nsfw", "inLibrary",
    "progressText", "progressChapterId", "altTitle",
]

# Vai trò của một dòng trong danh sách chương.
CHAPTER_ROLES = [
    "id", "label", "volume", "number", "title", "language", "pages", "publishedAt",
    "downloaded", "external",
]

# Vai trò của một trang ảnh trong reader.
PAGE_ROLES = ["index", "url", "source"]

# Vai trò của một dòng trong trang Lịch sử.
HISTORY_ROLES = [
    "source", "mangaId", "title", "cover", "chapterId", "chapterLabel", "page",
    "updatedAt", "updatedText",
]

# Vai trò của một dòng trong trang Tải xuống.
DOWNLOAD_ROLES = [
    "source", "mangaId", "chapterId", "label", "title", "pages", "sizeText", "path",
]
