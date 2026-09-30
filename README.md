# AniOS

AniOS là **Live USB/DVD Arch Linux** hướng tới chơi game trên máy tính phòng net: khởi động vào Hyprland với kernel `linux-zen`, cài sẵn Steam, driver đồ họa mã nguồn mở phổ biến cho Intel/AMD, trình duyệt Cốc Cốc, Wine, Python, Node.js, Java và trợ lý AUR `yay` để cài thêm gói ngay trong phiên live. Hệ thống cài sẵn toàn bộ dotfile của desktop [Immaterial Impulse](https://github.com/XephyLon/immaterial-impulse) (XephyLon) hoàn toàn offline, hỗ trợ song song 2 chế độ giao diện: **AniOS Minimal (Waybar)** và **Immaterial Impulse (Quickshell)**.

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

Script dùng profile `releng` của Archiso đang cài trên máy, đổi kernel sang `linux-zen` trong mọi mục menu (Syslinux, GRUB, systemd-boot, loopback), dán ảnh thương hiệu AniOS vào `syslinux/splash.png` và `usr/share/anios/wallpaper.png`, bật kho `multilib` chính thức để cài Steam, rồi thêm cấu hình AniOS. Cần Internet để tải các gói Arch (và cả gói AUR, xem [bên dưới](#gói-aur-cài-sẵn-trong-ảnh)). ISO hoàn chỉnh nặng khoảng **4–4,5 GB**; nên dùng USB ít nhất **16 GB**, chừa khoảng **25 GiB** đĩa trống cho `work/` (phần lớn là thư mục dựng gói AUR và cache pacman, đều bị dọn trước khi đóng ảnh), và kiểm tra ISO trước khi phát hành.

Tuỳ chọn hữu ích:

```bash
# Dựng sạch, bỏ mọi tàn dư của lần dựng trước trong work/
sudo ./scripts/build-iso.sh --clean

# Bỏ qua bước kiểm tra profile (chỉ dùng khi đã hiểu rõ lý do)
sudo ./scripts/build-iso.sh --skip-checks

# Dựng nhanh, KHÔNG nướng gói AUR vào ảnh (ảnh sẽ không có yay/Cốc Cốc/Legacy Launcher)
sudo ./scripts/build-iso.sh --no-aur
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

thì gần như chắc chắn vấn đề nằm ở **cách đọc squashfs**, không phải ở ảnh live. Hai file đó **có** trong ảnh nhưng là **symlink tuyệt đối**: PKGBUILD của `pipewire` cài chúng bằng `ln -st`, nên

```text
/etc/alsa/conf.d/99-pipewire-default.conf -> /usr/share/alsa/alsa.conf.d/99-pipewire-default.conf   (gói pipewire-alsa)
/etc/alsa/conf.d/50-pipewire.conf         -> /usr/share/alsa/alsa.conf.d/50-pipewire.conf           (gói pipewire-audio)
```

Các symlink do `systemctl enable` tạo ra (`etc/systemd/user/*.wants/...` -> `/usr/lib/systemd/user/...`) cũng là đường dẫn tuyệt đối. `unsquashfs -cat` **chỉ đi theo symlink tương đối**: gặp symlink tuyệt đối nó in `cat: <đường dẫn> failed to resolve symbolic link` và trả exit code 2 — nên đừng dùng `-cat` để đọc những file này.

`unsquashfs -d` thì **trích chính cái symlink** (không đi theo, không cần thêm cờ nào), nhưng chỉ tha cho **thư mục đích gốc** đã tồn tại sẵn: mọi thư mục khác trên đường dẫn mà có sẵn thì nó chết ngay với

```text
FATAL ERROR: dir_scan: failed to make directory <đường dẫn>, because File exists
```

(unsquashfs.c, `dir_scan()`: từng thư mục được tạo bằng `mkdir(2)` và `EEXIST` bị coi là lỗi, chỉ `depth == 1` mới được bỏ qua — trừ khi chạy `-force`.) Vì bản cũ trích **mọi thứ vào chung một** `$EXTRACT_DIR`, từ lần trích thứ hai trở đi unsquashfs hỏng và script báo `THIẾU` cho mọi đường dẫn còn lại — kể cả file có thật. Bản cũ còn tự chặn mọi thư mục quá 500 entry (để khỏi phải trích thư mục cha mà nhìn symlink), nên `usr/bin` — nơi có hàng nghìn binary trong ảnh live — bị bỏ qua và mọi binary trong đó cũng bị báo thiếu.

Cách sửa: đọc ảnh live bằng `scripts/check-live-audio.sh`. Script lấy loại entry và đích symlink từ `unsquashfs -ll` (chỉ đọc metadata, **không trích gì** và không đi theo symlink, nên thư mục cha to cỡ nào cũng không ảnh hưởng), rồi trích **đúng entry** cần đọc vào một thư mục đích **mới toanh** cho mỗi lần trích — nhờ vậy không bao giờ gặp lại lỗi `File exists`. Bài tự kiểm tra `scripts/selftest-check-live-audio.sh` dựng một ảnh live giả có đúng bố cục symlink đó, một `usr/bin` khổng lồ và lỗi `File exists` của `unsquashfs`, rồi chạy trong workflow `AniOS profile checks` — nên lỗi kiểu này bị bắt trong vài giây thay vì sau một lượt dựng ISO hàng chục phút.

## Gói AUR cài sẵn trong ảnh

`pacstrap` chỉ giải quyết được gói trong kho chính thức của Arch, nên gói AUR **không thể** nằm trong
`profile/packages.x86_64`. AniOS vì thế có một đường riêng: `profile/packages.aur.x86_64` liệt kê gói AUR
cần nướng vào ảnh, còn `scripts/anios-aur-build.sh` dựng và cài chúng **bên trong chroot** — sau khi
pacstrap cài xong và trước khi `mkarchiso` sinh `pkglist.x86_64.txt`, nên gói AUR hiện diện đầy đủ trong
database pacman của ảnh lẫn trong danh sách gói trên ISO.

| Gói AUR | Trong ảnh để làm gì |
| --- | --- |
| `yay` | trợ lý AUR cho phiên live: tìm, cài và cập nhật cả kho chính thức lẫn AUR (`yay -Syu`) |
| `coccoc-browser-stable` | trình duyệt Cốc Cốc tiếng Việt (Chromium, tải media tốt); phụ thuộc `qt5-base`, `ttf-liberation` |
| `legacy-launcher` | launcher Minecraft bản classic (llaun.ch); chạy bằng Java, cần `jre-openjdk` |

Cùng đợt này, `packages.x86_64` có thêm `python`, `python-pip`, `nodejs`, `npm`, `wine`, `winetricks`,
`base-devel`, `git`, `jre-openjdk`, `qt5-base` và `ttf-liberation` — nhóm gói từ kho chính thức mà người
dùng phòng net hay phải tự cài.

Cách bước dựng AUR hoạt động:

- `build-iso.sh` chép manifest và script dựng vào `airootfs/root/.anios-aur/`, sinh
  `airootfs/root/customize_airootfs.sh` (hook mà `mkarchiso` chạy bằng `env -u TMPDIR arch-chroot` rồi tự
  xoá), và chạy hook đó qua `bash` vì overlay chép vào airootfs làm mất bit thực thi.
- Trong chroot, tài khoản tạm `aniosbuild` (UID 1412) dựng gói bằng `makepkg` với quyền đã hạ bằng
  `runuser`/`setpriv`; thư mục dựng nằm ở `/var/tmp/anios-aur-build`. Root chỉ cài phụ thuộc
  (`pacman -S --asdeps`), cài gói hoàn chỉnh (`pacman -U --asexplicit` để không bị dọn như mồ côi), rồi
  gỡ **đúng** những phụ thuộc mồ côi do bước này tạo ra. `makepkg` không bao giờ chạy dưới quyền root, và
  **không có** luật `sudoers`/`NOPASSWD` nào được thêm vào ảnh.
- `go` chỉ là makedepend tạm thời của `yay`: nó nằm trong `BUILD_TOOLS=(base-devel git)` được cài trong
  chroot rồi bị dọn cùng nhóm mồ côi, **không** nằm trong `packages.x86_64` và không có trong ISO cuối cùng.
- Cố tình **không** dùng `pacman -Sy` ở đường thường: pacstrap vừa điền sync DB nên cài thẳng bằng DB đó
  giữ cho cả ảnh ở **một snapshot kho**, tránh trạng thái "partial upgrade". Chỉ khi DB sẵn có không cài
  được mới đồng bộ lại kho + keyring rồi thử lần hai.
- Một gói AUR dựng hỏng sẽ **làm dừng bản dựng** (kèm gợi ý `--no-aur`) chứ không âm thầm bỏ qua; tên gói
  không hợp lệ bị chặn trước khi tải; mỗi gói có thể tự thử lại (`ANIOS_AUR_RETRIES`); nhật ký đầy đủ ở
  `/var/tmp/anios-aur-build/anios-aur-build.log` trong lúc dựng (`ANIOS_AUR_KEEP_TMP=1` để giữ lại).
- Ảnh cuối cùng có `/usr/share/anios/aur-packages.txt` ghi `tên_gói=phiên_bản` cho từng gói AUR đã cài, để
  đối chiếu về sau.

Kiểm tra ảnh vừa dựng:

```bash
# Đối chiếu ngay trong squashfs: gói AUR + python/nodejs/wine, và không còn tàn dư của bước dựng
./scripts/check-live-aur.sh work/x86_64/airootfs.sfs out/anios-pkglist.txt
```

`scripts/check-live-aur.sh` đọc `airootfs.sfs` bằng `unsquashfs -ll`/`-cat` (theo đúng cách đọc symlink
mô tả ở phần [troubleshooting](#ci-báo-thiếu-etcalsaconfd-dù-gói-đã-cài-file-đó)) và xác nhận: binary của
từng gói (`usr/bin/yay`, `python3`, `node`, `npm`, `wine`, `winetricks`, `java`, `makepkg`, `git`) có trong
ảnh; database pacman trong ảnh (`var/lib/pacman/local/<gói>-<phiên bản>-<arch>`) ghi nhận từng gói — đây là
điều kiện để `yay`/`pacman` trong phiên live nhận ra chúng; `pkglist.x86_64` cũng liệt kê chúng; và
**không** còn tàn dư nào của bước dựng (`root/.anios-aur`, `root/customize_airootfs.sh`,
`var/tmp/anios-aur-build`, `home/aniosbuild`, dòng `aniosbuild` trong `/etc/passwd`, luật `NOPASSWD` trong
`etc/sudoers.d`). Hai bài tự kiểm tra `scripts/selftest-anios-aur-build.sh` và
`scripts/selftest-check-live-aur.sh` dựng sandbox giả để bắt lỗi kiểu này trong vài giây, chạy trên mọi
push/PR mà không cần Arch Linux.

## Dựng ISO tự động bằng GitHub Actions

Workflow `.github/workflows/build-iso.yml` dựng ISO trên runner Ubuntu bằng cách chạy trực tiếp container Docker `archlinux:base-devel`, rồi gọi đúng `scripts/build-iso.sh` nên kết quả giống hệt khi dựng tay. Mỗi lượt chạy tự giải phóng dung lượng đĩa của runner, cài `archiso`, kiểm tra profile, dựng ISO, rồi tự kiểm tra kết quả (checksum SHA256, boot record El Torito cho BIOS/UEFI, đúng kernel `linux-zen`, đọc thẳng `airootfs.sfs` để xác nhận tên AniOS, wallpaper, theme SDDM Wuthering Waves, cấu hình desktop, giao dàn âm thanh PipeWire cho `scripts/check-live-audio.sh`, và giao gói AUR cùng `python`/`nodejs`/`wine` cho `scripts/check-live-aur.sh` kiểm tra) trước khi lưu lại. Nếu một bước hỏng, lượt chạy đỏ và không có artifact.

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

Lưu ý: mỗi lượt dựng mất khoảng 45–150 phút (workflow đặt trần 180 phút) và vài chục GB dung lượng đĩa tuỳ tốc độ tải gói Arch; bước dựng gói AUR cộng thêm thời gian vì `yay` được biên dịch từ mã nguồn. Muốn dựng khi có push vào nhánh chính, thêm `branches: [main]` vào mục `push` của workflow (dưới `tags:`). ISO do CI dựng vẫn nên boot thử trên máy thật, đặc biệt với từng model GPU, trước khi đưa vào quán.

## Sử dụng phiên Live

- SDDM tự đăng nhập vào tài khoản Live tạm `anios` và khởi chạy phiên AniOS trên Hyprland. Mật khẩu tài khoản Live và `sudo` đều là `1111`; đây là mật khẩu cố ý đơn giản cho môi trường live tạm thời, **không dùng phiên này với dữ liệu riêng tư hoặc trên mạng không đáng tin cậy**.
- Kết nối Wi-Fi bằng biểu tượng mạng trên thanh trạng thái hoặc lệnh `nmtui`; kết nối dây do NetworkManager quản lý.
- **Gõ tiếng Việt**: cài sẵn cả **ibus (ibus-unikey)** và **fcitx5 (fcitx5-unikey)**. Mặc định phiên khởi động với fcitx5, nhấn `Ctrl+Space` để bật/tắt tiếng Việt (Telex). Người dùng có thể dễ dàng chuyển đổi qua lại giữa IBus và Fcitx5 bất kỳ lúc nào bằng lệnh `anios-switch-im ibus` hoặc `anios-switch-im fcitx5`.
- **Dotfile cài sẵn**: tài khoản live và hệ thống được thiết lập sẵn bộ dotfile hoàn chỉnh gồm cấu hình shell Bash (`~/.bashrc` với prompt màu AniOS, alias thông dụng `ll`, `fetch`, `update`, `update-aur`), Fish shell (`~/.config/fish/config.fish`, cùng bộ alias), Kitty terminal (`~/.config/kitty/kitty.conf`), HUD chơi game MangoHud (`~/.config/MangoHud/MangoHud.conf`, bật tắt bằng `Shift_R+F12`), GameMode (`~/.config/gamemode.ini`), Fastfetch (`~/.config/fastfetch/config.jsonc`), Git, Vim và Nano. Đặc biệt, hệ thống **tích hợp sẵn toàn bộ dotfile Immaterial Impulse** (XephyLon) hoàn toàn offline: toàn bộ desktop Quickshell Material 3 (`~/.config/quickshell/imi`), Matugen dynamic theming (`~/.config/matugen`), Kvantum Qt theming (`~/.config/Kvantum`), màn hình phiên và menu đăng xuất tích hợp trong Quickshell, Starship prompt (`~/.config/starship.toml`), Tmux (`~/.config/tmux`), MPV, cấu hình cờ Chrome/Code/Thorium và icon chính chủ.
- **Cắm USB/ổ cứng ngoài**: udisks2 + gvfs tự mount, ổ hiện trong Thunar và trên thanh trạng thái, hỗ trợ NTFS/exFAT/FAT32.
- **Âm thanh**: PipeWire + WirePlumber (thêm `pipewire-audio`, `alsa-utils` và `rtkit`). Ảnh live **tự bật sẵn** dàn âm thanh chứ không trông chờ vào việc các gói tự `systemctl --global enable` lúc pacstrap:
  - `profile/airootfs/etc/systemd/user/default.target.d/10-anios-audio.conf` nạp `pipewire.service`, `pipewire-pulse.service`, `wireplumber.service` và `anios-audio-setup.service` vào phiên, kèm các symlink trong `default.target.wants/`, `sockets.target.wants/` và `pipewire.service.wants/` (đúng trạng thái mà `systemctl --user enable` tạo ra). Thiếu những thứ này thì **phiên live câm hoàn toàn**: không ứng dụng nào thấy thiết bị âm thanh, Waybar không hiện âm lượng.
  - `anios-audio-setup` chạy khi vào phiên (cả từ unit người dùng lẫn từ `hyprland.lua`): bật các unit, chạy thẳng `pipewire`/`wireplumber`/`pipewire-pulse` nếu phiên không có `systemd --user`, khởi động lại dàn âm thanh khi có card mà không có thiết bị xuất nào, và ở **lần vào desktop đầu tiên sau khi khởi động** tự bỏ trạng thái tắt tiếng/âm lượng 0% do BIOS để lại trên thiết bị xuất mặc định (đặt 50%). Các phiên sau tôn trọng lựa chọn của người dùng vì thư mục home của tài khoản live được làm mới ở mỗi lần boot. Cảnh báo hiện trên desktop bằng `hyprctl notify`.
  - `anios-audio-check` (phím tắt `Super+Shift+A`, hoặc gõ lệnh trong Foot) in ra card ALSA, trạng thái từng unit, máy chủ pulse, danh sách thiết bị xuất và mức âm lượng, phát thử một tiếng bíp, rồi gợi ý cách sửa. Khi thiết bị xuất mặc định là HDMI/DisplayPort mà máy vẫn còn cổng analog, cảnh báo kèm đúng lệnh `wpctl set-default …` để chuyển về loa/jack 3.5mm — kiểu "không có tiếng" phổ biến nhất ở máy phòng net. Nhật ký: `$XDG_RUNTIME_DIR/anios-audio-setup.log`.
  - Muốn dựng lại dàn âm thanh bằng tay: `anios-audio-setup --force`; chọn thiết bị xuất bằng `pavucontrol`; kiểm tra kênh phần cứng đang `[off]` bằng `alsamixer`.
- **Cài thêm phần mềm ngay trong phiên live**: `yay` đã có sẵn trong ảnh nên dùng được cả kho chính thức lẫn AUR — `yay -S <tên gói>` để cài (tự hỏi mật khẩu `sudo`), `yay -Syu` (hoặc alias `update-aur`) để cập nhật toàn bộ, `yay -Ss <từ khoá>` (alias `aur-search`) để tìm. Vì đây là phiên live nên mọi gói cài thêm chỉ tồn tại tới khi tắt máy, và gói phải biên dịch sẽ ngốn RAM/đĩa tạm của phiên — máy ít RAM nên ưu tiên gói `-bin`.
- **Cốc Cốc Browser** (`coccoc-browser-stable`) cài sẵn cho ai cần trình duyệt tiếng Việt, tải media từ trang nội địa tốt; chạy qua XWayland trong phiên Hyprland, thêm `--ozone-platform-hint=auto` nếu muốn thử Wayland native.
- **Phần mềm Windows**: `wine` + `winetricks` cài sẵn (kho `multilib` được bật từ lúc dựng nên phần 32-bit đầy đủ). Chạy `wine <file.exe>`; lần đầu Wine có thể đề nghị tải thêm Gecko/Mono. Game Windows nên ưu tiên qua Steam/Proton.
- **Lập trình**: `python` + `pip`, `nodejs` + `npm` và Java (`jre-openjdk`) có sẵn; `base-devel` + `git` cũng nằm trong ảnh để `yay` tự dựng được gói AUR ngay trong phiên.
- **Minecraft**: `legacy-launcher` (bản classic của llaun.ch) cài sẵn, mở từ launcher; cần Java (đã có) và tài khoản Minecraft hợp lệ.
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
- Ảnh live nay nặng hơn (thêm Cốc Cốc, Wine, Node.js, Java và `base-devel`), nên máy quán net RAM 4 GB sẽ chật khi vừa chạy game vừa mở trình duyệt; 8 GB trở lên là mức nên có.
- Hệ thống Live chạy từ ảnh nén trong RAM (zram là swap nén, `vm.swappiness=100` để giảm nghẽn khi mở nhiều game) và không phải trình cài đặt vào ổ đĩa. Cần đủ RAM cho hệ thống và game; để dùng ổn định trong quán net, nên cài lên ổ đĩa và kiểm thử từng mẫu máy trước.

## Cấu trúc repository

- `profile/airootfs/` — tài khoản Live, SDDM tự đăng nhập và theme **Wuthering Waves** (Qylock) đã tinh chỉnh khởi tạo video có dự phòng, phiên Hyprland (cấu hình Lua `hyprland.lua` + `hyprlock.conf` hỗ trợ song song Minimal và Immaterial Impulse), Quickshell, Waybar, Matugen, dotfile cài sẵn, ibus & fcitx5, công cụ chuyển đổi giao diện (`usr/local/bin/anios-switch-desktop`), dàn âm thanh tự khởi động (`etc/systemd/user/`, `usr/local/bin/anios-audio-setup`, `usr/local/bin/anios-audio-check`), mạng và cấu hình phiên, kèm pacman hook (`etc/pacman.d/hooks/anios-live-user.hook`) tạo sẵn tài khoản live và mật khẩu `1111` trong ảnh lúc build.
- `profile/airootfs/usr/share/sddm/themes/wuwa/` — theme Qylock Wuthering Waves, mã nguồn giấy phép GPL-3.0; thông tin upstream và commit nguồn ở `UPSTREAM`.
- `profile/airootfs/etc/os-release` — tên AniOS hiển thị cho người dùng, `ID=arch` để giữ tương thích công cụ Arch.
- `profile/branding/` — wallpaper và splash menu khởi động; dựng lại bằng `./scripts/make-branding-assets.sh` (cần ImageMagick).
- `profile/packages.x86_64` — các gói desktop, kernel, game, firmware, ibus-unikey, Cốc Cốc/Wine/Python/Node.js/Java và tiện ích bổ sung vào Archiso `releng`.
- `profile/packages.aur.x86_64` — manifest gói AUR cần nướng vào ảnh (`yay`, `coccoc-browser-stable`, `legacy-launcher`); cố tình tách khỏi `packages.x86_64` vì pacstrap không phân giải được AUR.
- `scripts/build-iso.sh` — dựng profile Archiso tạm thời (kernel `linux-zen`, ảnh thương hiệu, gỡ bỏ xung đột agetty tty1, sao chép dotfile cho tài khoản live), chuẩn bị bước dựng gói AUR (`root/.anios-aur` + hook `customize_airootfs.sh`, tuỳ chọn `--no-aur` để bỏ qua), chạy `mkarchiso`, rồi tự xác nhận gói AUR có trong pacman DB của ảnh và không còn tàn dư builder.
- `scripts/anios-aur-build.sh` — chạy **trong chroot airootfs**: tải PKGBUILD từ AUR, dựng bằng `makepkg` dưới tài khoản tạm `aniosbuild` với quyền đã hạ, root cài phụ thuộc/gói và dọn mồ côi, ghi `/usr/share/anios/aur-packages.txt`.
- `scripts/check-profile.sh` — kiểm tra cấu trúc profile, danh sách gói (kể cả manifest AUR và ràng buộc của bước dựng AUR), định danh AniOS, dotfile, cấu hình âm thanh (drop-in + symlink bật sẵn), mức độ bao phủ của CI và cú pháp script ngoại tuyến.
- `scripts/check-live-aur.sh` — kiểm tra gói AUR, `python`/`nodejs`/`wine` và tàn dư builder ngay trong `airootfs.sfs` vừa dựng.
- `scripts/selftest-anios-aur-build.sh` — tự kiểm tra `anios-aur-build.sh` trên chroot giả (fake pacman/makepkg/runuser), không cần Arch Linux.
- `scripts/selftest-check-live-aur.sh` — tự kiểm tra `check-live-aur.sh` trên ảnh live giả cùng `unsquashfs` giả.
- `scripts/check-live-audio.sh` — kiểm tra dàn âm thanh ngay trong `airootfs.sfs` vừa dựng (tự đi theo symlink tuyệt đối, vì `unsquashfs -cat` không đọc được loại symlink đó).
- `scripts/selftest-check-live-audio.sh` — tự kiểm tra script trên một ảnh live giả, chạy trên mọi push/PR mà không cần Arch Linux.
- `.github/workflows/build-iso.yml` — dựng ISO tự động, kiểm tra ảnh live (gồm dàn âm thanh PipeWire: plugin SPA ALSA, unit người dùng, cấu hình bật sẵn và công cụ chẩn đoán; cùng gói AUR, `python`/`nodejs`/`wine` và tàn dư builder), xuất artifact và phát hành release.
- `.github/workflows/profile-check.yml` — kiểm tra nhanh profile trên mỗi push và pull request.

## Kiểm tra nhanh

```bash
./scripts/check-profile.sh                # cấu trúc profile, danh sách gói, manifest AUR, ràng buộc CI
./scripts/selftest-check-live-audio.sh    # logic đọc ảnh live (cần bash, không cần Arch)
./scripts/selftest-anios-aur-build.sh     # bước dựng gói AUR trong chroot giả
./scripts/selftest-check-live-aur.sh      # bước kiểm tra gói AUR/python/nodejs/wine trong ảnh giả
```

Chạy cả bốn mất khoảng 10 giây. Khi dựng ISO xong, kiểm tra thêm ngay trên ảnh thật:

```bash
./scripts/check-live-audio.sh work/x86_64/airootfs.sfs
./scripts/check-live-aur.sh  work/x86_64/airootfs.sfs out/anios-pkglist.txt
```

Lệnh kiểm tra không cần Arch Linux. Để tạo và kiểm thử ISO vẫn cần máy Archiso (hoặc máy ảo Arch Linux). Nên boot thử ISO với từng GPU trước khi phát hành.
