"""Kiểm thử bộ tải xuống: đặt tên file, meta.json, tải lại tiếp tục, đọc từ đĩa."""
from __future__ import annotations

from pathlib import Path

from anios_manga.downloader import download_chapter, downloaded_pages, read_meta
from anios_manga.paths import chapter_dir
from anios_manga.sources.mangadex import MangaDexSource


def test_download_chapter_writes_numbered_files(fake, settings):
    source = MangaDexSource(transport=fake)
    chapter = source.chapters("m1", ["vi"])[0]
    info = download_chapter(
        source=source,
        manga_id="m1",
        manga_title="One Piece",
        chapter=chapter,
        settings=settings,
        transport=fake,
    )

    dest = chapter_dir(settings, "mangadex", "m1", chapter.id)
    assert Path(info["path"]) == dest
    names = sorted(p.name for p in dest.iterdir())
    assert names == ["0001.png", "0002.png", "0003.png", "meta.json"]
    assert info["pages"] == 3
    assert info["size"] > 0
    assert info["size_text"].endswith(("B", "kB", "MB"))


def test_download_records_meta(fake, settings):
    source = MangaDexSource(transport=fake)
    chapter = source.chapters("m1", ["vi"])[0]
    download_chapter(source=source, manga_id="m1", manga_title="One Piece", chapter=chapter,
                     settings=settings, transport=fake)
    meta = read_meta(chapter_dir(settings, "mangadex", "m1", chapter.id))
    assert meta["source"] == "mangadex"
    assert meta["manga_id"] == "m1"
    assert meta["manga_title"] == "One Piece"
    assert meta["pages"] == 3


def test_download_skips_existing_files(fake, settings):
    source = MangaDexSource(transport=fake)
    chapter = source.chapters("m1", ["vi"])[0]
    download_chapter(source=source, manga_id="m1", manga_title="T", chapter=chapter,
                     settings=settings, transport=fake)
    before = len(fake.requests_to("cdn.example"))

    # Xoá một trang rồi tải lại: chỉ tải lại đúng trang thiếu.
    dest = chapter_dir(settings, "mangadex", "m1", chapter.id)
    (dest / "0002.png").unlink()
    download_chapter(source=source, manga_id="m1", manga_title="T", chapter=chapter,
                     settings=settings, transport=fake)
    after = len(fake.requests_to("cdn.example"))
    assert after - before == 1
    assert (dest / "0002.png").is_file()


def test_progress_callback_reports_every_page(fake, settings):
    source = MangaDexSource(transport=fake)
    chapter = source.chapters("m1", ["vi"])[0]
    seen = []
    download_chapter(source=source, manga_id="m1", manga_title="T", chapter=chapter,
                     settings=settings, transport=fake,
                     progress=lambda done, total: seen.append((done, total)))
    assert seen == [(1, 3), (2, 3), (3, 3)]


def test_downloaded_pages_reads_directory_in_order(fake, settings):
    source = MangaDexSource(transport=fake)
    chapter = source.chapters("m1", ["vi"])[0]
    download_chapter(source=source, manga_id="m1", manga_title="T", chapter=chapter,
                     settings=settings, transport=fake)
    urls = downloaded_pages(chapter_dir(settings, "mangadex", "m1", chapter.id))
    assert [Path(u).name for u in urls] == ["0001.png", "0002.png", "0003.png"]
    assert all(u.startswith("file://") for u in urls)


def test_downloaded_pages_returns_empty_for_missing_dir(tmp_path):
    assert downloaded_pages(tmp_path / "khong-co") == []


def test_data_saver_downloads_smaller_files(fake, settings):
    settings.data_saver = True
    source = MangaDexSource(transport=fake, data_saver=True)
    chapter = source.chapters("m1", ["vi"])[0]
    download_chapter(source=source, manga_id="m1", manga_title="T", chapter=chapter,
                     settings=settings, transport=fake)
    assert fake.requests_to("data-saver")
    assert not fake.requests_to("/data/")


def test_chapter_dir_is_safe_for_weird_ids(settings):
    path = chapter_dir(settings, "mangadex", "../lạ/../id", "ch 01/02")
    assert path.is_relative_to(settings.data_path / "downloads")
    assert ".." not in path.parts
    assert "/" not in path.name


def test_download_without_transport_falls_back_to_bytes_transport(monkeypatch, settings, fake):
    """Tải xuống khi chạy thật (transport=None) phải dùng bản giữ nguyên byte ảnh."""
    import anios_manga.http as http
    from conftest import PNG_BYTES

    # Danh sách ảnh lấy từ transport giả; chỉ riêng việc tải byte là chạy thật.
    source = MangaDexSource(transport=fake)
    chapter = source.chapters("m1", ["vi"])[0]
    seen = []

    class FakeResponse:
        status = 200
        headers = {"Content-Type": "image/png"}

        def read(self):
            return PNG_BYTES

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return False

    def fake_urlopen(request, timeout=None):
        seen.append(request.full_url)
        return FakeResponse()

    monkeypatch.setattr(http.urllib.request, "urlopen", fake_urlopen)
    info = download_chapter(
        source=source,
        manga_id="m1",
        manga_title="One Piece",
        chapter=chapter,
        settings=settings,
        transport=None,
    )
    assert info["pages"] == 3
    assert len(seen) == 3
    dest = Path(info["path"])
    assert (dest / "0001.png").read_bytes() == PNG_BYTES
