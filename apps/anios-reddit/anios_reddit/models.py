"""Model danh sách cho QML. Một lớp tổng quát dựa trên dict để dùng cho bài viết và bình luận."""
from __future__ import annotations

from typing import Any, Iterable

from PySide6.QtCore import QAbstractListModel, QByteArray, QModelIndex, Qt


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

    def row(self, index: int) -> dict | None:
        if 0 <= index < len(self._rows):
            return dict(self._rows[index])
        return None

    def rows(self) -> list[dict]:
        return list(self._rows)

    def update_row(self, index: int, values: dict[str, Any]) -> None:
        if not (0 <= index < len(self._rows)):
            return
        self._rows[index].update(values)
        idx = self.index(index, 0)
        self.dataChanged.emit(idx, idx, list(self._role_ids.keys()))


POST_ROLES = [
    "id", "fullname", "title", "author", "subreddit", "score", "numComments", "created",
    "permalink", "url", "domain", "isSelf", "selftext", "thumbnail", "flair", "nsfw",
    "stickied", "isVideo", "scoreText", "commentsText", "ageText",
]
COMMENT_ROLES = ["id", "author", "body", "score", "created", "depth", "isOp"]
