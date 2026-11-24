# Báo cáo lỗ hổng bảo mật

AniOS là một bản phân phối Arch Linux chạy trực tiếp trên USB, thường ở **chế
độ live** trong quán net hoặc phòng học. Vì vậy lỗ hổng không chỉ ảnh hưởng
người dùng cuối mà còn ảnh hưởng **mọi máy khác** trong cùng mạng.

## Báo cáo

Mở một **issue ẩn danh (private)** trên GitHub — không dùng issue công khai cho
tới khi đã có bản vá.

Vui lòng kèm:

- phiên bản bản ISO (`anios` / `aniterals` / `anix`) và ngày dựng;
- các bước tái hiện;
- tác động (ai bị ảnh hưởng, dữ liệu nào lộ).

Chúng tôi sẽ phản hồi trong 7 ngày.

## Những gì đã biết và được chấp nhận

Các điểm dưới đây là **thiết kế có chủ ý** của bản live, không phải lỗ hổng:

| Điểm | Vì sao |
| --- | --- |
| Tài khoản live `anios` có mật khẩu `1111` và `sudo` không cần mật khẩu | Bản live được dựng để mở ra là dùng được ngay, không cần đăng nhập. Bộ cài đặt **loại bỏ** mật khẩu này và tạo tài khoản riêng cho máy đã cài. |
| Mật khẩu live xuất hiện trong bộ dotfile | `anios-installer-skel` quét và loại bỏ trước khi đưa sang máy đã cài. |
| `AniTails` chạy hoàn toàn trong RAM | Đây là điểm mạnh của bản amnesic: không lưu dấu vết xuống đĩa. Nhưng dữ liệu trong RAM vẫn bị đọc được bởi người có quyền truy cập vật lý. |
| Ảnh không có SBOM/checksum ký số ở mức phát hành | Sẽ bổ sung ở WAVE 3. |

## Phạm vi

- Bộ cài đặt Calamares và các helper trong `profile/installer/`.
- Các script chạy trong phiên live: `profile/airootfs/usr/local/bin/anios-*`.
- Chế độ quán net (`anios-cafe`) — đây là script **xoá dữ liệu**.
- Bộ dựng ISO (`scripts/build-iso.sh`, `scripts/anios-aur-build.sh`).
