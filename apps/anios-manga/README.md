# AniOS Manga

Trình đọc truyện tranh cho Linux, viết bằng PySide6 (Qt Quick) với giao diện Material Design —
bản viết lại cho Linux từ ứng dụng Android [Kotatsu-Redo](https://github.com/Kotatsu-Redo/Kotatsu-Redo)
(theo đúng kiểu `apps/anios-reddit`: Python + QML, không dùng APK, Waydroid hay bản port Kotlin).

App đọc truyện từ hai nguồn, chuyển qua lại trong Cài đặt:

| Nguồn | Nội dung | Cần mạng? |
| --- | --- | --- |
| **MangaDex** | API JSON công khai, không cần đăng ký, không cần khoá | có |
| **Thư viện cục bộ** | file `.cbz`/`.zip` (và thư mục ảnh) có sẵn trên máy | không |

## Tính năng

- **Khám phá**: nổi bật / mới nhất / tìm kiếm, lọc theo thể loại (tag MangaDex), tải thêm theo trang.
- **Chi tiết truyện**: bìa, tác giả, hoạ sĩ, trạng thái, mô tả, thể loại, danh sách chương (chương mới nhất trước).
- **Đọc truyện**: ba chế độ — cuộn dọc (webtoon, mặc định), từng trang, và từng trang theo kiểu phải-qua-trái (manga Nhật).
  Cuộn/đổi trang ghi lại tiến độ; bấm *Đọc tiếp* mở đúng chương và trang đang đọc dở.
- **Kệ sách**: lưu truyện yêu thích, xếp theo thể loại kệ (tạo/xoá thể loại được), thêm/bỏ bằng chuột phải trên thẻ truyện.
- **Lịch sử**: truyện đã đọc gần đây, xoá từng mục hoặc xoá hết.
- **Tải xuống**: tải cả chương về máy để đọc offline; chương đã tải được đánh dấu trong danh sách chương và
  đọc trực tiếp từ đĩa (không tốn mạng). Xoá bản tải được từ trang Tải xuống.
- **Cài đặt**: sáng/tối, chế độ đọc, ngôn ngữ ưu tiên, ảnh nén (data saver), cho phép nội dung 18+,
  thư mục chứa CBZ/ZIP, mở thư mục dữ liệu.

## Cấu hình và dữ liệu

- Cấu hình: `~/.config/anios-manga/config.json` (hoặc `$ANIOS_MANGA_CONFIG`, hoặc `anios-manga --config <file>`).
- Dữ liệu: `~/.local/share/anios-manga/` (hoặc `$XDG_DATA_HOME`): `library.db` (SQLite: kệ sách, thể loại,
  tiến độ, lịch sử, bản tải), `cache/` (ảnh bìa và trang truyện đã tải), `local/` (chương CBZ/ZIP đã giải nén).

## Chạy thử

```sh
python -m venv .venv && . .venv/bin/activate
pip install -e '.[test]'
anios-manga                 # hoặc: python -m anios_manga
anios-manga --config /duong/dan/config.json
```

Shortcut trong menu ứng dụng (không cần root; cần `anios-manga` đã có trong PATH):

```sh
./install-desktop.sh              # mục menu + icon
./install-desktop.sh --desktop    # thêm biểu tượng trên Desktop
./install-desktop.sh --uninstall  # gỡ shortcut
```

Trên Arch Linux: `sudo pacman -S pyside6` rồi `python -m anios_manga` trong thư mục này.

## Kiểm thử

```sh
pytest
```

Không test nào gọi mạng: MangaDex và CDN ảnh được thay bằng transport giả đọc từ `tests/fixtures/`
(dữ liệu mẫu, không phải nội dung MangaDex thật), còn urllib được thay bằng `urlopen` giả trong hai bài
kiểm tra đường chạy thật. Test QML nạp giao diện thật với `QT_QPA_PLATFORM=offscreen`; nó cũng chặn
lỗi kiểu "tên thuộc tính/slot không tồn tại" và "anchors trên item do layout quản lý".
Đặt `ANIOS_MANGA_SHOT=/tmp/manga.png` để lưu ảnh chụp màn hình.

## Cấu trúc

- `anios_manga/http.py` — tầng HTTP chung (urllib): mọi lỗi mạng/HTTP/phản hồi hỏng quy về một kiểu
  `MangaError` có thông điệp tiếng Việt. `transport` có thể thay bằng bản giả để kiểm thử offline.
  Ảnh phải đi qua `default_bytes_transport` (`surrogateescape`) nếu không sẽ hỏng byte.
- `anios_manga/sources/` — giao diện chung `MangaSource` và hai nguồn: `mangadex.py` (API v5: duyệt,
  tìm kiếm, chi tiết, chương, `/at-home/server/` lấy link ảnh, tag) và `local.py` (quét CBZ/ZIP/thư mục ảnh,
  giải nén chương ra đĩa rồi trả đường dẫn `file://`).
- `anios_manga/library.py` — SQLite: kệ sách, thể loại kệ, tiến độ đọc, lịch sử, bản tải xuống.
- `anios_manga/downloader.py` — tải ảnh một chương về `~/.local/share/anios-manga/downloads/...`,
  ghi `meta.json`, tải lại thì tiếp tục chứ không tải lại trang đã có.
- `anios_manga/images.py` — `image://manga/...`: tải ảnh ở luồng nền, cache ra đĩa theo sha1(url),
  ghi `.part` rồi đổi tên để không bao giờ đọc phải file tải dở.
- `anios_manga/models.py` — model danh sách cho QML và vai trò của từng bảng.
- `anios_manga/backend.py` — cầu nối Python ↔ QML: mỗi thao tác mạng chạy ở luồng nền, kết quả cũ bị
  bỏ qua khi người dùng đã đổi sang truyện/chương khác.
- `anios_manga/qml/` — giao diện: `Main.qml`, `LibraryPage.qml`, `ExplorePage.qml`, `DetailsPage.qml`,
  `ReaderPage.qml`, `HistoryPage.qml`, `DownloadsPage.qml`, `SettingsPage.qml`, `MangaCard.qml`,
  `ChapterItem.qml`.
- `data/anios-manga.desktop`, `data/anios-manga.svg` — mục menu ứng dụng và icon; `install-desktop.sh` cài chúng vào thư mục người dùng.

## Chưa làm

- Chưa đưa vào ISO: cần thêm gói `pyside6` vào `profile/packages.x86_64` và cài thư mục này vào `/usr/lib`,
  cùng `.desktop` và icon (giống trạng thái hiện tại của `apps/anios-reddit`).
- Mới chỉ có hai nguồn (MangaDex và thư viện cục bộ); Kotatsu-Redo có 900+ nguồn nhưng mỗi nguồn là một
  bộ parser riêng, cần thêm dần.
- Chưa đồng bộ tiến độ giữa máy, chưa đọc được một số định dạng lạ (`.cb7`, `.pdf`, `.epub`).
