"""Kiểm thử nguồn MangaDex: phân tích cú pháp, phân trang, chọn ngôn ngữ, link ảnh."""
from __future__ import annotations

import pytest

from anios_manga.sources.mangadex import MangaDexSource


def make_source(fake, **kwargs):
    return MangaDexSource(transport=fake, **kwargs)


def test_popular_parses_first_page(fake):
    listing = make_source(fake).popular()
    assert len(listing.items) == 3
    assert listing.has_more is True
    first = listing.items[0]
    assert first.id.startswith("a1a1a1a1")
    # Người dùng Việt Nam nên tiêu đề tiếng Việt được ưu tiên hơn bản gốc.
    assert first.title == "Đảo Hải Tặc"
    assert first.author == "Eiichiro Oda"
    assert first.status == "ongoing"
    assert first.year == 1997
    assert "Adventure" in first.tags
    assert first.cover_url.endswith("/covers/a1a1a1a1-1111-4111-8111-111111111111/onepiece.jpg")
    assert first.cover_thumb.endswith(".256.jpg")
    assert "example.org" not in first.description  # link markdown đã bị bỏ


def test_popular_prefers_vietnamese_title(fake):
    listing = make_source(fake).popular()
    assert listing.items[2].title == "Thần Ấn Vương Toạ"


def test_pagination_walks_offsets(fake):
    source = make_source(fake)
    first = source.popular()
    second = source.popular(1)
    third = source.popular(2)
    assert [len(x.items) for x in (first, second, third)] == [3, 2, 1]
    assert third.has_more is False
    offsets = [c[1].split("offset=")[1].split("&")[0] for c in fake.calls if "offset=" in c[1]]
    assert offsets == ["0", "24", "48"]


def test_latest_and_search_use_different_orders(fake):
    source = make_source(fake)
    source.latest()
    source.search("one")
    latest_url = fake.requests_to("/manga")[0][1]
    search_url = fake.requests_to("/manga")[1][1]
    assert "order%5BlatestUploadedChapter%5D=desc" in latest_url
    assert "order%5Brelevance%5D=desc" in search_url
    assert "title=one" in search_url


def test_search_without_query_returns_nothing(fake):
    assert make_source(fake).search("   ").items == []
    assert fake.calls == []


def test_content_rating_depends_on_nsfw(fake):
    make_source(fake).popular()
    assert "contentRating=safe" in fake.calls[-1][1]
    assert "erotica" not in fake.calls[-1][1]
    make_source(fake, nsfw=True).popular()
    assert "contentRating=erotica" in fake.calls[-1][1]


def test_details_parses_relationships(fake):
    manga = make_source(fake).details("a1a1a1a1-1111-4111-8111-111111111111")
    assert manga.title == "Đảo Hải Tặc"
    assert manga.alt_title == "ワンピース"
    assert manga.author == "Eiichiro Oda"
    assert "\r\n" not in manga.description
    assert manga.url == "https://mangadex.org/title/a1a1a1a1-1111-4111-8111-111111111111"


def test_chapters_keep_preferred_language(fake):
    chapters = make_source(fake).chapters("manga-1", ["vi", "en"])
    ids = [ch.id for ch in chapters]
    # Chương 10 có cả bản vi và en: chỉ giữ bản tiếng Việt.
    assert "ch-010" in ids
    assert "ch-010-en" not in ids
    assert chapters[0].id == "ch-010"  # mới nhất trước


def test_chapters_are_sorted_newest_first_with_oneshots_last(fake):
    chapters = make_source(fake).chapters("manga-1", ["vi", "en"])
    labels = [(ch.volume, ch.number) for ch in chapters]
    assert labels == [("1", "10"), ("1", "9"), ("", "5.5"), ("", "")]


def test_chapters_parse_pages_and_language(fake):
    chapters = make_source(fake).chapters("manga-1", ["vi", "en"])
    chapter = chapters[0]
    assert chapter.pages == 18
    assert chapter.language == "vi"
    assert chapter.title == "Cuộc chiến"
    assert chapter.published_at.startswith("2024-03-01")


def test_page_urls_use_at_home_server(fake):
    source = make_source(fake)
    chapters = source.chapters("manga-1", ["vi", "en"])
    urls = source.page_urls(chapters[0])
    assert urls == [
        "https://cdn.example/data/abc123/1.png",
        "https://cdn.example/data/abc123/2.png",
        "https://cdn.example/data/abc123/3.png",
    ]


def test_page_urls_honour_data_saver(fake):
    source = make_source(fake)
    chapters = source.chapters("manga-1", ["vi", "en"])
    urls = source.page_urls(chapters[0], data_saver=True)
    assert urls == ["https://cdn.example/data-saver/abc123/s.png"]


def test_tags_are_sorted_and_labelled(fake):
    tags = make_source(fake).tags()
    # Sắp theo nhóm rồi tới tên: format < genre < theme.
    assert [t["id"] for t in tags] == ["tag-longstrip", "tag-action", "tag-adventure", "tag-romance"]
    assert tags[0]["name"] == "Long Strip"  # nhóm "format" đứng trước "genre"


def test_error_payload_becomes_manga_error(fake):
    fake.fail["/manga/"] = (500, "MangaDex đang quá tải")
    with pytest.raises(Exception) as exc:
        make_source(fake).details("x")
    assert "500" in str(exc.value) or "quá tải" in str(exc.value)


def test_source_without_transport_uses_urllib(monkeypatch):
    """Chạy thật không truyền transport: nguồn phải tự dùng urllib, không được sập.

    Lỗi này từng xảy ra: `transport=None` được giữ nguyên rồi gọi như hàm nên
    mọi thao tác mạng đều chết với "'NoneType' object is not callable".
    """
    import json as _json

    import anios_manga.http as http
    from anios_manga.http import default_transport

    seen = []

    class FakeResponse:
        status = 200
        headers = {"Content-Type": "application/json"}

        def read(self):
            return _json.dumps({"result": "ok", "data": [], "total": 0}).encode()

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return False

    def fake_urlopen(request, timeout=None):
        seen.append(request.full_url)
        return FakeResponse()

    monkeypatch.setattr(http.urllib.request, "urlopen", fake_urlopen)

    source = MangaDexSource()  # không truyền transport, đúng như app thật
    assert source._transport is default_transport
    listing = source.popular()
    assert listing.items == []
    assert seen and seen[0].startswith("https://api.mangadex.org/manga?")
