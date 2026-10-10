"""Tầng HTTP dùng chung, chỉ dựa vào thư viện chuẩn (urllib).

Mọi nguồn truyện đi qua `request_json`/`request_bytes` để lỗi mạng, lỗi HTTP và
phản hồi hỏng đều quy về MỘT kiểu `MangaError` có thông điệp tiếng Việt — giao diện
và backend chỉ cần bắt một ngoại lệ duy nhất.

`transport(method, url, headers, body) -> (status, body_text, response_headers)` có thể
thay bằng bản giả để kiểm thử offline, đúng kiểu apps/anios-reddit đang dùng. Với dữ
liệu nhị phân (ảnh) phải dùng `default_bytes_transport`: nó giải mã bằng
`surrogateescape` nên encode ngược trả lại ĐÚNG từng byte, còn `default_transport`
dùng `errors="replace"` sẽ làm hỏng ảnh.
"""
from __future__ import annotations

import json
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Callable, Optional

USER_AGENT = "AniOSManga/0.1.0 (Linux x86_64) PySide6"

# transport(method, url, headers, body) -> (status, body_text, response_headers)
Transport = Callable[[str, str, dict, Optional[bytes]], tuple]


class MangaError(Exception):
    """Lỗi có thông điệp hiển thị được cho người dùng."""

    def __init__(self, message: str, status: Optional[int] = None):
        super().__init__(message)
        self.status = status


def build_url(base: str, path: str, params: Optional[dict] = None) -> str:
    """Ghép URL; giá trị dạng list được lặp lại thành nhiều tham số (MangaDex cần cách này)."""
    url = base.rstrip("/") + "/" + path.lstrip("/") if base else path
    if not params:
        return url
    query: list[tuple[str, str]] = []
    for key, value in params.items():
        if value in (None, ""):
            continue
        if isinstance(value, (list, tuple)):
            query.extend((key, str(v)) for v in value if v not in (None, ""))
        else:
            query.append((key, str(value)))
    return f"{url}?{urllib.parse.urlencode(query)}" if query else url


def _headers(extra: Optional[dict] = None) -> dict:
    headers = {"User-Agent": USER_AGENT, "Accept": "*/*"}
    if extra:
        headers.update(extra)
    return headers


def default_transport(method: str, url: str, headers: dict, body: Optional[bytes]) -> tuple:
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=25) as resp:
            return resp.status, resp.read().decode("utf-8", "replace"), dict(resp.headers)
    except urllib.error.HTTPError as exc:
        return exc.code, _read_error(exc), dict(exc.headers or {})
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        raise MangaError(f"Không kết nối được tới máy chủ: {exc}") from exc


def default_bytes_transport(method: str, url: str, headers: dict, body: Optional[bytes]) -> tuple:
    """Như `default_transport` nhưng giữ nguyên byte của ảnh (surrogateescape khép kín)."""
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=25) as resp:
            raw = resp.read()
            return resp.status, raw.decode("utf-8", "surrogateescape"), dict(resp.headers)
    except urllib.error.HTTPError as exc:
        return exc.code, _read_error(exc), dict(exc.headers or {})
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        raise MangaError(f"Không tải được ảnh: {exc}") from exc


def _read_error(exc: urllib.error.HTTPError) -> str:
    try:
        return exc.read().decode("utf-8", "replace")
    except Exception:  # noqa: BLE001 - thân phản hồi lỗi không đọc được thì bỏ qua
        return ""


def request_json(
    url: str,
    *,
    params: Optional[dict] = None,
    headers: Optional[dict] = None,
    transport: Transport = default_transport,
    action: str = "tải dữ liệu",
    retries: int = 2,
    sleep: Callable[[float], None] = time.sleep,
) -> dict:
    """GET một JSON; tự thử lại khi bị giới hạn tần suất (429) hoặc máy chủ lỗi (5xx)."""
    full_url = build_url("", url, params) if params else url
    last_error: Optional[MangaError] = None
    attempts = max(1, retries)
    for attempt in range(attempts):
        try:
            status, text, resp_headers = transport("GET", full_url, _headers(headers), None)
        except MangaError:
            raise
        if status >= 400:
            last_error = MangaError(_http_message(status, text, action), status)
            retryable = status == 429 or status in (500, 502, 503, 504)
            if retryable and attempt + 1 < attempts:
                if status == 429:
                    sleep(min(5.0, max(1.0, _as_float(_header(resp_headers, "retry-after"), 1.5))))
                else:
                    sleep(1.0)
                continue
            raise last_error
        try:
            return json.loads(text)
        except json.JSONDecodeError as exc:
            raise MangaError(f"Phản hồi không phải JSON khi {action}.") from exc
    raise last_error or MangaError(f"Không thể {action}.")


def request_bytes(
    url: str,
    *,
    headers: Optional[dict] = None,
    transport: Transport = default_bytes_transport,
    action: str = "tải ảnh",
    retries: int = 3,
) -> bytes:
    """GET nội dung nhị phân (ảnh trang, ảnh bìa)."""
    last_error: Optional[MangaError] = None
    attempts = max(1, retries)
    for attempt in range(attempts):
        try:
            status, text, _headers_resp = transport("GET", url, _headers(headers), None)
        except MangaError:
            raise
        if status >= 400:
            last_error = MangaError(_http_message(status, text, action), status)
            if attempt + 1 < attempts:
                continue
            raise last_error
        return text.encode("utf-8", "surrogateescape")
    raise last_error or MangaError(f"Không thể {action}.")


def _as_float(value: str, fallback: float) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return fallback


def _http_message(status: int, text: str, action: str) -> str:
    """Thông điệp lỗi thân thiện; MangaDex đính kèm `errors[0].detail` nên tận dụng."""
    detail = ""
    try:
        payload = json.loads(text)
        errors = payload.get("errors") or []
        if errors and isinstance(errors, list):
            detail = str(errors[0].get("detail") or errors[0].get("title") or "")
    except (json.JSONDecodeError, AttributeError, IndexError, TypeError):
        detail = ""
    if status == 404:
        return "Không tìm thấy nội dung (404)."
    if status == 403:
        return "Máy chủ từ chối yêu cầu (403). Thử đổi nguồn hoặc bật/tắt bộ lọc 18+."
    if status == 429:
        return "Đang bị giới hạn số yêu cầu (429). Chờ một chút rồi thử lại."
    message = f"Không thể {action} (HTTP {status})."
    return f"{message} {detail}".strip()


def _header(headers: dict, name: str) -> str:
    for key, value in (headers or {}).items():
        if key.lower() == name:
            return str(value)
    return ""
