"""Cấu hình người dùng, lưu ở ~/.config/anios-reddit/config.json (hoặc $ANIOS_REDDIT_CONFIG)."""
from __future__ import annotations

import json
import os
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Optional

DEFAULT_SUBREDDITS = ["all", "popular", "linux", "archlinux", "unixporn", "linux_gaming", "programming"]


def default_config_path() -> Path:
    override = os.environ.get("ANIOS_REDDIT_CONFIG")
    if override:
        return Path(override)
    base = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
    return base / "anios-reddit" / "config.json"


@dataclass
class Settings:
    client_id: str = ""
    contact: str = ""  # tên Reddit để đưa vào User-Agent (không bắt buộc)
    theme: str = "dark"  # "dark" hoặc "light"
    subreddits: list = field(default_factory=lambda: list(DEFAULT_SUBREDDITS))
    last_subreddit: str = "all"
    last_sort: str = "hot"

    @classmethod
    def load(cls, path: Optional[Path] = None) -> "Settings":
        path = path or default_config_path()
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return cls()
        known = {k: raw[k] for k in cls.__dataclass_fields__ if k in raw}
        settings = cls(**known)
        if settings.theme not in ("dark", "light"):
            settings.theme = "dark"
        if not settings.subreddits:
            settings.subreddits = list(DEFAULT_SUBREDDITS)
        return settings

    def save(self, path: Optional[Path] = None) -> Path:
        path = path or default_config_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".tmp")
        # Client ID không phải bí mật, nhưng vẫn giữ file chỉ đọc cho người dùng.
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(asdict(self), fh, ensure_ascii=False, indent=2)
        os.replace(tmp, path)
        return path
