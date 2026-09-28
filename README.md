# AniOS

AniOS là **Live USB/DVD Arch Linux** hướng tới chơi game trên máy tính phòng net: khởi động vào Hyprland gọn nhẹ với kernel `linux-zen`, cài sẵn Steam và driver đồ họa mã nguồn mở phổ biến cho Intel/AMD. Dự án cũng có lựa chọn cài desktop [Immaterial Impulse](https://github.com/XephyLon/immaterial-impulse) chính chủ qua một shortcut sau khi vào desktop.

> Repository này chứa **Archiso profile và script tạo ISO**. File ISO được dựng tự động bằng [GitHub Actions](#dựng-iso-tự-động-bằng-github-actions), hoặc dựng tay trên máy Arch Linux.

## AniOS và Arch Linux

AniOS là **bản phối lại của Arch Linux**, không phải một hệ điều hành khác. Cách đặt tên được giữ đúng theo hướng dẫn của Arch:

- **Bên ngoài là AniOS**: menu khởi động, `/etc/os-release` (`NAME="AniOS"`), `/etc/issue`, `/etc/motd`, wallpaper và giao diện đăng nhập SDDM đều mang tên AniOS, kèm dòng giới thiệu "Arch Linux based" để người dùng biết hệ nền.
- **Bên trong là Arch Linux**: `ID=arch` và `ID_LIKE=arch` trong `/etc/os-release` không đổi, nên các công cụ Arch vẫn hoạt động đúng — `pacman`, AUR helper, `mkinitcpio`, `archiso`, script cài đặt của upstream đều nhận ra hệ nền và không bị nhầm với bản phân phối khác.
- **Logo/màn hình khởi động** do AniOS tự làm (xem `profile/branding/`), không dùng tài nguyên của Arch hay của dự án khác.

Nói ngắn gọn: mọi thứ người dùng nhìn thấy là AniOS, còn những gì hệ thống cần để chạy là Arch Linux nguyên bản.

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

Script dùng profile `releng` của Archiso đang cài trên máy, đổi kernel sang `linux-zen` trong mọi mục menu (Syslinux, GRUB, systemd-boot, loopback), dán ảnh thương hiệu AniOS vào `syslinux/splash.png` và `usr/share/anios/wallpaper.png`, bật kho `multilib` chính thức để cài Steam, rồi thêm cấu hình AniOS. Cần Internet để tải các gói Arch. ISO hoàn chỉnh sẽ có dung lượng vài GB; nên dùng USB ít nhất 8 GB và kiểm tra ISO trước khi phát hành.

## Dựng ISO tự động bằng GitHub Actions

Workflow `.github/workflows/build-iso.yml` dựng ISO trên runner Ubuntu bằng cách chạy trực tiếp container Docker `archlinux:base-devel`, rồi gọi đúng `scripts/build-iso.sh` nên kết quả giống hệt khi dựng tay. Mỗi lượt chạy tự giải phóng dung lượng đĩa của runner, cài `archiso`, kiểm tra profile, dựng ISO, rồi tự kiểm tra kết quả (checksum SHA256, boot record El Torito cho BIOS/UEFI, đúng kernel `linux-zen`, và đọc thẳng `airootfs.sfs` để xác nhận tên AniOS, wallpaper, theme SDDM Wuthering Waves và cấu hình desktop có thật trong ảnh live) trước khi lưu lại. Nếu một bước hỏng, lượt chạy đỏ và không có artifact.

Khi nào workflow chạy:

| Khi nào | Kết quả |
| --- | --- |
| Mở PR có thay đổi trong `profile/`, `scripts/` hoặc chính workflow này | Dựng thử ISO và kiểm tra ảnh live ngay trên PR, chỉ lưu artifact, không tạo release |
| Tab **Actions → Build AniOS ISO → Run workflow** | Dựng ISO ngay; bật tuỳ chọn `publish` để tạo release `nightly` |
| Đẩy tag, ví dụ `git tag v1.0.0 && git push origin v1.0.0` | Dựng ISO và tạo release `AniOS v1.0.0` |
| Lịch hằng tuần (Chủ nhật 18:23 UTC) | Dựng lại để ISO bám theo kho gói rolling của Arch, cập nhật release `nightly` |

Cách lấy file ISO:

- **Artifact**: mở lần chạy tương ứng, cuộn xuống mục **Artifacts**, tải `anios-iso` (gồm file ISO, file `.sha256` và danh sách gói). Artifact được giữ 30 ngày.
- **Release**: có ở lượt chạy theo tag hoặc `nightly`. GitHub chỉ nhận tệp đính kèm nhỏ hơn 2 GB, nên khi ISO nặng hơn thì workflow chỉ đính kèm checksum, danh sách gói và ghi link tải artifact trong phần mô tả release.

Kiểm tra file sau khi tải:

```bash
sha256sum -c anios-<ngay>-x86_64.iso.sha256
sudo dd if=anios-<ngay>-x86_64.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

Lưu ý: mỗi lượt dựng mất khoảng 30–90 phút và vài chục GB dung lượng đĩa tuỳ tốc độ tải gói Arch. Muốn dựng khi có push vào nhánh chính, thêm `branches: [main]` vào mục `push` của workflow (dưới `tags:`). ISO do CI dựng vẫn nên boot thử trên máy thật, đặc biệt với từng model GPU, trước khi đưa vào quán.

## Sử dụng phiên Live

- SDDM tự đăng nhập vào tài khoản Live tạm `anios` và khởi chạy phiên AniOS trên Hyprland. Mật khẩu tài khoản Live và `sudo` đều là `1111`; đây là mật khẩu cố ý đơn giản cho môi trường live tạm thời, **không dùng phiên này với dữ liệu riêng tư hoặc trên mạng không đáng tin cậy**.
- Kết nối Wi-Fi bằng biểu tượng mạng trên thanh trạng thái hoặc lệnh `nmtui`; kết nối dây do NetworkManager quản lý.
- **Gõ tiếng Việt**: cài sẵn cả **ibus (ibus-unikey)** và **fcitx5 (fcitx5-unikey)**. Mặc định phiên khởi động với fcitx5, nhấn `Ctrl+Space` để bật/tắt tiếng Việt (Telex). Người dùng có thể dễ dàng chuyển đổi qua lại giữa IBus và Fcitx5 bất kỳ lúc nào bằng lệnh `anios-switch-im ibus` hoặc `anios-switch-im fcitx5`.
- **Dotfile cài sẵn**: tài khoản live và hệ thống được thiết lập sẵn bộ dotfile hoàn chỉnh gồm cấu hình shell Bash (`~/.bashrc` với prompt màu AniOS, alias thông dụng `ll`, `fetch`, `update`), Fish shell (`~/.config/fish/config.fish`), Kitty terminal (`~/.config/kitty/kitty.conf`), HUD chơi game MangoHud (`~/.config/MangoHud/MangoHud.conf`, bật tắt bằng `Shift_R+F12`), GameMode (`~/.config/gamemode.ini`), Fastfetch (`~/.config/fastfetch/config.jsonc`), Git, Vim và Nano.
- **Cắm USB/ổ cứng ngoài**: udisks2 + gvfs tự mount, ổ hiện trong Thunar và trên thanh trạng thái, hỗ trợ NTFS/exFAT/FAT32.
- Mở Steam từ launcher. Steam cần Internet và tài khoản Steam. Có thể thử GameMode bằng cách thêm `gamemoderun %command%` vào Steam → Properties → Launch Options của game. Steam và mọi thứ bạn tải trong phiên chỉ nằm trong RAM/overlay tạm: hãy copy file cần giữ ra ổ ngoài trước khi tắt máy, hoặc cài hệ thống vào ổ đĩa nếu sử dụng thường xuyên.
- Phím tắt: `Super+Return` mở Foot; `Super+D` mở launcher; `Super+Shift+L` khoá màn hình; `Ctrl+Alt+F2` mở TTY cứu hộ (ở đó `fastfetch` in thông tin máy); `Super+Shift+E` thoát phiên Hyprland.
- **Màn hình khoá dùng mật khẩu**, không phải cơ chế bảo mật mạnh: nhập `1111` để mở khoá. Tài khoản live và `sudo` dùng cùng mật khẩu; mật khẩu này được tạo sẵn trong ảnh từ lúc build (pacman hook `anios-live-user.hook` viết hash vào `/etc/shadow`) và được `anios-live-home.service` đặt lại ở mỗi lần khởi động như dự phòng. Vì vậy đừng để dữ liệu quan trọng trong phiên live.
- Nếu thoát phiên bằng `Super+Shift+E`, SDDM sẽ hiện theme **Wuthering Waves** của Qylock; chọn phiên **AniOS (Hyprland)** rồi nhập `1111` để vào lại. Theme hiện khung nền tĩnh ngay, rồi mới khởi tạo video sau 1,2 giây; nếu thiếu codec video thì khung tĩnh vẫn giữ cho màn hình đăng nhập dùng được. Các lỗi không vào được SDDM đã được xử lý triệt để: tắt tiến trình agetty autologin tty1 của releng để tránh tranh chấp VT, chuẩn hoá UID 1000 và nhóm quyền phần cứng (wheel, video, audio, input, seat) cho tài khoản `anios`, sửa liên kết dịch vụ chuẩn bị thư mục người dùng (`anios-live-home.service`), cấu hình `MinimumUid=500` cho SDDM, bổ sung fallback tài khoản tự động trong theme, và "nướng" mật khẩu `1111` vào `/etc/shadow` từ lúc build bằng pacman hook để đăng nhập thủ công SDDM (stack PAM `sddm` → `pam_unix`) không phụ thuộc vào việc service lúc khởi động có chạy thành công hay không — autologin thì luôn qua được vì dùng stack `sddm-autologin` (kết thúc bằng `pam_permit`).
- Desktop mặc định tắt blur và animation để giảm tải GPU. `Super+Space` bật/tắt chế độ cửa sổ nổi.
- **Cấu hình Hyprland** nằm ở `~/.config/hypr/hyprland.lua` (bản sao gốc trong ảnh: `/usr/share/anios/skel/.config/hypr/hyprland.lua`): từ Hyprland 0.55 cấu hình viết bằng Lua thay cho `hyprland.conf` cũ, nên sau khi sửa chỉ cần `Super+Shift+R` để nạp lại. Màn hình khoá dùng định dạng riêng của hyprlock (`~/.config/hypr/hyprlock.conf`).

## Cài desktop Immaterial Impulse

Phiên mặc định được giữ nhẹ. Shortcut **Install Immaterial Impulse** sẽ clone repository của XephyLon và chạy trình cài đặt tương tác chính chủ với quyền user thường:

```bash
anios-setup
```

Cần Internet. Immaterial Impulse là desktop Quickshell nhiều tính năng; trình cài đặt có thể tải thêm nhiều gói (một số gói được build từ AUR), sử dụng thêm RAM/VRAM và mất thời gian thiết lập. Vì vậy AniOS để bước này tự chọn, không tự chạy khi boot, nhằm giữ cấu hình mặc định phù hợp hơn với máy phòng net đời cũ. Phần mềm upstream và giấy phép của nó được quản lý riêng; hãy xem repository upstream để biết yêu cầu mới nhất.

## Phần cứng và hiệu năng

- AniOS nhắm đến máy **x86_64**. Không hệ điều hành nào có thể bảo đảm game tương thích hoặc chạy nhanh trên mọi cấu hình; hiệu năng tùy thuộc CPU, GPU, RAM, tản nhiệt, trò chơi và driver. `linux-zen` được chọn để ưu tiên độ phản hồi, **không bảo đảm FPS cao hơn**.
- ISO có Mesa/OpenGL/Vulkan cho Intel và AMD, cùng các thư viện 32-bit Steam và XWayland để game chỉ có bản X11 vẫn chạy trong phiên Hyprland. Driver NVIDIA proprietary không được cài sẵn; các card NVIDIA đời cũ có thể cần driver và cấu hình kernel riêng. Hãy kiểm tra từng model GPU trước khi triển khai cho quán net.
- Hyprland là compositor Wayland. GPU quá cũ, không có DRM/KMS hoạt động tốt có thể không phù hợp. Nếu giao diện đồ họa không chạy, chuyển TTY khác bằng `Ctrl+Alt+F2` và xem `journalctl -b -u sddm` hoặc `~/.local/share/hyprland/hyprland.log`.
- Hệ thống Live chạy từ ảnh nén trong RAM (zram là swap nén, `vm.swappiness=100` để giảm nghẽn khi mở nhiều game) và không phải trình cài đặt vào ổ đĩa. Cần đủ RAM cho hệ thống và game; để dùng ổn định trong quán net, nên cài lên ổ đĩa và kiểm thử từng mẫu máy trước.

## Cấu trúc repository

- `profile/airootfs/` — tài khoản Live, SDDM tự đăng nhập và theme **Wuthering Waves** (Qylock) đã tinh chỉnh khởi tạo video có dự phòng, phiên Hyprland (cấu hình Lua `hyprland.lua` + `hyprlock.conf`), Waybar, dotfile cài sẵn, ibus & fcitx5, mạng và cấu hình phiên, kèm pacman hook (`etc/pacman.d/hooks/anios-live-user.hook`) tạo sẵn tài khoản live và mật khẩu `1111` trong ảnh lúc build.
- `profile/airootfs/usr/share/sddm/themes/wuwa/` — theme Qylock Wuthering Waves, mã nguồn giấy phép GPL-3.0; thông tin upstream và commit nguồn ở `UPSTREAM`.
- `profile/airootfs/etc/os-release` — tên AniOS hiển thị cho người dùng, `ID=arch` để giữ tương thích công cụ Arch.
- `profile/branding/` — wallpaper và splash menu khởi động; dựng lại bằng `./scripts/make-branding-assets.sh` (cần ImageMagick).
- `profile/packages.x86_64` — các gói desktop, kernel, game, firmware, ibus-unikey và tiện ích bổ sung vào Archiso `releng`.
- `scripts/build-iso.sh` — dựng profile Archiso tạm thời (kernel `linux-zen`, ảnh thương hiệu, gỡ bỏ xung đột agetty tty1, sao chép dotfile cho tài khoản live) và chạy `mkarchiso`.
- `scripts/check-profile.sh` — kiểm tra cấu trúc profile, danh sách gói, định danh AniOS, dotfile và cú pháp script ngoại tuyến.
- `.github/workflows/build-iso.yml` — dựng ISO tự động, kiểm tra ảnh live, xuất artifact và phát hành release.
- `.github/workflows/profile-check.yml` — kiểm tra nhanh profile trên mỗi push và pull request.

## Kiểm tra nhanh

```bash
./scripts/check-profile.sh
```

Lệnh kiểm tra không cần Arch Linux. Để tạo và kiểm thử ISO vẫn cần máy Archiso (hoặc máy ảo Arch Linux). Nên boot thử ISO với từng GPU trước khi phát hành.
