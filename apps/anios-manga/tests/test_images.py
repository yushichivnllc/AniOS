"""Kiểm thử nhà cung cấp ảnh: cache ra đĩa, tải khi trượt, đọc file cục bộ."""
from __future__ import annotations

from pathlib import Path

from anios_manga.http import MangaError
from anios_manga.images import MangaImageProvider, image_url


def test_image_url_accepts_plain_and_encoded_ids():
    assert image_url("https://x/1.png") == "https://x/1.png"
    assert image_url("file:///tmp/a.png") == "file:///tmp/a.png"
    # Qt có thể giải mã percent-encoding trước khi đưa vào provider.
    assert image_url("https%3A%2F%2Fx%2F1.png") == "https://x/1.png"


def test_provider_caches_downloaded_image(fake, tmp_path):
    provider = MangaImageProvider(tmp_path / "cache", transport=fake)
    data = provider.load("https://cdn.example/1.png")
    assert data.startswith(b"\x89PNG")
    cached = list((tmp_path / "cache").iterdir())
    assert len(cached) == 1
    # Lần hai đọc từ cache, không tải lại.
    calls = len(fake.calls)
    assert provider.load("https://cdn.example/1.png") == data
    assert len(fake.calls) == calls


def test_provider_reads_local_files(tmp_path):
    image = tmp_path / "1.png"
    image.write_bytes(b"\x89PNG local file")
    provider = MangaImageProvider(tmp_path / "cache")
    assert provider.load(image.as_uri()) == b"\x89PNG local file"


def test_provider_raises_on_http_error(tmp_path):
    def transport(method, url, headers, body):
        return 404, "{}", {}

    provider = MangaImageProvider(tmp_path / "cache", transport=transport)
    try:
        provider.load("https://cdn.example/thieu.png")
    except MangaError as exc:
        assert "404" in str(exc)
    else:  # pragma: no cover - pytest.raises sẽ bắt, nhánh này chỉ là lưới an toàn
        raise AssertionError("phải ném MangaError")


def test_image_type_is_image(tmp_path):
    from PySide6.QtQuick import QQuickAsyncImageProvider

    provider = MangaImageProvider(tmp_path / "cache")
    assert provider.imageType() == QQuickAsyncImageProvider.ImageType.Image


def test_provider_reads_local_files_with_spaces_and_diacritics(tmp_path):
    # Thư mục CBZ/ảnh trên Linux thường có khoảng trắng và dấu tiếng Việt;
    # as_uri() mã hoá chúng thành %20, %E1%BB%87... và provider phải giải mã lại.
    folder = tmp_path / "Truyện tranh mới"
    folder.mkdir()
    image = folder / "trang 01.png"
    image.write_bytes(b"\x89PNG diacritics")
    provider = MangaImageProvider(tmp_path / "cache")
    from urllib.parse import quote, unquote

    # Dạng QML gửi qua image://manga/ (đã mã hoá một lần) và dạng Qt đã giải mã.
    assert provider.load(image.as_uri()) == b"\x89PNG diacritics"
    assert provider.load(quote(image.as_uri(), safe="")) == b"\x89PNG diacritics"
    assert provider.load(unquote(quote(image.as_uri(), safe=""))) == b"\x89PNG diacritics"
