"""Kiểm thử model danh sách dùng chung cho QML."""
from __future__ import annotations

import pytest

pytest.importorskip("PySide6.QtCore")

from PySide6.QtCore import Qt  # noqa: E402

from anios_manga.models import (  # noqa: E402
    CHAPTER_ROLES,
    DOWNLOAD_ROLES,
    HISTORY_ROLES,
    MANGA_ROLES,
    PAGE_ROLES,
    DictListModel,
)

pytestmark = pytest.mark.usefixtures("qt_app")


def test_set_and_append_rows(qt_app):
    model = DictListModel(["id", "title"])
    model.set_rows([{"id": "1", "title": "A"}])
    assert model.rowCount() == 1
    model.append_rows([{"id": "2", "title": "B"}])
    assert model.rowCount() == 2
    assert model.row(1)["title"] == "B"


def test_data_returns_role_values(qt_app):
    model = DictListModel(["id", "title"])
    model.set_rows([{"id": "1", "title": "A"}])
    index = model.index(0, 0)
    role_ids = {bytes(name): rid for rid, name in model.roleNames().items()}
    assert model.data(index, role_ids[b"title"]) == "A"
    assert model.data(index, role_ids[b"id"]) == "1"
    assert model.data(index, Qt.ItemDataRole.UserRole + 99) is None


def test_row_out_of_range_is_none(qt_app):
    model = DictListModel(["id"])
    model.set_rows([{"id": "1"}])
    assert model.row(5) is None
    assert model.row(-1) is None


def test_update_row_emits_change(qt_app):
    model = DictListModel(["id", "downloaded"])
    model.set_rows([{"id": "ch-1", "downloaded": False}])
    model.update_row(0, {"downloaded": True})
    assert model.row(0)["downloaded"] is True


def test_index_of_finds_row(qt_app):
    model = DictListModel(["id", "title"])
    model.set_rows([{"id": "a"}, {"id": "b"}])
    assert model.index_of("id", "b") == 1
    assert model.index_of("id", "zzz") == -1


def test_clear_empties_model(qt_app):
    model = DictListModel(["id"])
    model.set_rows([{"id": "a"}])
    model.clear()
    assert model.rowCount() == 0


def test_every_role_list_is_unique():
    for roles in (MANGA_ROLES, CHAPTER_ROLES, PAGE_ROLES, HISTORY_ROLES, DOWNLOAD_ROLES):
        assert len(roles) == len(set(roles)), roles


def test_roles_cover_what_qml_uses():
    assert "cover" in MANGA_ROLES and "progressChapterId" in MANGA_ROLES
    assert "downloaded" in CHAPTER_ROLES and "label" in CHAPTER_ROLES
    assert "url" in PAGE_ROLES
    assert "sizeText" in DOWNLOAD_ROLES
    assert "chapterLabel" in HISTORY_ROLES
