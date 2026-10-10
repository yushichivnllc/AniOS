"""Cấu hình người dùng, lưu ở ~/.config/anios-manga/config.json (hoặc $ANIOS_MANGA_CONFIG)."""
from __future__ import annotations

import json
import os
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import List

APP_ID = "anios-manga"

THEMES = ("dark", "light")
# Cuộn dọc (webtoon) là mặc định vì đa số truyện hiện nay phát hành dạng dài.
READER_MODES = ("webtoon", "paged", "rtl")


def default_config_path() -> Path:
    override = os.environ.get("ANIOS_MANGA_CONFIG")
    if override:
        return Path(override)
    base = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
    return base / APP_ID / "config.json"


def default_data_dir() -> Path:
    base = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local" / "share")
    return base / APP_ID


def default_local_dir() -> Path:
    return Path.home() / "Manga"


@dataclass
class Settings:
    theme: str = "dark"
    # Nguồn mặc định: MangaDex (API công khai, không cần khoá).
    source: str = "mangadex"
    # Ngôn ngữ ưu tiên khi lấy danh sách chương; MangaDex nhận nhiều ngôn ngữ.
    languages: List[str] = field(default_factory=lambda: ["vi", "en"])
    reader_mode: str = "webtoon"
    data_saver: bool = False  # ảnh nén của MangaDex (nhẹ hơn, phù hợp mạng chậm)
    nsfw: bool = False  # cho phép nội dung 18+
    # Thư mục chứa CBZ/ZIP của người dùng cho nguồn "Thư viện cục bộ".
    local_dir: str = ""
    # Bộ lọc thể loại của trang khám phá (id tag MangaDex), rỗng = tất cả.
    explore_tag: str = ""

    def __post_init__(self) -> None:
        # Chuẩn hoá ngay khi tạo: lưu/đọc nhiều lần không tích luỹ giá trị lạ.
        if self.theme not in THEMES:
            self.theme = "dark"
        if self.reader_mode not in READER_MODES:
            self.reader_mode = "webtoon"
        langs = [str(x).strip().lower() for x in self.languages if str(x).strip()]
        self.languages = langs or ["vi", "en"]
        if not self.local_dir:
            self.local_dir = str(default_local_dir())

    @property
    def local_path(self) -> Path:
        return Path(self.local_dir).expanduser()

    @property
    def data_path(self) -> Path:
        return default_data_dir()

    @classmethod
    def load(cls, path: Path | None = None) -> "Settings":
        path = path or default_config_path()
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return cls()
        if not isinstance(raw, dict):
            return cls()
        known = {k: raw[k] for k in cls.__dataclass_fields__ if k in raw}
        return cls(**known)

    def save(self, path: Path | None = None) -> Path:
        path = path or default_config_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".tmp")
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(asdict(self), fh, ensure_ascii=False, indent=2)
        os.replace(tmp, path)
        return path
