# AniOS

AniOS là **Live USB/DVD Arch Linux** hướng tới chơi game trên máy tính phòng net: khởi động vào Hyprland gọn nhẹ với kernel `linux-zen`, cài sẵn Steam và driver đồ họa mã nguồn mở phổ biến cho Intel/AMD. Dự án cũng có lựa chọn cài desktop [Immaterial Impulse](https://github.com/XephyLon/immaterial-impulse) chính chủ qua một shortcut sau khi vào desktop.

> Repository này chứa **Archiso profile và script tạo ISO**, chưa kèm file ISO dựng sẵn. Cần một máy build chạy Arch Linux để tạo ảnh.

## Tạo ISO Live

Trên máy build Arch Linux x86_64 đã cập nhật đầy đủ:

```bash
sudo pacman -Syu --needed archiso git
# Clone repository rồi chạy:
cd AniOS
sudo ./scripts/build-iso.sh
```

ISO được đặt trong `out/`, file tạm ở `work/`. Có thể chọn đường dẫn khác:

```bash
sudo ./scripts/build-iso.sh --output /duong-dan/iso --work /duong-dan/work
```

Script dùng profile `releng` của Archiso đang cài trên máy, bật kho `multilib` chính thức để cài Steam, rồi thêm cấu hình AniOS. Cần Internet để tải các gói Arch. ISO hoàn chỉnh sẽ có dung lượng vài GB; nên dùng USB ít nhất 8 GB và kiểm tra ISO trước khi phát hành.

## Sử dụng phiên Live

- AniOS tự đăng nhập vào tài khoản tạm `anios` và khởi chạy Hyprland. Tài khoản Live có quyền `sudo` không cần mật khẩu để tiện sử dụng; **không dùng phiên này với dữ liệu riêng tư hoặc trên mạng không đáng tin cậy**.
- Kết nối Wi-Fi bằng biểu tượng mạng trên thanh trạng thái hoặc lệnh `nmtui`; kết nối dây do NetworkManager quản lý.
- Mở Steam từ launcher. Steam cần Internet và tài khoản Steam. Có thể thử GameMode bằng cách thêm `gamemoderun %command%` vào Steam → Properties → Launch Options của game. Trên USB Live thông thường, game và thiết lập không được lưu sau khi tắt máy; hãy dùng ổ ngoài có lưu trữ bền vững hoặc cài hệ thống vào ổ đĩa nếu sử dụng thường xuyên.
- `Super+Return`: mở Foot; `Super+D`: mở launcher; `Super+Shift+E`: thoát phiên Hyprland.
- Desktop mặc định tắt blur và animation để giảm tải GPU. `Super+Space` bật/tắt chế độ cửa sổ nổi.

## Cài desktop Immaterial Impulse

Phiên mặc định được giữ nhẹ. Shortcut **Install Immaterial Impulse** sẽ clone repository của XephyLon và chạy trình cài đặt tương tác chính chủ với quyền user thường:

```bash
anios-setup
```

Cần Internet. Immaterial Impulse là desktop Quickshell nhiều tính năng; trình cài đặt có thể tải thêm nhiều gói (một số gói được build từ AUR), sử dụng thêm RAM/VRAM và mất thời gian thiết lập. Vì vậy AniOS để bước này tự chọn, không tự chạy khi boot, nhằm giữ cấu hình mặc định phù hợp hơn với máy phòng net đời cũ. Phần mềm upstream và giấy phép của nó được quản lý riêng; hãy xem repository upstream để biết yêu cầu mới nhất.

## Phần cứng và hiệu năng

- AniOS nhắm đến máy **x86_64**. Không hệ điều hành nào có thể bảo đảm game tương thích hoặc chạy nhanh trên mọi cấu hình; hiệu năng tùy thuộc CPU, GPU, RAM, tản nhiệt, trò chơi và driver. `linux-zen` được chọn để ưu tiên độ phản hồi, **không bảo đảm FPS cao hơn**.
- ISO có Mesa/OpenGL/Vulkan cho Intel và AMD, cùng các thư viện 32-bit Steam. Driver NVIDIA proprietary không được cài sẵn; các card NVIDIA đời cũ có thể cần driver và cấu hình kernel riêng. Hãy kiểm tra từng model GPU trước khi triển khai cho quán net.
- Hyprland là compositor Wayland. GPU quá cũ, không có DRM/KMS hoạt động tốt có thể không phù hợp. Nếu giao diện đồ họa không chạy, chuyển TTY khác bằng `Ctrl+Alt+F2` để kiểm tra log.
- Hệ thống Live chạy từ ảnh nén trong RAM và không phải trình cài đặt vào ổ đĩa. Cần đủ RAM cho hệ thống và game; để dùng ổn định trong quán net, nên cài lên ổ đĩa và kiểm thử từng mẫu máy trước.

## Cấu trúc repository

- `profile/airootfs/` — tài khoản Live, Hyprland, Waybar, mạng và cấu hình phiên.
- `profile/packages.x86_64` — các gói desktop, kernel, game, firmware và tiện ích bổ sung vào Archiso `releng`.
- `scripts/build-iso.sh` — dựng profile Archiso tạm thời và chạy `mkarchiso`.
- `scripts/check-profile.sh` — kiểm tra cấu trúc profile và cú pháp script ngoại tuyến.

## Kiểm tra nhanh

```bash
./scripts/check-profile.sh
```

Lệnh kiểm tra không cần Arch Linux. Để tạo và kiểm thử ISO vẫn cần máy Archiso (hoặc máy ảo Arch Linux). Nên boot thử ISO với từng GPU trước khi phát hành.
