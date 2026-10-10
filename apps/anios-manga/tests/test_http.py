"""Kiểm thử tầng HTTP: ghép URL, ánh xạ lỗi, thử lại và tải ảnh nhị phân."""
from __future__ import annotations

import json

import pytest

from anios_manga.http import (
    MangaError,
    build_url,
    default_bytes_transport,
    request_bytes,
    request_json,
)


def test_build_url_repeats_list_params():
    url = build_url("https://api.example/", "/manga", {"limit": 5, "translatedLanguage": ["vi", "en"]})
    assert url == "https://api.example/manga?limit=5&translatedLanguage=vi&translatedLanguage=en"


def test_build_url_drops_empty_values():
    url = build_url("https://api.example", "/manga", {"title": "", "limit": None, "x": 0})
    assert url == "https://api.example/manga?x=0"


def test_request_json_returns_payload():
    def transport(method, url, headers, body):
        return 200, json.dumps({"result": "ok"}), {}

    assert request_json("https://api.example/x", transport=transport) == {"result": "ok"}


def test_request_json_maps_http_errors_to_vietnamese():
    def transport(method, url, headers, body):
        return 404, "{}", {}

    with pytest.raises(MangaError) as exc:
        request_json("https://api.example/x", transport=transport)
    assert "404" in str(exc.value)


def test_request_json_uses_mangadex_error_detail():
    payload = {"result": "error", "errors": [{"detail": "Chapter not found"}]}

    def transport(method, url, headers, body):
        return 404, json.dumps(payload), {}

    with pytest.raises(MangaError) as exc:
        request_json("https://api.example/x", transport=transport)
    assert "404" in str(exc.value)


def test_request_json_retries_on_rate_limit():
    calls = {"n": 0}

    def transport(method, url, headers, body):
        calls["n"] += 1
        if calls["n"] == 1:
            return 429, "{}", {"retry-after": "1"}
        return 200, json.dumps({"ok": True}), {}

    slept = []
    payload = request_json(
        "https://api.example/x", transport=transport, sleep=slept.append
    )
    assert payload == {"ok": True}
    assert calls["n"] == 2
    assert slept == [1.0]


def test_request_json_raises_after_retries_exhausted():
    def transport(method, url, headers, body):
        return 503, "{}", {}

    with pytest.raises(MangaError):
        request_json("https://api.example/x", transport=transport, sleep=lambda s: None, retries=2)


def test_request_json_rejects_non_json():
    def transport(method, url, headers, body):
        return 200, "<html>oops</html>", {}

    with pytest.raises(MangaError):
        request_json("https://api.example/x", transport=transport)


def test_request_json_wraps_network_failure():
    def transport(method, url, headers, body):
        raise MangaError("Không kết nối được tới máy chủ: mất mạng")

    with pytest.raises(MangaError) as exc:
        request_json("https://api.example/x", transport=transport)
    assert "Không kết nối" in str(exc.value)


def test_request_bytes_round_trips_binary_data(fake):
    from conftest import PNG_BYTES

    data = request_bytes("https://cdn.example/1.png", transport=fake)
    assert isinstance(data, bytes)
    assert data == PNG_BYTES


def test_default_bytes_transport_keeps_every_byte():
    """Transport ảnh phải khép kín từng byte (không dùng errors='replace')."""
    from conftest import PNG_BYTES

    raw = b"\x89PNG\r\n\x1a\n\xff\xfe binary \x00\x01"

    def transport(method, url, headers, body):
        return 200, raw.decode("utf-8", "surrogateescape"), {}

    data = request_bytes("https://cdn.example/x.png", transport=transport)
    assert data == raw
    assert data != PNG_BYTES  # fixture khác, chỉ để chắc dữ liệu không bị trộn
