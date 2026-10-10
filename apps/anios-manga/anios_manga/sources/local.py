"""Nguồn "Thư viện cục bộ": đọc CBZ/ZIP (và thư mục ảnh) có sẵn trên máy.

Cấu trúc thư mục người dùng (mặc định ~/Manga):

    ~/Manga/
      One Piece/            <- một bộ truyện
        Tập 01.cbz           <- mỗi file nén là một chương
        Tập 02.cbz
      Naruto.cbz            <- bộ một chương: file nén nằm ngay thư mục gốc

Mỗi file .cbz/.zip được giải nén MỘT LẦN vào ~/.local/share/anios-manga/local/<bộ>/<chương>
rồi đọc từ đó (QML không đọc được file nén), và được giải nén lại nếu file gốc đổi.
"""
from __future__ import annotations

import os
import shutil
import time
import zipfile
from pathlib import Path
from typing import Iterable, List, Optional

from ..util import natural_key, safe_name, sorted_images
from .base import Chapter, Listing, Manga, MangaSource

ARCHIVE_SUFFIXES = (".cbz", ".zip")


class LocalSource(MangaSource):
    id = "local"
    name = "Thư viện cục bộ"
    offline = True

    def __init__(self, root: Path, extract_root: Path):
        self.root = Path(root)
        self.extract_root = Path(extract_root)

    # ------------------------------------------------------------------ quét
    def _entries(self) -> List[Path]:
        if not self.root.is_dir():
            return []
        entries = [p for p in self.root.iterdir() if not p.name.startswith(".")]
        entries.sort(key=lambda p: natural_key(p.name))
        return entries

    def _archives(self, folder: Path) -> List[Path]:
        try:
            files = [
                p for p in folder.iterdir()
                if p.is_file() and p.suffix.lower() in ARCHIVE_SUFFIXES and not p.name.startswith(".")
            ]
        except OSError:
            return []
        files.sort(key=lambda p: natural_key(p.name))
        return files

    def _images_here(self, folder: Path) -> List[Path]:
        try:
            return sorted_images(p for p in folder.iterdir() if p.is_file())
        except OSError:
            return []

    def _images_in_tree(self, folder: Path) -> List[Path]:
        """Anh trong ca cay thu muc (file nen co the co thu muc con)."""
        images: List[Path] = []
        for dirpath, _dirnames, filenames in os.walk(folder):
            for name in filenames:
                path = Path(dirpath) / name
                if path.suffix.lower() in {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".avif"}:
                    images.append(path)
        # Sap xep theo duong dan tuong doi de thu tu thu muc con khong pha thu tu doc.
        images.sort(key=lambda p: natural_key(str(p.relative_to(folder))))
        return images

    def list_all(self) -> List[Manga]:
        """Quét thư mục gốc, trả về mọi bộ truyện tìm thấy."""
        out: List[Manga] = []
        for entry in self._entries():
            if entry.is_dir():
                if self._archives(entry) or self._images_here(entry):
                    out.append(self._manga_from_dir(entry))
            elif entry.suffix.lower() in ARCHIVE_SUFFIXES:
                out.append(self._manga_from_archive(entry))
        return out

    def _manga_from_dir(self, folder: Path) -> Manga:
        rel = self._rel(folder)
        chapters = self._archives(folder)
        return Manga(
            source=self.id,
            id=rel,
            title=folder.name,
            description=f"{len(chapters)} chương trong thư mục này"
            if chapters else "Thư mục ảnh trên máy",
            tags=["Offline"],
        )

    def _manga_from_archive(self, path: Path) -> Manga:
        return Manga(
            source=self.id,
            id=self._rel(path),
            title=path.stem,
            description="File CBZ/ZIP trên máy của bạn",
            tags=["Offline"],
        )

    def _rel(self, path: Path) -> str:
        try:
            return str(Path(path).resolve().relative_to(self.root.resolve()))
        except (ValueError, OSError):
            return str(path)

    def _abs(self, manga_id: str) -> Path:
        candidate = (self.root / manga_id).resolve()
        # Không cho thoát khỏi thư mục gốc (manga_id đến từ DB của chính app).
        try:
            candidate.relative_to(self.root.resolve())
        except (ValueError, OSError):
            return self.root
        return candidate

    # ------------------------------------------------------------------ API chung
    def popular(self, page: int = 0) -> Listing:
        return Listing(items=self.list_all(), has_more=False)

    def latest(self, page: int = 0) -> Listing:
        return Listing(items=self.list_all(), has_more=False)

    def search(self, query: str, page: int = 0) -> Listing:
        needle = (query or "").strip().lower()
        if not needle:
            return Listing(items=self.list_all(), has_more=False)
        items = [m for m in self.list_all() if needle in m.title.lower()]
        return Listing(items=items, has_more=False)

    def details(self, manga_id: str) -> Manga:
        path = self._abs(manga_id)
        if path.is_dir():
            return self._manga_from_dir(path)
        return self._manga_from_archive(path)

    def chapters(self, manga_id: str, languages: Optional[List[str]] = None) -> List[Chapter]:
        path = self._abs(manga_id)
        if path.is_dir():
            archives = self._archives(path)
            if archives:
                return [self._chapter_from_archive(a, manga_id) for a in archives]
            images = self._images_here(path)
            if images:
                return [self._chapter_from_images(path, manga_id, images)]
            return []
        if path.suffix.lower() in ARCHIVE_SUFFIXES:
            return [self._chapter_from_archive(path, manga_id)]
        return []

    def _chapter_from_archive(self, path: Path, manga_id: str) -> Chapter:
        with zipfile.ZipFile(path) as zf:
            count = sum(1 for n in zf.namelist() if _is_image_name(n))
        return Chapter(
            id=str(path),
            number="",
            volume="",
            title=path.stem,
            language="",
            pages=count,
        )

    def _chapter_from_images(self, folder: Path, manga_id: str, images: List[Path]) -> Chapter:
        return Chapter(id=str(folder), number="", volume="", title=folder.name, pages=len(images))

    def page_urls(self, chapter: Chapter, *, data_saver: bool = False) -> List[str]:
        # Nguồn cục bộ không có "URL"; các đường dẫn file do prepare_pages trả về.
        return self.prepare_pages(chapter, data_saver=data_saver)

    def prepare_pages(self, chapter: Chapter, *, data_saver: bool = False) -> List[str]:
        """Giải nén chương (nếu là file nén) rồi trả về đường dẫn `file://` từng trang."""
        path = Path(chapter.id)
        if path.is_dir():
            images = self._images_here(path)
        elif path.is_file() and path.suffix.lower() in ARCHIVE_SUFFIXES:
            dest = self._extract_dir(path)
            images = self._extract(path, dest)
        else:
            raise FileNotFoundError(f"Không tìm thấy chương: {chapter.id}")
        if not images:
            raise FileNotFoundError("Chương này không có ảnh nào để đọc.")
        return [img.resolve().as_uri() for img in images]

    # ------------------------------------------------------------------ giải nén
    def _extract_dir(self, archive: Path) -> Path:
        # Tên thư mục gồm tên file + kích thước/mốc thời gian: file cùng tên nhưng
        # khác nội dung không bị dùng lại bản giải nén cũ.
        try:
            stat = archive.stat()
            stamp = f"{int(stat.st_mtime)}-{stat.st_size}"
        except OSError:
            stamp = str(int(time.time()))
        parent = archive.parent.name if archive.parent != self.root else ""
        parts = [p for p in (parent, archive.stem, stamp) if p]
        return self.extract_root.joinpath(*[safe_name(p) for p in parts])

    def _extract(self, archive: Path, dest: Path) -> List[Path]:
        marker = dest / ".extracted"
        if dest.is_dir() and marker.is_file() and self._images_in_tree(dest):
            return self._images_in_tree(dest)
        if dest.exists():
            shutil.rmtree(dest, ignore_errors=True)
        dest.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(archive) as zf:
            for info in zf.infolist():
                name = info.filename
                if not _is_image_name(name) or info.is_dir():
                    continue
                # Chặn "zip slip": tên file tuyệt đối hoặc chứa ".." thì bỏ qua.
                target = _safe_join(dest, name)
                if target is None:
                    continue
                target.parent.mkdir(parents=True, exist_ok=True)
                with zf.open(info) as src, open(target, "wb") as out:
                    shutil.copyfileobj(src, out)
        marker.write_text(str(int(time.time())), encoding="utf-8")
        return self._images_in_tree(dest)

    def manga_url(self, manga_id: str) -> str:
        return self._abs(manga_id).as_uri()


def _is_image_name(name: str) -> bool:
    if name.startswith("__MACOSX") or "/__MACOSX/" in name:
        return False
    return Path(name).suffix.lower() in {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".avif"}


def _safe_join(root: Path, name: str) -> Optional[Path]:
    candidate = (root / name).resolve()
    try:
        candidate.relative_to(root.resolve())
    except (ValueError, OSError):
        return None
    return candidate


def dir_size(path: Path) -> int:
    total = 0
    for dirpath, _dirnames, filenames in os.walk(path):
        for name in filenames:
            try:
                total += (Path(dirpath) / name).stat().st_size
            except OSError:
                continue
    return total


def iter_files(path: Path) -> Iterable[Path]:
    for dirpath, _dirnames, filenames in os.walk(path):
        for name in filenames:
            yield Path(dirpath) / name
