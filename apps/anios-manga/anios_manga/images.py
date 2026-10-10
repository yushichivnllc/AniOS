"""Nhà cung cấp ảnh cho QML (`image://manga/<url>`).

Vì sao không để QML tự tải ảnh bằng `Image { source: "https://..." }`:
  * cần gửi kèm User-Agent (MangaDex từ chối yêu cầu không định danh);
  * cần cache ra đĩa để lưới ảnh bìa không tải lại mỗi lần mở app;
  * truyện đã tải về phải đọc từ đĩa, không đi mạng;
  * tải phải chạy ở luồng nền, không được đơ giao diện.

`QQuickAsyncImageProvider` cho phép làm cả ba: mỗi ảnh là một
`MangaImageResponse` chạy trong thread pool của Qt.
"""
from __future__ import annotations

import hashlib
import threading
from pathlib import Path
from typing import Optional

from PySide6.QtCore import QByteArray
from PySide6.QtGui import QImage
from PySide6.QtQuick import QQuickAsyncImageProvider, QQuickImageResponse, QQuickTextureFactory

from .http import MangaError, default_bytes_transport, request_bytes

IMAGE_PROVIDER_ID = "manga"


def image_url(image_id: str) -> str:
    """Chuẩn hoá id Qt đưa sang: Qt có thể giải mã percent-encoding nên thử cả hai dạng."""
    candidate = image_id or ""
    if candidate.startswith(("http://", "https://", "file://")):
        return candidate
    from urllib.parse import unquote

    decoded = unquote(candidate)
    return decoded if decoded.startswith(("http://", "https://", "file://")) else candidate


class MangaImageProvider(QQuickAsyncImageProvider):
    def __init__(self, cache_dir: Path, transport=default_bytes_transport):
        super().__init__()
        self.cache_dir = Path(cache_dir)
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self._transport = transport
        self._lock = threading.Lock()

    def imageType(self) -> QQuickAsyncImageProvider.ImageType:  # noqa: N802
        return QQuickAsyncImageProvider.ImageType.Image

    def requestImageResponse(self, image_id: str, requested_size) -> QQuickImageResponse:  # noqa: N802
        return MangaImageResponse(self, image_id, requested_size)

    # ---------------------------------------------------------------- nạp ảnh
    def load(self, image_id: str) -> bytes:
        """Trả về byte ảnh: đọc từ đĩa nếu có, không thì tải về rồi ghi cache."""
        url = image_url(image_id)
        if url.startswith("file://"):
            return Path(url[len("file://"):]).read_bytes()
        cached = self._cache_path(url)
        if cached.is_file():
            return cached.read_bytes()
        data = request_bytes(url, transport=self._transport, action="tải ảnh")
        self._store(cached, data)
        return data

    def _cache_path(self, url: str) -> Path:
        digest = hashlib.sha1(url.encode("utf-8")).hexdigest()
        return self.cache_dir / digest

    def _store(self, path: Path, data: bytes) -> None:
        with self._lock:
            if path.is_file():
                return
            tmp = path.with_suffix(".part")
            tmp.write_bytes(data)
            tmp.replace(path)


class MangaImageResponse(QQuickImageResponse):
    def __init__(self, provider: MangaImageProvider, image_id: str, requested_size):
        super().__init__()
        self._provider = provider
        self._image_id = image_id
        self._requested_size = requested_size
        self._image = QImage()
        self._error = ""

    def run(self) -> None:
        try:
            data = self._provider.load(self._image_id)
            image = QImage.fromData(QByteArray(data))
            if image.isNull():
                self._error = "Ảnh không đọc được."
            else:
                self._image = image
        except MangaError as exc:
            self._error = str(exc)
        except OSError as exc:
            self._error = f"Không đọc được ảnh: {exc}"
        self.finished.emit()

    def textureFactory(self) -> Optional[QQuickTextureFactory]:  # noqa: N802
        if self._image.isNull():
            return None
        return QQuickTextureFactory.textureFactoryForImage(self._image)

    def errorString(self) -> str:  # noqa: N802
        return self._error
