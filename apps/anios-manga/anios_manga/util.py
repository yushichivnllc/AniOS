"""Hàm tiện ích dùng chung: làm sạch tên file, sắp xếp tự nhiên, định dạng dung lượng."""
from __future__ import annotations

import re
from pathlib import Path
from typing import Iterable, List

_SAFE = re.compile(r"[^A-Za-z0-9._-]+")


def safe_name(value: str, fallback: str = "unknown", max_len: int = 80) -> str:
    """Biến một id bất kỳ thành tên file an toàn (id của MangaDex là uuid nên không vấn đề gì,
    nhưng tiêu truyện do người dùng tự đặt thì có dấu cách, dấu '/', emoji...)."""
    cleaned = _SAFE.sub("_", (value or "").strip()).strip("._-")
    if not cleaned:
        cleaned = fallback
    return cleaned[:max_len] or fallback


_NUM = re.compile(r"(\d+)")


def natural_key(name: str) -> List:
    """Khoá sắp xếp tự nhiên: 'vol 2' < 'vol 10' (không dùng so sánh chuỗi thuần)."""
    parts = _NUM.split(name.lower())
    return [int(p) if p.isdigit() else p for p in parts]


def sorted_images(files: Iterable[Path]) -> List[Path]:
    """Sắp xếp file ảnh theo thứ tự đọc (tự nhiên, không phân biệt hoa thường)."""
    exts = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".avif"}
    images = [p for p in files if p.suffix.lower() in exts and p.is_file()]
    return sorted(images, key=lambda p: natural_key(p.name))


def format_size(num_bytes: int) -> str:
    """Dung lượng kiểu '12,3 MB' để hiển thị trong danh sách tải xuống."""
    size = float(num_bytes or 0)
    for unit in ("B", "kB", "MB", "GB"):
        if size < 1024 or unit == "GB":
            if unit == "B":
                return f"{int(size)} {unit}"
            return f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} GB"


def chapter_label(volume: str, number: str, title: str = "") -> str:
    """Nhãn chương hiển thị: 'Chương 12', 'Tập 3 Chương 5', 'Oneshot'."""
    num = (number or "").strip()
    vol = (volume or "").strip()
    # Số chương là thông tin chính; tập chỉ hiện khi chương không có số.
    if num:
        label = f"Chương {num}"
    elif vol:
        label = f"Tập {vol}"
    else:
        label = "Oneshot"
    name = title.strip()
    # Truyện oneshot thường tự đặt tên là "oneshot": hi lại một lần cho gọn.
    if name.lower().replace(" ", "") in ("oneshot", "one-shot"):
        name = ""
    if name:
        label = f"{label} - {name}" if label else name
    return label
