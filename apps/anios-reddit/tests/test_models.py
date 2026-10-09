from PySide6.QtCore import Qt
from PySide6.QtGui import QGuiApplication

from anios_reddit.models import COMMENT_ROLES, POST_ROLES, DictListModel


def _app():
    return QGuiApplication.instance() or QGuiApplication([])


def test_role_names_and_data():
    _app()
    model = DictListModel(POST_ROLES)
    names = {bytes(v).decode() for v in model.roleNames().values()}
    assert {"title", "score", "scoreText", "thumbnail", "isSelf"} <= names
    model.set_rows([{"title": "A", "score": 3}, {"title": "B", "score": 5}])
    assert model.rowCount() == 2
    role = [k for k, v in model.roleNames().items() if bytes(v) == b"title"][0]
    assert model.data(model.index(1, 0), role) == "B"
    assert model.data(model.index(5, 0), role) is None


def test_append_and_update_row():
    _app()
    model = DictListModel(COMMENT_ROLES)
    model.set_rows([{"id": "1", "body": "x", "depth": 0}])
    model.append_rows([{"id": "2", "body": "y", "depth": 1}])
    assert model.rowCount() == 2
    model.update_row(1, {"body": "z"})
    assert model.row(1)["body"] == "z"
    assert model.index(0, 0).isValid()
    assert model.flags(model.index(0, 0)) & Qt.ItemFlag.ItemIsEnabled
