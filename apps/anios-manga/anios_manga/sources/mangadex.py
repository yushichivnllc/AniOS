"""Nguồn truyện MangaDex (https://api.mangadex.org).

Chọn MangaDex làm nguồn chính vì:
  * API JSON công khai, không cần đăng ký, không cần khoá;
  * có bản dịch tiếng Việt của phần lớn truyện phổ biến;
  * ảnh được phục vụ qua mạng CDN riêng (`/at-home/server/...`) nên app tự lấy được
    link ảnh chứ không phải parse HTML.

Tài liệu: https://api.mangadex.org/docs/
"""
from __future__ import annotations

import re
from typing import List, Optional

from ..http import MangaError, build_url, default_transport, request_json
from .base import Chapter, Listing, Manga, MangaSource

API = "https://api.mangadex.org"
COVERS = "https://uploads.mangadex.org/covers"
PAGE_SIZE = 24
MAX_CHAPTERS = 1000 # chặn vòng lặp phân trang nếu máy chủ trả total vô nghĩa

# Ngôn ngữ luôn được phép hiển thị kể cả khi người dùng không chọn.
FALLBACK_LANGUAGES = ("en", "vi")


class MangaDexSource(MangaSource):
    id = "mangadex"
    name = "MangaDex"
    offline = False

    def __init__(self, *, nsfw: bool = False, languages: Optional[List[str]] = None,
                 data_saver: bool = False, transport=None):
        self.nsfw = nsfw
        self.languages = list(languages) if languages else list(FALLBACK_LANGUAGES)
        self.data_saver = data_saver
        # Không truyền transport (chạy thật) thì dùng urllib; kiểm thử mới truyền bản giả.
        self._transport = transport or default_transport

    # ------------------------------------------------------------------ tiện ích
    def _get(self, path: str, params: Optional[dict] = None, action: str = "tải dữ liệu") -> dict:
        url = build_url(API, path, params)
        payload = request_json(url, transport=self._transport, action=action)
        if payload.get("result") not in (None, "ok"):
            raise MangaError("MangaDex trả về lỗi, thử lại sau.")
        return payload

    def _content_rating(self) -> List[str]:
        ratings = ["safe", "suggestive"]
        if self.nsfw:
            ratings += ["erotica", "pornographic"]
        return ratings

    def _langs(self) -> List[str]:
        langs = [x for x in self.languages if x]
        return langs or list(FALLBACK_LANGUAGES)

    # ------------------------------------------------------------------ duyệt/tìm
    def _listing(self, params: dict, page: int, action: str) -> Listing:
        params = dict(params)
        params.setdefault("limit", PAGE_SIZE)
        params["offset"] = max(0, page) * PAGE_SIZE
        params["includes"] = ["cover_art"]
        params["contentRating"] = self._content_rating()
        payload = self._get("/manga", params, action=action)
        data = payload.get("data") or []
        items = [self._to_manga(item) for item in data if isinstance(item, dict)]
        total = int(payload.get("total") or 0)
        offset = int(payload.get("offset") or 0)
        return Listing(items=items, has_more=offset + len(data) < total)

    def popular(self, page: int = 0) -> Listing:
        return self._listing(
            {"order[followedCount]": "desc", "hasAvailableChapters": "true"}, page, "tải truyện nổi bật")

    def latest(self, page: int = 0) -> Listing:
        return self._listing(
            {"order[latestUploadedChapter]": "desc", "hasAvailableChapters": "true"},
            page, "tải truyện mới nhất")

    def search(self, query: str, page: int = 0) -> Listing:
        query = (query or "").strip()
        if not query:
            return Listing()
        return self._listing(
            {"title": query, "order[relevance]": "desc", "hasAvailableChapters": "true"},
            page, "tìm truyện")

    # ------------------------------------------------------------------ chi tiết
    def details(self, manga_id: str) -> Manga:
        payload = self._get(
            f"/manga/{manga_id}",
            {"includes": ["cover_art", "author", "artist"]},
            action="tải thông tin truyện",
        )
        item = payload.get("data") or {}
        if not item:
            raise MangaError("Không tìm thấy truyện này trên MangaDex.")
        return self._to_manga(item)

    def chapters(self, manga_id: str, languages: Optional[List[str]] = None) -> List[Chapter]:
        langs = [x for x in (languages or self._langs()) if x]
        params = {
            "limit": 500,
            "offset": 0,
            "translatedLanguage": langs,
            "includeEmptyPages": 0,
            "includeExternalUrl": 0,
        }
        collected: List[Chapter] = []
        while True:
            payload = self._get(f"/manga/{manga_id}/feed", params, action="tải danh sách chương")
            data = payload.get("data") or []
            collected.extend(self._to_chapter(item) for item in data if isinstance(item, dict))
            total = int(payload.get("total") or 0)
            params["offset"] += len(data)
            if len(data) < 500 or params["offset"] >= total or len(collected) >= MAX_CHAPTERS:
                break
        # Một chương có thể có nhiều bản dịch: giữ bản của ngôn ngữ ưu tiên nhất.
        return _dedupe_by_language(collected, langs)

    def tags(self) -> List[dict]:
        payload = self._get("/manga/tag", action="tải thể loại")
        out: List[dict] = []
        for item in payload.get("data") or []:
            attrs = item.get("attributes") or {}
            name = (attrs.get("name") or {}).get("en") or ""
            if item.get("id") and name:
                out.append({"id": item["id"], "name": name, "group": attrs.get("group", "")})
        out.sort(key=lambda t: (t.get("group", ""), t["name"]))
        return out

    # ------------------------------------------------------------------ ảnh
    def page_urls(self, chapter: Chapter, *, data_saver: bool = False) -> List[str]:
        payload = self._get(f"/at-home/server/{chapter.id}", action="lấy địa chỉ ảnh")
        base = payload.get("baseUrl") or ""
        info = payload.get("chapter") or {}
        digest = info.get("hash") or ""
        files = info.get("dataSaver") if data_saver else info.get("data")
        if not files:
            files = info.get("data") or []
        if not (base and digest and files):
            raise MangaError("Chương này chưa có ảnh để đọc (có thể đã bị gỡ).")
        folder = "data-saver" if data_saver else "data"
        return [f"{base}/{folder}/{digest}/{name}" for name in files]

    def manga_url(self, manga_id: str) -> str:
        return f"https://mangadex.org/title/{manga_id}"

    # ------------------------------------------------------------------ chuyển đổi
    def _to_manga(self, item: dict) -> Manga:
        attrs = item.get("attributes") or {}
        rels = item.get("relationships") or []
        cover = ""
        author = artist = ""
        for rel in rels:
            if not isinstance(rel, dict):
                continue
            kind = rel.get("type")
            rattrs = rel.get("attributes") or {}
            if kind == "cover_art":
                cover = rattrs.get("fileName") or ""
            elif kind == "author" and not author:
                author = rattrs.get("name") or ""
            elif kind == "artist" and not artist:
                artist = rattrs.get("name") or ""
        manga_id = item.get("id") or ""
        title = _pick_lang(attrs.get("title")) or "Không tên"
        alt = _first_alt(attrs.get("altTitles"))
        cover_url = f"{COVERS}/{manga_id}/{cover}" if cover else ""
        cover_thumb = f"{cover_url}.256.jpg" if cover else ""
        tags = []
        for tag in attrs.get("tags") or []:
            if not isinstance(tag, dict):
                continue
            name = (tag.get("attributes") or {}).get("name") or {}
            label = name.get("en") or name.get("vi") or ""
            if label:
                tags.append(label)
        year = attrs.get("year")
        return Manga(
            source=self.id,
            id=manga_id,
            title=title,
            cover_url=cover_url,
            cover_thumb=cover_thumb,
            description=_clean_text(attrs.get("description")),
            author=author,
            artist=artist,
            status=attrs.get("status") or "",
            tags=tags,
            year=int(year) if isinstance(year, int) else None,
            url=self.manga_url(manga_id),
            alt_title=alt,
            nsfw=(attrs.get("contentRating") or "") in ("erotica", "pornographic"),
        )

    def _to_chapter(self, item: dict) -> Chapter:
        attrs = item.get("attributes") or {}
        chapter_id = item.get("id") or ""
        number = attrs.get("chapter")
        number = str(number).strip() if number not in (None, "") else ""
        volume = attrs.get("volume")
        volume = str(volume).strip() if volume not in (None, "") else ""
        pages = attrs.get("pages")
        return Chapter(
            id=chapter_id,
            number=number,
            volume=volume,
            title=(attrs.get("title") or "").strip(),
            language=(attrs.get("translatedLanguage") or "").strip(),
            pages=int(pages) if isinstance(pages, int) else 0,
            published_at=(attrs.get("publishAt") or attrs.get("readableAt") or "").strip(),
            external=bool(attrs.get("externalUrl")),
        )


# --------------------------------------------------------------------------- helper

def _pick_lang(values) -> str:
    """Chọn chuỗi theo thứ tự ưu tiên vi → en → ngôn ngữ đầu tiên có."""
    if isinstance(values, dict):
        for lang in ("vi", "en"):
            if values.get(lang):
                return str(values[lang]).strip()
        for value in values.values():
            if value:
                return str(value).strip()
    if isinstance(values, str):
        return values.strip()
    return ""


def _first_alt(alt_titles) -> str:
    if isinstance(alt_titles, list):
        for entry in alt_titles:
            if isinstance(entry, dict):
                for lang in ("vi", "en"):
                    if entry.get(lang):
                        return str(entry[lang]).strip()
                for value in entry.values():
                    if value:
                        return str(value).strip()
    return ""


_MD_LINK = re.compile(r"\[([^\]]*)\]\([^)]*\)")


def _clean_text(value) -> str:
    """MangaDex trả description kiểu Markdown rút gọn; bỏ link và xuống dòng Windows."""
    if not isinstance(value, dict):
        return _clean_text({"": value}) if isinstance(value, str) else ""
    text = _pick_lang(value)
    if not text:
        return ""
    text = _MD_LINK.sub(r"\1", text)
    return text.replace("\r\n", "\n").strip()


def _num(value: str) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return -1.0


def _chapter_sort_key(chapter: Chapter):
    # Oneshot không có số -> -1 nên rơi xuống cuối khi sắp xếp giảm dần.
    return (_num(chapter.volume), _num(chapter.number), chapter.published_at)


def _dedupe_key(chapter: Chapter):
    """Chương được định danh bằng (tập, số). Oneshot không có số nên dùng tiêu đề."""
    if chapter.number:
        return (chapter.volume, chapter.number)
    return ("oneshot", chapter.title.strip().lower())


def _dedupe_by_language(chapters: List[Chapter], languages: List[str]) -> List[Chapter]:
    """Giữ lại một bản dịch cho mỗi chương: bản của ngôn ngữ ưu tiên nhất."""
    rank = {lang: i for i, lang in enumerate(languages)}
    best: dict = {}
    for chapter in chapters:
        key = _dedupe_key(chapter)
        priority = rank.get(chapter.language, len(rank))
        current = best.get(key)
        if current is None or priority < current[0]:
            best[key] = (priority, chapter)
    ordered = [chapter for _, chapter in best.values()]
    ordered.sort(key=_chapter_sort_key, reverse=True)
    return ordered
