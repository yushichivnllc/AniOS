"""Kiểm thử nguồn cục bộ: quét thư mục, thứ tự chương, giải nén và chống zip slip."""
from __future__ import annotations

import zipfile
from pathlib import Path

import pytest

from anios_manga.sources.local import LocalSource, dir_size


def make_cbz(path: Path, names, extra=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w") as zf:
        for name in names:
            zf.writestr(name, b"\x89PNG fake")
        for name, data in (extra or {}).items():
            zf.writestr(name, data)
    return path


@pytest.fixture()
def library_root(tmp_path):
    root = tmp_path / "Manga"
    root.mkdir()
    return root


@pytest.fixture()
def source(library_root, tmp_path):
    return LocalSource(library_root, tmp_path / "extract")


def test_scan_finds_directories_and_single_archives(source, library_root):
    make_cbz(library_root / "One Piece" / "Tập 01.cbz", ["1.png", "2.png"])
    make_cbz(library_root / "One Piece" / "Tập 02.cbz", ["1.png"])
    make_cbz(library_root / "Naruto.cbz", ["a.png"])
    (library_root / "Ghi chu.txt").write_text("không phải truyện", encoding="utf-8")

    titles = [m.title for m in source.list_all()]
    assert titles == ["Naruto", "One Piece"]


def test_chapters_are_sorted_naturally(source, library_root):
    folder = library_root / "Bleach"
    for name in ("Tập 1.cbz", "Tập 2.cbz", "Tập 10.cbz"):
        make_cbz(folder / name, ["1.png"])

    chapters = source.chapters("Bleach")
    assert [Path(c.id).name for c in chapters] == ["Tập 1.cbz", "Tập 2.cbz", "Tập 10.cbz"]
    assert chapters[0].pages == 1


def test_prepare_pages_extracts_archive_once(source, library_root, tmp_path):
    archive = make_cbz(library_root / "Bộ" / "ch1.cbz", ["3.png", "1.png", "2.png"])
    chapters = source.chapters("Bộ")
    urls = source.prepare_pages(chapters[0])

    assert len(urls) == 3
    assert all(u.startswith("file://") for u in urls)
    # Ảnh được sắp xếp theo thứ tự đọc, không phải theo thứ tự trong file nén.
    assert [Path(u).name for u in urls] == ["1.png", "2.png", "3.png"]

    # Lần hai đọc lại bản đã giải nén, không giải nén lại.
    folder = Path(urls[0][len("file://"):]).parent
    before = sorted(p.name for p in folder.iterdir())
    urls_again = source.prepare_pages(chapters[0])
    assert urls == urls_again
    assert sorted(p.name for p in folder.iterdir()) == before


def test_prepare_pages_reextracts_when_archive_changes(source, library_root):
    archive = library_root / "Bộ" / "ch1.cbz"
    make_cbz(archive, ["1.png"])
    first = source.prepare_pages(source.chapters("Bộ")[0])
    make_cbz(archive, ["1.png", "2.png", "3.png"])
    second = source.prepare_pages(source.chapters("Bộ")[0])
    assert len(first) == 1
    assert len(second) == 3


def test_prepare_pages_reads_folder_of_images(source, library_root):
    folder = library_root / "Ảnh lẻ"
    folder.mkdir()
    for name in ("1.png", "2.jpg", "3.png"):
        (folder / name).write_bytes(b"\x89PNG fake")
    (folder / "notes.txt").write_text("bỏ qua", encoding="utf-8")

    chapters = source.chapters("Ảnh lẻ")
    assert len(chapters) == 1
    urls = source.prepare_pages(chapters[0])
    assert [Path(u).name for u in urls] == ["1.png", "2.jpg", "3.png"]


def test_archive_with_nested_folders(source, library_root):
    make_cbz(library_root / "Lồng" / "ch.cbz", ["Thư mục/1.png", "Thư mục/2.png"])
    urls = source.prepare_pages(source.chapters("Lồng")[0])
    assert len(urls) == 2


def test_zip_slip_entries_are_ignored(source, library_root):
    make_cbz(
        library_root / "Độc" / "evil.cbz",
        ["1.png"],
        extra={"../../though-u.png": b"x", "/tmp/absolute.png": b"y"},
    )
    urls = source.prepare_pages(source.chapters("Độc")[0])
    assert len(urls) == 1
    for url in urls:
        assert ".." not in url and "absolute" not in url


def test_macosx_junk_is_skipped(source, library_root):
    make_cbz(library_root / "Rác" / "ch.cbz", ["__MACOSX/._1.png", "1.png"])
    assert len(source.prepare_pages(source.chapters("Rác")[0])) == 1


def test_search_filters_by_title(source, library_root):
    make_cbz(library_root / "Doraemon.cbz", ["1.png"])
    make_cbz(library_root / "Conan.cbz", ["1.png"])
    titles = [m.title for m in source.search("dora").items]
    assert titles == ["Doraemon"]


def test_offline_flags():
    assert LocalSource(Path("/tmp"), Path("/tmp/x")).offline is True
    assert LocalSource(Path("/tmp"), Path("/tmp/x")).id == "local"


def test_dir_size_counts_files(tmp_path):
    (tmp_path / "a.bin").write_bytes(b"x" * 10)
    (tmp_path / "b.bin").write_bytes(b"y" * 5)
    assert dir_size(tmp_path) == 15
