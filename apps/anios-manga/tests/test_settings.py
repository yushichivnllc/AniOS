"""Kiểm thử cấu hình: mặc định, đọc/ghi file, chặn giá trị lạ."""
from __future__ import annotations

from anios_manga.settings import (
    READER_MODES,
    THEMES,
    Settings,
    default_config_path,
    default_data_dir,
    default_local_dir,
)


def test_defaults_are_sensible():
    settings = Settings()
    assert settings.theme == "dark"
    assert settings.source == "mangadex"
    assert settings.reader_mode == "webtoon"
    assert settings.languages[:2] == ["vi", "en"]
    assert settings.nsfw is False
    assert settings.data_saver is False
    assert settings.local_dir
    assert settings.data_path == default_data_dir()
    assert settings.local_path == default_local_dir()


def test_load_returns_defaults_when_file_missing(tmp_path):
    assert Settings.load(tmp_path / "khong-co.json") == Settings()


def test_load_ignores_unknown_and_bad_values(tmp_path):
    path = tmp_path / "config.json"
    path.write_text('{"theme": "xanh lá", "reader_mode": "xoay", "languages": [], "la": 1}', encoding="utf-8")
    settings = Settings.load(path)
    assert settings.theme == "dark"
    assert settings.reader_mode == "webtoon"
    assert settings.languages == ["vi", "en"]


def test_save_and_load_round_trip(tmp_path):
    path = tmp_path / "config.json"
    settings = Settings(theme="light", reader_mode="rtl", languages=["en", "vi"], nsfw=True)
    settings.save(path)
    assert path.exists()
    assert Settings.load(path) == settings


def test_save_creates_parent_dirs_and_is_atomic(tmp_path):
    path = tmp_path / "sâu" / "hơn" / "config.json"
    Settings().save(path)
    assert path.is_file()
    assert not path.with_suffix(".tmp").exists()


def test_config_path_honours_env(monkeypatch, tmp_path):
    monkeypatch.setenv("ANIOS_MANGA_CONFIG", str(tmp_path / "tùy.json"))
    assert default_config_path() == tmp_path / "tùy.json"


def test_reader_modes_and_themes_are_exposed():
    assert "webtoon" in READER_MODES and "rtl" in READER_MODES
    assert set(THEMES) == {"dark", "light"}
