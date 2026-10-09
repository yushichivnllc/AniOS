# AniOS Reddit

Trình đọc Reddit cho Linux, viết bằng PySide6 (Qt Quick) với giao diện Material Design.

Ứng dụng chỉ hiển thị một trang: [r/unixporn](https://www.reddit.com/r/unixporn/). Chỉ đọc:
sắp xếp (Nổi bật / Mới / Top / Đang lên / Gây tranh cãi), khoảng thời gian cho Top, tải thêm bài,
xem ảnh xem trước, đọc bài viết tự và bình luận có thụt lề theo độ sâu. Không có tìm kiếm toàn Reddit,
danh sách subreddit hay đăng nhập; chưa hỗ trợ bỏ phiếu hoặc bình luận.

## Vì sao cần client ID

Reddit yêu cầu mọi truy cập Data API phải qua OAuth và giới hạn/chặn yêu cầu không định danh
([Reddit Data API Wiki](https://support.reddithelp.com/hc/en-us/articles/16160319875092-Reddit-Data-API-Wiki)).
Vì vậy bạn cần tạo một ứng dụng một lần:

1. Mở https://www.reddit.com/prefs/apps và bấm **create another app…**
2. Chọn loại **installed app**, đặt tên tuỳ ý.
3. Redirect URI: `http://localhost:8080` (không được dùng, nhưng Reddit yêu cầu).
4. Sao chép client ID (chuỗi dưới tên ứng dụng) và dán vào màn hình kết nối của app.

App dùng luồng *installed client* để lấy token chỉ-đọc, không cần đăng nhập tài khoản Reddit.
Client ID được lưu tại `~/.config/anios-reddit/config.json` (quyền 600). Chuỗi User-Agent được
tạo theo định dạng Reddit yêu cầu: `linux:com.anios.reddit:<phiên bản> (by /u/<tên>)`; có thể đặt
tên Reddit của bạn bằng trường `contact` trong file cấu hình.

Giới hạn tốc độ của Reddit áp dụng cho client ID của bạn. Khi bị giới hạn, app hiển thị thông báo kèm
số giây cần chờ.

## Chạy thử

```sh
python -m venv .venv && . .venv/bin/activate
pip install -e '.[test]'
anios-reddit                 # hoặc: python -m anios_reddit
anios-reddit --config /duong/dan/config.json
```

Trên Arch Linux: `sudo pacman -S pyside6` rồi `python -m anios_reddit` trong thư mục này.

## Kiểm thử

```sh
pytest
```

Các test không gọi mạng: Reddit được thay bằng transport giả đọc từ `tests/fixtures/` (dữ liệu
mẫu, không phải nội dung Reddit thật). Test QML nạp giao diện thật với `QT_QPA_PLATFORM=offscreen`.
Đặt `ANIOS_REDDIT_SHOT=/tmp/feed.png` để lưu ảnh chụp màn hình.

## Cấu trúc

- `anios_reddit/api.py` — client Reddit (OAuth, phân tích listing/bình luận, định dạng số và thời gian). Không phụ thuộc Qt.
- `anios_reddit/backend.py` — cầu nối Python ↔ QML; tải r/unixporn ở luồng nền, bỏ qua kết quả cũ khi người dùng đổi sắp xếp.
- `anios_reddit/models.py` — model danh sách cho QML.
- `anios_reddit/settings.py` — cấu hình người dùng (client ID, chế độ sáng/tối, sắp xếp đã chọn).
- `anios_reddit/qml/` — giao diện: `Main.qml`, `FeedPage.qml`, `PostCard.qml`, `PostPage.qml`, `CommentItem.qml`, `SetupPage.qml`.
- `data/anios-reddit.desktop` — mục menu ứng dụng.

## Chưa làm

- Chưa đưa vào ISO: cần thêm gói `pyside6` vào `profile/packages.x86_64` và cài thư mục này vào `/usr/lib`, cùng `.desktop`.
- Chưa tải nội dung đa phương tiện (video, gallery) và chưa nạp thêm bình luận ("more").
