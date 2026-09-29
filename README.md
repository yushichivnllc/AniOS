# AniOS

AniOS là **Live USB/DVD Arch Linux** hướng tới chơi game trên máy tính phòng net: khởi động vào Hyprland với kernel `linux-zen`, cài sẵn Steam và driver đồ họa mã nguồn mở phổ biến cho Intel/AMD. Hệ thống cài sẵn toàn bộ dotfile của desktop [Immaterial Impulse](https://github.com/XephyLon/immaterial-impulse) (XephyLon) hoàn toàn offline, hỗ trợ song song 2 chế độ giao diện: **AniOS Minimal (Waybar)** và **Immaterial Impulse (Quickshell)**.

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

Tuỳ chọn hữu ích:

```bash
# Dựng sạch, bỏ mọi tàn dư của lần dựng trước trong work/
sudo ./scripts/build-iso.sh --clean

# Bỏ qua bước kiểm tra profile (chỉ dùng khi đã hiểu rõ lý do)
sudo ./scripts/build-iso.sh --skip-checks
```

### Lỗi `failed to commit transaction (conflicting files)`

Nếu bản dựng dừng với thông báo dạng:

```text
error: failed to commit transaction (conflicting files)
pipewire-alsa: .../work/x86_64/airootfs/etc/alsa/conf.d/99-pipewire-default.conf exists in filesystem
Errors occurred, no packages were upgraded.
==> ERROR: Failed to install packages to new root
```

thì nguyên nhân là `profile/airootfs/` đang chứa file nằm ở **đường dẫn mà một gói pacman sở hữu**. `mkarchiso` chép overlay vào `work/<arch>/airootfs` *trước* khi `pacstrap` cài gói, nên pacman từ chối ghi đè file không thuộc gói nào và huỷ toàn bộ transaction. Cách sửa:

- **Đổi tên file** sang đường dẫn không gói nào sở hữu, ví dụ `etc/alsa/conf.d/99-anios-pipewire.conf` thay vì `etc/alsa/conf.d/99-pipewire-default.conf`.
- **Hoặc bỏ hẳn file** nếu gói đã cung cấp sẵn: ALSA trỏ về PipeWire là do gói `pipewire-alsa` tự cài `/etc/alsa/conf.d/99-pipewire-default.conf` (và `pipewire-audio` cài `/etc/alsa/conf.d/50-pipewire.conf`), nên chỉ cần hai gói đó có trong `profile/packages.x86_64`.
- Nếu file là **tàn dư của lần dựng trước** trong `work/` được dùng lại, dựng sạch bằng `sudo ./scripts/build-iso.sh --clean` (hoặc `sudo rm -rf work`). `build-iso.sh` cũng tự dọn những đường dẫn đã biết là xung đột.

Ngoại lệ: `/etc/passwd`, `/etc/shadow`, `/etc/issue`... là file "backup" của gói `filesystem` nên pacman cho phép overlay ghi đè — chính archiso dựa vào đó để tạo tài khoản live. `scripts/check-profile.sh` chặn trước nhóm lỗi này cho các đường dẫn đã biết, và `build-iso.sh` in chẩn đoán kèm log `work/mkarchiso.log` khi bản dựng hỏng.

### CI báo `THIẾU etc/alsa/conf.d/...` dù gói đã cài file đó

Nếu bước **Kiểm tra âm thanh trong ảnh live** in ra:

```text
  THIẾU etc/alsa/conf.d/50-pipewire.conf
  THIẾU etc/alsa/conf.d/99-pipewire-default.conf
##[error]Ảnh live thiếu thành phần âm thanh
```

thì vấn đề thường nằm ở **cách đọc squashfs**, không phải ở ảnh live. Hai file đó **có** trong ảnh nhưng là **symlink tuyệt đối**: PKGBUILD của `pipewire` cài chúng bằng `ln -st`, nên

```text
/etc/alsa/conf.d/99-pipewire-default.conf -> /usr/share/alsa/alsa.conf.d/99-pipewire-default.conf   (gói pipewire-alsa)
/etc/alsa/conf.d/50-pipewire.conf         -> /usr/share/alsa/alsa.conf.d/50-pipewire.conf           (gói pipewire-audio)
```

Các symlink do `systemctl enable` tạo ra (`etc/systemd/user/*.wants/...` -> `/usr/lib/systemd/user/...`) cũng là đường dẫn tuyệt đối. Mà `unsquashfs -cat` **chỉ đi theo symlink tương đối**: gặp symlink tuyệt đối nó in `cat: <đường dẫn> failed to resolve symbolic link` và trả exit code 2 — tức "thiếu file" dù file có thật.

Cách sửa: đọc ảnh live bằng `scripts/check-live-audio.sh`. `unsquashfs` từ chối symlink tuyệt đối ở **cả** `-cat` **lẫn** `-d` khi symlink là thành phần cuối của đường dẫn, nhưng trích **cả thư mục** thì symlink bên trong được giữ nguyên — nên script trích thư mục cha (`etc/alsa/conf.d`, `etc/systemd/user/*.wants`...), lấy đích bằng `readlink`, rồi trích tiếp file đích. Nhờ vậy cả symlink tuyệt đối lẫn file thật đều đọc được. Bài tự kiểm tra `scripts/selftest-check-live-audio.sh` dựng một ảnh live giả có đúng bố cục symlink đó và chạy trong workflow `AniOS profile checks`, nên lỗi kiểu này bị bắt trong vài giây thay vì sau một lượt dựng ISO hàng chục phút.

## Dựng ISO tự động bằng GitHub Actions

Workflow `.github/workflows/build-iso.yml` dựng ISO trên runner Ubuntu bằng cách chạy trực tiếp container Docker `archlinux:base-devel`, rồi gọi đúng `scripts/build-iso.sh` nên kết quả giống hệt khi dựng tay. Mỗi lượt chạy tự giải phóng dung lượng đĩa của runner, cài `archiso`, kiểm tra profile, dựng ISO, rồi tự kiểm tra kết quả (checksum SHA256, boot record El Torito cho BIOS/UEFI, đúng kernel `linux-zen`, đọc thẳng `airootfs.sfs` để xác nhận tên AniOS, wallpaper, theme SDDM Wuthering Waves, cấu hình desktop, và giao dàn âm thanh PipeWire cho `scripts/check-live-audio.sh` kiểm tra) trước khi lưu lại. Nếu một bước hỏng, lượt chạy đỏ và không có artifact.

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
- **Dotfile cài sẵn**: tài khoản live và hệ thống được thiết lập sẵn bộ dotfile hoàn chỉnh gồm cấu hình shell Bash (`~/.bashrc` với prompt màu AniOS, alias thông dụng `ll`, `fetch`, `update`), Fish shell (`~/.config/fish/config.fish`), Kitty terminal (`~/.config/kitty/kitty.conf`), HUD chơi game MangoHud (`~/.config/MangoHud/MangoHud.conf`, bật tắt bằng `Shift_R+F12`), GameMode (`~/.config/gamemode.ini`), Fastfetch (`~/.config/fastfetch/config.jsonc`), Git, Vim và Nano. Đặc biệt, hệ thống **tích hợp sẵn toàn bộ dotfile Immaterial Impulse** (XephyLon) hoàn toàn offline: toàn bộ desktop Quickshell Material 3 (`~/.config/quickshell/imi`), Matugen dynamic theming (`~/.config/matugen`), Kvantum Qt theming (`~/.config/Kvantum`), màn hình phiên và menu đăng xuất tích hợp trong Quickshell, Starship prompt (`~/.config/starship.toml`), Tmux (`~/.config/tmux`), MPV, cấu hình cờ Chrome/Code/Thorium và icon chính chủ.
- **Cắm USB/ổ cứng ngoài**: udisks2 + gvfs tự mount, ổ hiện trong Thunar và trên thanh trạng thái, hỗ trợ NTFS/exFAT/FAT32.
- **Âm thanh**: PipeWire + WirePlumber (thêm `pipewire-audio`, `alsa-utils` và `rtkit`). Ảnh live **tự bật sẵn** dàn âm thanh chứ không trông chờ vào việc các gói tự `systemctl --global enable` lúc pacstrap:
  - `profile/airootfs/etc/systemd/user/default.target.d/10-anios-audio.conf` nạp `pipewire.service`, `pipewire-pulse.service`, `wireplumber.service` và `anios-audio-setup.service` vào phiên, kèm các symlink trong `default.target.wants/`, `sockets.target.wants/` và `pipewire.service.wants/` (đúng trạng thái mà `systemctl --user enable` tạo ra). Thiếu những thứ này thì **phiên live câm hoàn toàn**: không ứng dụng nào thấy thiết bị âm thanh, Waybar không hiện âm lượng.
  - `anios-audio-setup` chạy khi vào phiên (cả từ unit người dùng lẫn từ `hyprland.lua`): bật các unit, chạy thẳng `pipewire`/`wireplumber`/`pipewire-pulse` nếu phiên không có `systemd --user`, khởi động lại dàn âm thanh khi có card mà không có thiết bị xuất nào, và ở **lần vào desktop đầu tiên sau khi khởi động** tự bỏ trạng thái tắt tiếng/âm lượng 0% do BIOS để lại trên thiết bị xuất mặc định (đặt 50%). Các phiên sau tôn trọng lựa chọn của người dùng vì thư mục home của tài khoản live được làm mới ở mỗi lần boot. Cảnh báo hiện trên desktop bằng `hyprctl notify`.
  - `anios-audio-check` (phím tắt `Super+Shift+A`, hoặc gõ lệnh trong Foot) in ra card ALSA, trạng thái từng unit, máy chủ pulse, danh sách thiết bị xuất và mức âm lượng, phát thử một tiếng bíp, rồi gợi ý cách sửa. Khi thiết bị xuất mặc định là HDMI/DisplayPort mà máy vẫn còn cổng analog, cảnh báo kèm đúng lệnh `wpctl set-default …` để chuyển về loa/jack 3.5mm — kiểu "không có tiếng" phổ biến nhất ở máy phòng net. Nhật ký: `$XDG_RUNTIME_DIR/anios-audio-setup.log`.
  - Muốn dựng lại dàn âm thanh bằng tay: `anios-audio-setup --force`; chọn thiết bị xuất bằng `pavucontrol`; kiểm tra kênh phần cứng đang `[off]` bằng `alsamixer`.
- Mở Steam từ launcher. Steam cần Internet và tài khoản Steam. Có thể thử GameMode bằng cách thêm `gamemoderun %command%` vào Steam → Properties → Launch Options của game. Steam và mọi thứ bạn tải trong phiên chỉ nằm trong RAM/overlay tạm: hãy copy file cần giữ ra ổ ngoài trước khi tắt máy, hoặc cài hệ thống vào ổ đĩa nếu sử dụng thường xuyên.
- Phím tắt: `Super+Return` mở Foot; `Super+D` mở launcher; `Super+Shift+A` mở công cụ kiểm tra âm thanh; `Super+Shift+L` khoá màn hình; `Ctrl+Alt+F2` mở TTY cứu hộ (ở đó `fastfetch` in thông tin máy); `Super+Shift+E` thoát phiên Hyprland.
- **Màn hình khoá dùng mật khẩu**, không phải cơ chế bảo mật mạnh: nhập `1111` để mở khoá. Tài khoản live và `sudo` dùng cùng mật khẩu; mật khẩu này được tạo sẵn trong ảnh từ lúc build (pacman hook `anios-live-user.hook` viết hash vào `/etc/shadow`) và được `anios-live-home.service` đặt lại ở mỗi lần khởi động như dự phòng. Vì vậy đừng để dữ liệu quan trọng trong phiên live.
- Nếu thoát phiên bằng `Super+Shift+E`, SDDM sẽ hiện theme **Wuthering Waves** của Qylock; chọn phiên **AniOS (Hyprland)** rồi nhập `1111` để vào lại. Theme hiện khung nền tĩnh ngay, rồi mới khởi tạo video sau 1,2 giây; nếu thiếu codec video thì khung tĩnh vẫn giữ cho màn hình đăng nhập dùng được. Các lỗi không vào được SDDM đã được xử lý triệt để: tắt tiến trình agetty autologin tty1 của releng để tránh tranh chấp VT, chuẩn hoá UID 1000 và nhóm quyền phần cứng (wheel, video, audio, input, seat) cho tài khoản `anios`, sửa liên kết dịch vụ chuẩn bị thư mục người dùng (`anios-live-home.service`), cấu hình `MinimumUid=500` cho SDDM, bổ sung fallback tài khoản tự động trong theme, và "nướng" mật khẩu `1111` vào `/etc/shadow` từ lúc build bằng pacman hook để đăng nhập thủ công SDDM (stack PAM `sddm` → `pam_unix`) không phụ thuộc vào việc service lúc khởi động có chạy thành công hay không — autologin thì luôn qua được vì dùng stack `sddm-autologin` (kết thúc bằng `pam_permit`).
- Desktop mặc định tắt blur và animation để giảm tải GPU. `Super+Space` bật/tắt chế độ cửa sổ nổi.
- **Cấu hình Hyprland** nằm ở `~/.config/hypr/hyprland.lua` (bản sao gốc trong ảnh: `/usr/share/anios/skel/.config/hypr/hyprland.lua`): từ Hyprland 0.55 cấu hình viết bằng Lua thay cho `hyprland.conf` cũ, nên sau khi sửa chỉ cần `Super+Shift+R` để nạp lại. Màn hình khoá dùng định dạng riêng của hyprlock (`~/.config/hypr/hyprlock.conf`).

## Giao diện Immaterial Impulse và Dual Session

Toàn bộ dotfile và thành phần của **Immaterial Impulse** (XephyLon) đã được **cài sẵn trong ảnh ISO** (offline 100%, không cần kết nối mạng hay build gói). Người dùng có 2 cách trải nghiệm:

1. **Chọn phiên tại màn hình đăng nhập SDDM**:
   - `AniOS (Hyprland - Minimal)`: Phiên bản nhẹ mặc định với Waybar + Mako + Fuzzel, tiết kiệm tài nguyên cho GPU yếu hoặc máy quán net đời cũ.
   - `AniOS (Immaterial Impulse)`: Phiên bản đầy đủ tính năng với Quickshell, widget Material 3, Matugen tự đổi màu theo hình nền và phím tắt thông minh.

2. **Chuyển đổi giao diện trực tiếp trong desktop (không cần khởi động lại máy)**:
   - Sử dụng lệnh:
     ```bash
     anios-switch-desktop imi       # Chuyển sang Immaterial Impulse (Quickshell)
     anios-switch-desktop minimal   # Chuyển về AniOS Minimal (Waybar)
     anios-switch-desktop toggle    # Đổi qua lại giữa 2 giao diện
     ```
   - Hoặc phím tắt: `Super+Alt+M`.
   - Hoặc nhấp đúp vào biểu tượng **Switch to Immaterial Impulse** / **Switch to AniOS Minimal** trên màn hình Desktop.
   - Script `anios-setup` cung cấp menu tương tác nhanh để chuyển đổi hoặc khôi phục dotfile gốc từ `/usr/share/anios/skel`.

## Phần cứng và hiệu năng

- AniOS nhắm đến máy **x86_64**. Không hệ điều hành nào có thể bảo đảm game tương thích hoặc chạy nhanh trên mọi cấu hình; hiệu năng tùy thuộc CPU, GPU, RAM, tản nhiệt, trò chơi và driver. `linux-zen` được chọn để ưu tiên độ phản hồi, **không bảo đảm FPS cao hơn**.
- ISO có Mesa/OpenGL/Vulkan cho Intel và AMD, cùng các thư viện 32-bit Steam và XWayland để game chỉ có bản X11 vẫn chạy trong phiên Hyprland. Driver NVIDIA proprietary không được cài sẵn; các card NVIDIA đời cũ có thể cần driver và cấu hình kernel riêng. Hãy kiểm tra từng model GPU trước khi triển khai cho quán net.
- Hyprland là compositor Wayland. GPU quá cũ, không có DRM/KMS hoạt động tốt có thể không phù hợp. Nếu giao diện đồ họa không chạy, chuyển TTY khác bằng `Ctrl+Alt+F2` và xem `journalctl -b -u sddm` hoặc `~/.local/share/hyprland/hyprland.log`.
- Hệ thống Live chạy từ ảnh nén trong RAM (zram là swap nén, `vm.swappiness=100` để giảm nghẽn khi mở nhiều game) và không phải trình cài đặt vào ổ đĩa. Cần đủ RAM cho hệ thống và game; để dùng ổn định trong quán net, nên cài lên ổ đĩa và kiểm thử từng mẫu máy trước.

## Cấu trúc repository

- `profile/airootfs/` — tài khoản Live, SDDM tự đăng nhập và theme **Wuthering Waves** (Qylock) đã tinh chỉnh khởi tạo video có dự phòng, phiên Hyprland (cấu hình Lua `hyprland.lua` + `hyprlock.conf` hỗ trợ song song Minimal và Immaterial Impulse), Quickshell, Waybar, Matugen, dotfile cài sẵn, ibus & fcitx5, công cụ chuyển đổi giao diện (`usr/local/bin/anios-switch-desktop`), dàn âm thanh tự khởi động (`etc/systemd/user/`, `usr/local/bin/anios-audio-setup`, `usr/local/bin/anios-audio-check`), mạng và cấu hình phiên, kèm pacman hook (`etc/pacman.d/hooks/anios-live-user.hook`) tạo sẵn tài khoản live và mật khẩu `1111` trong ảnh lúc build.
- `profile/airootfs/usr/share/sddm/themes/wuwa/` — theme Qylock Wuthering Waves, mã nguồn giấy phép GPL-3.0; thông tin upstream và commit nguồn ở `UPSTREAM`.
- `profile/airootfs/etc/os-release` — tên AniOS hiển thị cho người dùng, `ID=arch` để giữ tương thích công cụ Arch.
- `profile/branding/` — wallpaper và splash menu khởi động; dựng lại bằng `./scripts/make-branding-assets.sh` (cần ImageMagick).
- `profile/packages.x86_64` — các gói desktop, kernel, game, firmware, ibus-unikey và tiện ích bổ sung vào Archiso `releng`.
- `scripts/build-iso.sh` — dựng profile Archiso tạm thời (kernel `linux-zen`, ảnh thương hiệu, gỡ bỏ xung đột agetty tty1, sao chép dotfile cho tài khoản live) và chạy `mkarchiso`.
- `scripts/check-profile.sh` — kiểm tra cấu trúc profile, danh sách gói, định danh AniOS, dotfile, cấu hình âm thanh (drop-in + symlink bật sẵn) và cú pháp script ngoại tuyến.
- `scripts/check-live-audio.sh` — kiểm tra dàn âm thanh ngay trong `airootfs.sfs` vừa dựng (tự đi theo symlink tuyệt đối, vì `unsquashfs -cat` không đọc được loại symlink đó).
- `scripts/selftest-check-live-audio.sh` — tự kiểm tra script trên một ảnh live giả, chạy trên mọi push/PR mà không cần Arch Linux.
- `.github/workflows/build-iso.yml` — dựng ISO tự động, kiểm tra ảnh live (gồm dàn âm thanh PipeWire: plugin SPA ALSA, unit người dùng, cấu hình bật sẵn và công cụ chẩn đoán), xuất artifact và phát hành release.
- `.github/workflows/profile-check.yml` — kiểm tra nhanh profile trên mỗi push và pull request.

## Kiểm tra nhanh

```bash
./scripts/check-profile.sh
./scripts/selftest-check-live-audio.sh   # kiểm tra logic đọc ảnh live (cần bash, không cần Arch)
```

Lệnh kiểm tra không cần Arch Linux. Để tạo và kiểm thử ISO vẫn cần máy Archiso (hoặc máy ảo Arch Linux). Nên boot thử ISO với từng GPU trước khi phát hành.
