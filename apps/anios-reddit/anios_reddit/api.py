"""Client Reddit Data API (chỉ đọc) cho AniOS Reddit.

Reddit yêu cầu OAuth cho mọi truy cập và từ chối/giới hạn yêu cầu không định danh
(xem wiki Data API của Reddit). App dùng luồng "installed client": người dùng tự tạo
một ứng dụng loại *installed app* trên reddit.com/prefs/apps, dán client ID vào, và
app đổi lấy access token chỉ-đọc mà không cần đăng nhập tài khoản.

Lớp này không phụ thuộc Qt nên có thể kiểm thử offline bằng transport giả.
"""
from __future__ import annotations

import base64
import html
import json
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from dataclasses import dataclass, field
from typing import Callable, Optional

API_BASE = "https://oauth.reddit.com"
TOKEN_URL = "https://www.reddit.com/api/v1/access_token"
INSTALLED_CLIENT_GRANT = "https://oauth.reddit.com/grants/installed_client"
APP_ID = "com.anios.reddit"
APP_VERSION = "0.1.0"

# Ứng dụng chỉ hiển thị một subreddit duy nhất.
FEED_SUBREDDIT = "unixporn"

SORTS = ("hot", "new", "top", "rising", "controversial")
TIME_RANGES = ("hour", "day", "week", "month", "year", "all")
COMMENT_SORTS = ("confidence", "top", "new", "controversial", "old", "qa")

# transport(method, url, headers, body) -> (status, body_text, response_headers)
Transport = Callable[[str, str, dict, Optional[bytes]], tuple]


class RedditError(Exception):
    """Lỗi có thông điệp hiển thị được cho người dùng."""

    def __init__(self, message: str, status: Optional[int] = None):
        super().__init__(message)
        self.status = status


def make_user_agent(contact: str = "") -> str:
    """User-Agent theo định dạng Reddit yêu cầu: <platform>:<appid>:<version> (by /u/<name>)."""
    who = contact.strip().lstrip("/").removeprefix("u/") or "anios-user"
    return f"linux:{APP_ID}:{APP_VERSION} (by /u/{who})"


def default_transport(method: str, url: str, headers: dict, body: Optional[bytes]) -> tuple:
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            return resp.status, resp.read().decode("utf-8", "replace"), dict(resp.headers)
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8", "replace"), dict(exc.headers or {})
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        raise RedditError(f"Không kết nối được Reddit: {exc}") from exc


# --------------------------------------------------------------------------- parsing

def _preview_url(data: dict) -> str:
    """Ảnh xem trước của bài viết (nếu có) — ưu tiên preview, rồi tới thumbnail thật."""
    images = (data.get("preview") or {}).get("images") or []
    if images:
        src = (images[0].get("source") or {}).get("url") or ""
        if src:
            return html.unescape(src)
    thumb = data.get("thumbnail") or ""
    return thumb if thumb.startswith("http") else ""


def parse_post(data: dict) -> dict:
    """Chuyển một `t3` thành dòng dữ liệu phẳng cho model."""
    permalink = data.get("permalink") or ""
    return {
        "id": data.get("id", ""),
        "fullname": data.get("name", ""),
        "title": data.get("title", ""),
        "author": data.get("author", "[đã xoá]"),
        "subreddit": data.get("subreddit", ""),
        "score": int(data.get("score") or 0),
        "numComments": int(data.get("num_comments") or 0),
        "created": float(data.get("created_utc") or 0.0),
        "permalink": "https://www.reddit.com" + permalink if permalink else "",
        "url": data.get("url_overridden_by_dest") or data.get("url") or "",
        "domain": data.get("domain", ""),
        "isSelf": bool(data.get("is_self")),
        "selftext": data.get("selftext", "") or "",
        "thumbnail": _preview_url(data),
        "flair": data.get("link_flair_text") or "",
        "nsfw": bool(data.get("over_18")),
        "stickied": bool(data.get("stickied")),
        "isVideo": bool(data.get("is_video")),
        "scoreText": compact_number(int(data.get("score") or 0)),
        "commentsText": compact_number(int(data.get("num_comments") or 0)),
        "ageText": relative_time(float(data.get("created_utc") or 0.0)),
    }


def parse_comments(children: list, max_depth: int = 8, limit: int = 300) -> list:
    """Duyệt cây bình luận (t1) theo thứ tự hiển thị và trả về danh sách phẳng có `depth`.

    Bỏ qua các mục `more` (Reddit cần endpoint riêng để nạp tiếp) và cắt ở `max_depth`.
    """
    out: list = []

    def walk(items: list, depth: int) -> None:
        for item in items:
            if len(out) >= limit:
                return
            if item.get("kind") != "t1":
                continue
            d = item.get("data", {})
            out.append({
                "id": d.get("id", ""),
                "author": d.get("author", "[đã xoá]"),
                "body": d.get("body", "") or "",
                "score": int(d.get("score") or 0),
                "created": float(d.get("created_utc") or 0.0),
                "depth": depth,
                "isOp": bool(d.get("is_submitter")),
            })
            replies = d.get("replies")
            if depth + 1 < max_depth and isinstance(replies, dict):
                walk(replies.get("data", {}).get("children", []), depth + 1)

    walk(children, 0)
    return out


@dataclass
class Page:
    posts: list = field(default_factory=list)
    after: Optional[str] = None


def parse_listing(payload: dict) -> Page:
    data = payload.get("data", {}) if isinstance(payload, dict) else {}
    posts = [parse_post(c.get("data", {})) for c in data.get("children", []) if c.get("kind") == "t3"]
    return Page(posts=posts, after=data.get("after") or None)


# --------------------------------------------------------------------------- formatting

def compact_number(n: int) -> str:
    if n < 1000:
        return str(n)
    if n < 1_000_000:
        v = f"{n / 1000:.1f}".rstrip("0").rstrip(".")
        return f"{v}k"
    v = f"{n / 1_000_000:.1f}".rstrip("0").rstrip(".")
    return f"{v}M"


def relative_time(created: float, now: Optional[float] = None) -> str:
    """Thời gian tương đối bằng tiếng Việt, ví dụ '5 phút trước'."""
    if not created:
        return ""
    delta = max(0, int((now if now is not None else time.time()) - created))
    units = (
        (365 * 86400, "năm"),
        (30 * 86400, "tháng"),
        (7 * 86400, "tuần"),
        (86400, "ngày"),
        (3600, "giờ"),
        (60, "phút"),
    )
    for seconds, label in units:
        if delta >= seconds:
            return f"{delta // seconds} {label} trước"
    return "vừa xong"


# --------------------------------------------------------------------------- client

class RedditClient:
    def __init__(
        self,
        client_id: str,
        *,
        contact: str = "",
        transport: Transport = default_transport,
        clock: Callable[[], float] = time.time,
        device_id: Optional[str] = None,
    ):
        if not client_id.strip():
            raise RedditError("Chưa có client ID của Reddit.")
        self.client_id = client_id.strip()
        self.user_agent = make_user_agent(contact)
        self._transport = transport
        self._clock = clock
        self._device_id = device_id or uuid.uuid4().hex[:30]
        self._token: Optional[str] = None
        self._token_expires = 0.0

    # -- auth
    def _ensure_token(self) -> str:
        if self._token and self._clock() < self._token_expires - 30:
            return self._token
        basic = base64.b64encode(f"{self.client_id}:".encode()).decode()
        body = urllib.parse.urlencode({"grant_type": INSTALLED_CLIENT_GRANT, "device_id": self._device_id}).encode()
        status, text, _ = self._transport(
            "POST", TOKEN_URL,
            {"Authorization": f"Basic {basic}", "User-Agent": self.user_agent,
             "Content-Type": "application/x-www-form-urlencoded"},
            body,
        )
        if status in (400, 401, 403):
            raise RedditError(
                "Reddit từ chối client ID. Kiểm tra lại client ID (loại app phải là 'installed app').", status)
        payload = _json_or_error(status, text, "xác thực với Reddit")
        token = payload.get("access_token")
        if not token:
            raise RedditError("Reddit không cấp token. Kiểm tra lại client ID (loại app phải là 'installed app').")
        self._token = token
        self._token_expires = self._clock() + int(payload.get("expires_in") or 3600)
        return token

    # -- requests
    def _get(self, path: str, params: dict) -> dict:
        query = {k: v for k, v in params.items() if v not in (None, "")}
        query.setdefault("raw_json", "1")
        url = f"{API_BASE}{path}?{urllib.parse.urlencode(query)}"
        headers = {"Authorization": f"bearer {self._ensure_token()}", "User-Agent": self.user_agent}
        status, text, resp_headers = self._transport("GET", url, headers, None)
        if status == 401:
            self._token = None  # token hết hạn: lần gọi sau sẽ xin lại
            raise RedditError("Phiên truy cập hết hạn, vui lòng thử lại.", status)
        if status == 429:
            reset = _header(resp_headers, "x-ratelimit-reset")
            wait = f" Thử lại sau khoảng {reset} giây." if reset else ""
            raise RedditError("Reddit đang giới hạn số yêu cầu." + wait, status)
        return _json_or_error(status, text, "tải dữ liệu từ Reddit")

    def listing(self, subreddit: str = FEED_SUBREDDIT, sort: str = "hot", after: Optional[str] = None,
                time_range: str = "day") -> Page:
        if sort not in SORTS:
            raise RedditError(f"Kiểu sắp xếp không hợp lệ: {sort}")
        name = subreddit.strip().removeprefix("r/").strip("/") or "all"
        params = {"limit": 25, "after": after}
        if sort == "top" or sort == "controversial":
            params["t"] = time_range if time_range in TIME_RANGES else "day"
        return parse_listing(self._get(f"/r/{name}/{sort}", params))

    def comments(self, post_id: str, sort: str = "confidence") -> list:
        if sort not in COMMENT_SORTS:
            sort = "confidence"
        payload = self._get(f"/comments/{post_id}", {"limit": 200, "sort": sort})
        if not isinstance(payload, list) or len(payload) < 2:
            raise RedditError("Phản hồi bình luận không đúng định dạng.")
        return parse_comments(payload[1].get("data", {}).get("children", []))


def _header(headers: dict, name: str) -> str:
    for key, value in (headers or {}).items():
        if key.lower() == name:
            return str(value)
    return ""


def _json_or_error(status: int, text: str, action: str) -> dict:
    if status >= 400:
        if status == 403:
            raise RedditError("Reddit từ chối yêu cầu (403). Có thể app chưa được cấp quyền hoặc client ID sai.", status)
        raise RedditError(f"Không thể {action} (HTTP {status}).", status)
    try:
        return json.loads(text)
    except json.JSONDecodeError as exc:
        raise RedditError(f"Phản hồi không phải JSON khi {action}.") from exc
