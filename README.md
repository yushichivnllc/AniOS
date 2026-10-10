# AniOS

AniOS là **Live USB/DVD Arch Linux** hướng tới chơi game trên máy tính phòng net: khởi động vào Hyprland với kernel `linux-zen`, cài sẵn Steam, driver đồ họa mã nguồn mở phổ biến cho Intel/AMD, trình duyệt Cốc Cốc, Wine, Python, Node.js, Java, trợ lý AUR `yay` để cài thêm gói ngay trong phiên live, cùng **stack AI cục bộ** (Ollama bản Vulkan, llama-cpp, whisper-cpp, OpenVINO và hai ứng dụng GUI Jan AI / LM Studio). Hệ thống cài sẵn toàn bộ dotfile của desktop [Immaterial Impulse](https://github.com/XephyLon/immaterial-impulse) (XephyLon) hoàn toàn offline, hỗ trợ song song 2 chế độ giao diện: **AniOS Minimal (Waybar)** và **Immaterial Impulse (Quickshell)**.

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

# Dựng nhanh, KHÔNG nướng gói AUR vào ảnh (ảnh sẽ không có Calamares/yay/Cốc Cốc/Legacy Launcher)
sudo ./scripts/build-iso.sh --no-aur
```

### Cài AniOS từ Live ISO

Trên ISO dựng mặc định (có AUR), AniOS tự đăng nhập vào desktop Live rồi mở màn hình chào mừng theo phong cách **Material Design** với hai lựa chọn **Dùng thử AniOS Live** và **Cài đặt AniOS**. Dùng thử sẽ đóng màn hình và giữ nguyên phiên hiện tại; cài đặt mở Calamares với các bước chọn ngôn ngữ/bàn phím, phân vùng, tài khoản và xác nhận trước khi cài. Cần kết nối Internet và tối thiểu 30 GB dung lượng trống.

Trong Calamares, người dùng có thể chọn:

- **Ngôn ngữ và múi giờ**: trang Region & Time mở sẵn ở **Asia/Ho_Chi_Minh** (UTC+7) nhờ `profile/installer/calamares/modules/locale.conf`, và GeoIP bị tắt để vị trí suy ra từ IP của mạng phòng net không ghi đè mặc định đó. Vẫn đổi được bằng bản đồ nếu cài ở nước khác.
- **GRUB**: giao diện **Grubphemous** từ [pvtoari/grubphemous-theme](https://github.com/pvtoari/grubphemous-theme), được giới thiệu trong [Jacksaur/Gorgeous-GRUB](https://github.com/Jacksaur/Gorgeous-GRUB), hoặc GRUB mặc định. Theme và preview được tải từ upstream ở commit đã pin lúc dựng ISO.
- **SDDM**: theme AniOS hoặc **Qylock / Wuthering Waves** từ [Darkkal44/qylock](https://github.com/Darkkal44/qylock).
- **Dotfiles Hyprland**: **Immaterial Impulse** (được đóng gói sẵn, dùng offline) hoặc [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland). Nếu chọn end-4, ở lần đăng nhập đầu tiên ứng dụng sẽ hỏi xác nhận trước khi tải revision đã pin và chạy trình cài đặt upstream dưới tài khoản người dùng; cần Internet, `sudo` và tải thêm gói.

Dựng bằng `--no-aur` vẫn vào được Live; thẻ cài đặt trong màn hình chào mừng sẽ bị vô hiệu hoá và báo rõ Calamares không có trong ảnh.

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

(unsquashfs.c, `dir_scan()`: từng thư mục được tạo bằng `mkdir(2)` và `EEXIST` bị coi là lỗi, chỉ `depth == 1` mới được bỏ qua — trừ khi chạy `-force`.) Vì bản cũ trích **mọi thứ vào chung một** `$EXTRACT_DIR` (hoặc trích `usr/share/alsa` tạo sẵn `$dump/usr` rồi lại gọi `unsquashfs -d "$dump" ... "usr/bin/$tool"`), từ lần trích thứ hai trở đi unsquashfs hỏng và script báo `THIẾU usr/bin/pipewire`, `THIẾU usr/bin/wpctl`, `THIẾU usr/bin/pactl`, `THIẾU usr/bin/aplay`... — kể cả khi mọi binary đó đều có thật. Bản cũ còn tự chặn mọi thư mục quá 500 entry (để khỏi phải trích thư mục cha mà nhìn symlink), hoặc dùng `find ... | sort | head -60` dưới `set -e -o pipefail`: khi `head -60` đóng ống sau 60 dòng (ngay tại `usr/share/alsa/cards/CMI8738-MC8.conf`), lệnh đứng trước nhận `SIGPIPE` (tín hiệu 13) và làm cả bước CI chết với `Error: Process completed with exit code 141` (`128 + 13`) trước khi kịp in `::error::`.

Cách sửa: đọc ảnh live bằng `scripts/check-live-audio.sh`. Script lấy loại entry và đích symlink từ `unsquashfs -ll` (chỉ đọc metadata, **không trích gì** và không đi theo symlink, nên thư mục cha to cỡ nào cũng không ảnh hưởng), trích **đúng entry** cần đọc vào một thư mục đích **mới toanh** cho mỗi lần trích (không bao giờ gặp lại lỗi `File exists`), và giới hạn số dòng chẩn đoán bằng `awk 'NR <= 60'` (đọc hết luồng tới EOF thay vì đóng ống sớm như `head`, nên không bao giờ chết với exit code 141). Bài tự kiểm tra `scripts/selftest-check-live-audio.sh` dựng một ảnh live giả có đúng bố cục symlink đó, một `usr/bin` khổng lồ, hàng trăm file `usr/share/alsa/cards/*.conf` và lỗi `File exists` của `unsquashfs`, rồi chạy trong workflow `AniOS profile checks` — nên lỗi kiểu này bị bắt trong vài giây thay vì sau một lượt dựng ISO hàng chục phút.

### Lỗi `A NOPASSWD sudo rule leaked into the image`

`mkarchiso` đã báo `Done!`, `build-iso.sh` in `AUR package baked into the image: ...` cho từng gói rồi dừng với:

```text
A NOPASSWD sudo rule leaked into the image while building AUR packages:
  etc/sudoers.d/20-foo:1: foo ALL=(ALL) NOPASSWD: ALL
```

Các dòng thụt vào có dạng `<file trong ảnh>:<số dòng>: <luật>` và là **đúng luật đã lọt vào ảnh**. `scripts/anios-aur-build.sh` không chạm vào sudoers, nên hãy tìm gói hoặc hook nào đã ghi luật đó và bỏ nó đi.

Bản cũ của script (trước khi có hàm `sudoers_nopasswd_rules`) dùng `grep -R NOPASSWD` nên **luôn** báo lỗi này, kể cả trên ảnh hoàn toàn sạch và không in ra dòng nào để lần theo. Nguyên nhân: gói `sudo` của Arch ship `/etc/sudoers` kèm sẵn ví dụ đã comment `# %wheel ALL=(ALL:ALL) NOPASSWD: ALL`, và `base-devel` (cần cho `yay`) kéo gói đó vào ảnh. Hàm mới chỉ tính luật **đang có hiệu lực** trong `etc/sudoers` và `etc/sudoers.d/*` (bỏ qua comment, nhưng `#1000 ...` là uid nên vẫn là luật thật). `scripts/selftest-build-iso-sudoers.sh` khoá hành vi đó và chạy trên mọi push/PR, nên lỗi kiểu này bị bắt trong vài giây thay vì sau một lượt dựng ISO.

Các dòng `warning: database file for 'core' does not exist (use '-Sy' to download)` xuất hiện xen giữa log ở bước này là **vô hại**: `pacman -Q --sysroot` đọc `etc/pacman.conf` của ảnh (khai báo `core`/`extra`/`multilib`) nhưng ảnh không chứa sync database. Chúng không liên quan tới lỗi trên.

## Gói AUR cài sẵn trong ảnh

`pacstrap` chỉ giải quyết được gói trong kho chính thức của Arch, nên gói AUR **không thể** nằm trong
`profile/packages.x86_64`. AniOS vì thế có một đường riêng: `profile/packages.aur.x86_64` liệt kê gói AUR
cần nướng vào ảnh, còn `scripts/anios-aur-build.sh` dựng và cài chúng **bên trong chroot** — sau khi
pacstrap cài xong và trước khi `mkarchiso` sinh `pkglist.x86_64.txt`, nên gói AUR hiện diện đầy đủ trong
database pacman của ảnh lẫn trong danh sách gói trên ISO.

| Gói AUR | Trong ảnh để làm gì |
| --- | --- |
| `calamares` | trình cài đặt đồ hoạ từng bước; AniOS nạp module, thương hiệu và theme riêng sau khi gói được cài |
| `yay` | trợ lý AUR cho phiên live: tìm, cài và cập nhật cả kho chính thức lẫn AUR (`yay -Syu`) |
| `coccoc-browser-stable` | trình duyệt Cốc Cốc tiếng Việt (Chromium, tải media tốt); phụ thuộc `qt5-base`, `ttf-liberation` |
| `legacy-launcher` | launcher Minecraft bản classic (llaun.ch); chạy bằng Java, cần `jre-openjdk` |

Cùng đợt này, `packages.x86_64` có thêm `python`, `python-pip`, `nodejs`, `npm`, `wine`, `winetricks`,
`flatpak`, `base-devel`, `git`, `jre-openjdk`, `qt5-base` và `ttf-liberation` — nhóm gói từ kho chính thức
mà người dùng phòng net hay phải tự cài.

Cách bước dựng AUR hoạt động:

- `build-iso.sh` chép manifest và script dựng vào `airootfs/root/.anios-aur/`, sinh
  `airootfs/root/customize_airootfs.sh` (hook mà `mkarchiso` chạy bằng `env -u TMPDIR arch-chroot` rồi tự
  xoá), và chạy hook đó qua `bash` vì overlay chép vào airootfs làm mất bit thực thi.
- PKGBUILD được lấy trực tiếp từ AUR; nếu Git/TLS tới `aur.archlinux.org` lỗi, script thử mirror GitHub
  chỉ-đọc chính thức `archlinux/aur` (mỗi gói là một branch), rồi mới thử snapshot cgit. Với Calamares,
  hook bỏ riêng `packagechooser` khỏi danh sách `SKIP_MODULES` trong PKGBUILD vì cấu hình AniOS dùng module
  này; `packagechooserq` vẫn tắt. Hook kiểm tra plugin sau khi cài để tránh phát hành installer thiếu module.
- Trong chroot, tài khoản tạm `aniosbuild` (UID 1412) dựng gói bằng `makepkg` với quyền đã hạ bằng
  `runuser`/`setpriv`; thư mục dựng nằm ở `/var/tmp/anios-aur-build`. Root chỉ cài phụ thuộc
  (`pacman -S --asdeps`), cài gói hoàn chỉnh (`pacman -U --asexplicit` để không bị dọn như mồ côi), rồi
  gỡ **đúng** những phụ thuộc mồ côi do bước này tạo ra. `makepkg` không bao giờ chạy dưới quyền root, và
  **không có** luật `sudoers`/`NOPASSWD` nào được thêm vào ảnh.
- `go` chỉ là makedepend tạm thời của `yay`: nó được cài trong chroot bằng `--asdeps` (bên cạnh nhóm công
  cụ dựng `BUILD_TOOLS=(base-devel git)`) rồi bị dọn cùng nhóm mồ côi, nên **không** nằm trong
  `packages.x86_64` và không có trong ISO cuối cùng — dù vậy `base-devel` + `git` vẫn ở lại ảnh vì người
  dùng phiên live cần chúng để `yay` dựng gói.
- Cố tình **không** dùng `pacman -Sy` ở đường thường: pacstrap vừa điền sync DB nên cài thẳng bằng DB đó
  giữ cho cả ảnh ở **một snapshot kho**, tránh trạng thái "partial upgrade". Chỉ khi DB sẵn có không cài
  được mới đồng bộ lại kho + keyring rồi thử lần hai.
- Một gói AUR dựng hỏng sẽ **làm dừng bản dựng** (kèm gợi ý `--no-aur`) chứ không âm thầm bỏ qua; tên gói
  không hợp lệ bị chặn trước khi tải; mỗi gói có thể tự thử lại (`ANIOS_AUR_RETRIES`); nhật ký đầy đủ ở
  `/var/tmp/anios-aur-build/anios-aur-build.log` trong lúc dựng (`ANIOS_AUR_KEEP_TMP=1` để giữ lại).
- Ảnh cuối cùng có `/usr/share/anios/aur-packages.txt` ghi `tên_gói=phiên_bản` cho từng gói AUR đã cài, để
  đối chiếu về sau.
- Ngay sau `mkarchiso`, `build-iso.sh` tự soi lại airootfs: gói AUR có trong pacman DB, không còn tài khoản
  `aniosbuild` hay `/root/.anios-aur`, và **không có luật `NOPASSWD` nào đang hiệu lực** trong `etc/sudoers`
  lẫn `etc/sudoers.d/*`. Chỉ luật thật mới tính, comment thì không: `/etc/sudoers` mặc định của gói `sudo` có
  sẵn dòng ví dụ `# %wheel ALL=(ALL:ALL) NOPASSWD: ALL`, nên một lệnh `grep NOPASSWD` thô sẽ luôn báo nhầm
  (xem [mục lỗi tương ứng](#lỗi-a-nopasswd-sudo-rule-leaked-into-the-image)).

Kiểm tra ảnh vừa dựng:

```bash
# Đối chiếu ngay trong squashfs: Calamares + gói AUR + python/nodejs/wine, và không còn tàn dư của bước dựng
./scripts/check-live-aur.sh work/x86_64/airootfs.sfs

# Tham số thứ hai (pkglist) là tuỳ chọn; CI trích nó từ ISO rồi truyền vào để đối chiếu chéo:
xorriso -indev out/anios-*.iso -osirrox on -extract /arch/pkglist.x86_64.txt out/anios-pkglist.txt
./scripts/check-live-aur.sh work/x86_64/airootfs.sfs out/anios-pkglist.txt
```

`scripts/check-live-aur.sh` đọc `airootfs.sfs` bằng `unsquashfs -ll`/`-cat` (theo đúng cách đọc symlink
mô tả ở phần [troubleshooting](#ci-báo-thiếu-etcalsaconfd-dù-gói-đã-cài-file-đó)) và xác nhận: Calamares,
các cấu hình/chọn lựa packagechooser và helper AniOS đều có trong ảnh; module packagechooser còn tồn tại;
binary của từng gói (`usr/bin/calamares`, `yay`, `python3`, `node`, `npm`, `wine`, `winetricks`, `java`,
`makepkg`, `git`) có trong ảnh; database pacman trong ảnh (`var/lib/pacman/local/<gói>-<pkgver>-<pkgrel>`)
ghi nhận từng gói — đây là điều kiện để `yay`/`pacman` trong phiên live nhận ra chúng; `pkglist.x86_64`
cũng liệt kê chúng; và
**không** còn tàn dư nào của bước dựng (`root/.anios-aur`, `root/customize_airootfs.sh`,
`var/tmp/anios-aur-build`, `home/aniosbuild`, dòng `aniosbuild` trong `/etc/passwd`, luật `NOPASSWD` trong
`etc/sudoers.d`). Hai bài tự kiểm tra `scripts/selftest-anios-aur-build.sh` và
`scripts/selftest-check-live-aur.sh` dựng sandbox giả để bắt lỗi kiểu này trong vài giây, chạy trên mọi
push/PR mà không cần Arch Linux.

## Dựng ISO tự động bằng GitHub Actions

Workflow `.github/workflows/build-iso.yml` dựng ISO trên runner Ubuntu bằng cách chạy trực tiếp container Docker `archlinux:base-devel`, rồi gọi đúng `scripts/build-iso.sh` nên kết quả giống hệt khi dựng tay. Mỗi lượt chạy tự giải phóng dung lượng đĩa của runner, cài `archiso`, kiểm tra profile, dựng ISO, rồi tự kiểm tra kết quả (checksum SHA256, boot record El Torito cho BIOS/UEFI, đúng kernel `linux-zen`, đọc thẳng `airootfs.sfs` để xác nhận tên AniOS, wallpaper, theme SDDM Wuthering Waves, cấu hình desktop, giao dàn âm thanh PipeWire cho `scripts/check-live-audio.sh`, và giao Calamares + packagechooser, các helper installer, gói AUR cùng `python`/`nodejs`/`wine` cho `scripts/check-live-aur.sh` kiểm tra) trước khi lưu lại. Nếu một bước hỏng, lượt chạy đỏ và không có artifact.

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
- **Cài thêm phần mềm ngay trong phiên live**: `yay` đã có sẵn trong ảnh nên dùng được cả kho chính thức lẫn AUR — `yay -S <tên gói>` để cài (tự hỏi mật khẩu `sudo`), `yay -Syu` (hoặc alias `update-aur`) để cập nhật toàn bộ, `yay -Ss <từ khoá>` (alias `aur-search`) để tìm. Gói cài thêm được ghi vào ổ lưu trữ trên USB (xem [mục bên dưới](#lưu-trữ-trên-usb-không-chạy-trong-ram-kiểu-tails)) nên còn nguyên sau khi tắt máy; nếu USB không còn chỗ để tạo ổ lưu trữ và phiên rơi về chế độ RAM dự phòng thì gói chỉ tồn tại tới khi tắt máy. Gói phải biên dịch tốn thời gian và CPU — máy yếu nên ưu tiên gói `-bin`.
- **Cốc Cốc Browser** (`coccoc-browser-stable`) cài sẵn cho ai cần trình duyệt tiếng Việt, tải media từ trang nội địa tốt; chạy qua XWayland trong phiên Hyprland, thêm `--ozone-platform-hint=auto` nếu muốn thử Wayland native.
- **Phần mềm Windows**: `wine` + `winetricks` cài sẵn (kho `multilib` được bật từ lúc dựng nên phần 32-bit đầy đủ). Chạy `wine <file.exe>`; lần đầu Wine có thể đề nghị tải thêm Gecko/Mono. Game Windows nên ưu tiên qua Steam/Proton.
- **Lập trình**: `python` + `pip`, `nodejs` + `npm` và Java (`jre-openjdk`) có sẵn; `base-devel` + `git` cũng nằm trong ảnh để `yay` tự dựng được gói AUR ngay trong phiên.
- **Minecraft**: `legacy-launcher` (bản classic của llaun.ch) cài sẵn, mở từ launcher; cần Java (đã có) và tài khoản Minecraft hợp lệ.
- Mở Steam từ launcher. Steam cần Internet và tài khoản Steam. Nếu Steam báo `Steam needs to be online to update` hoặc `DownloadManifest - exhausted list of download hosts` dù máy đã có mạng, xem [mục riêng bên dưới](#steam-báo-steam-needs-to-be-online-to-update). Có thể thử GameMode bằng cách thêm `gamemoderun %command%` vào Steam → Properties → Launch Options của game. Steam và mọi thứ bạn tải được ghi vào ổ lưu trữ trên USB nên dung lượng trống bằng phần còn lại của USB (xem [bên dưới](#lưu-trữ-trên-usb-không-chạy-trong-ram-kiểu-tails)). Nếu phiên đang ở chế độ RAM dự phòng thì hãy copy file cần giữ ra ổ ngoài trước khi tắt máy.
- Phím tắt: `Super+Return` mở Foot; `Super+D` mở launcher; `Super+Shift+A` mở công cụ kiểm tra âm thanh; `Super+Shift+L` khoá màn hình; `Ctrl+Alt+F2` mở TTY cứu hộ (ở đó `fastfetch` in thông tin máy); `Super+Shift+E` thoát phiên Hyprland.
- **Màn hình khoá dùng mật khẩu**, không phải cơ chế bảo mật mạnh: nhập `1111` để mở khoá. Tài khoản live và `sudo` dùng cùng mật khẩu; mật khẩu này được tạo sẵn trong ảnh từ lúc build (pacman hook `anios-live-user.hook` viết hash vào `/etc/shadow`) và được `anios-live-home.service` đặt lại ở mỗi lần khởi động như dự phòng. Vì vậy đừng để dữ liệu quan trọng trong phiên live.
- Nếu thoát phiên bằng `Super+Shift+E`, SDDM sẽ hiện theme **Wuthering Waves** của Qylock; chọn phiên **AniOS (Hyprland)** rồi nhập `1111` để vào lại. Theme hiện khung nền tĩnh ngay, rồi mới khởi tạo video sau 1,2 giây; nếu thiếu codec video thì khung tĩnh vẫn giữ cho màn hình đăng nhập dùng được. Các lỗi không vào được SDDM đã được xử lý triệt để: tắt tiến trình agetty autologin tty1 của releng để tránh tranh chấp VT, chuẩn hoá UID 1000 và nhóm quyền phần cứng (wheel, video, audio, input, seat) cho tài khoản `anios`, sửa liên kết dịch vụ chuẩn bị thư mục người dùng (`anios-live-home.service`), cấu hình `MinimumUid=500` cho SDDM, bổ sung fallback tài khoản tự động trong theme, và "nướng" mật khẩu `1111` vào `/etc/shadow` từ lúc build bằng pacman hook để đăng nhập thủ công SDDM (stack PAM `sddm` → `pam_unix`) không phụ thuộc vào việc service lúc khởi động có chạy thành công hay không — autologin thì luôn qua được vì dùng stack `sddm-autologin` (kết thúc bằng `pam_permit`).
- Desktop mặc định giữ hiệu ứng ở mức "rẻ" cho iGPU đời cũ: cửa sổ thường **không** blur, animation chỉ là fade/popin ngắn, blur dành riêng cho các lớp phủ bán trong suốt (Waybar, Fuzzel, Mako) qua `layerrule`, còn màn hình khoá hyprlock tự blur nền một lần lúc khoá. `Super+Space` bật/tắt chế độ cửa sổ nổi.
- **Cấu hình Hyprland** nằm ở `~/.config/hypr/hyprland.lua` (bản sao gốc trong ảnh: `/usr/share/anios/skel/.config/hypr/hyprland.lua`): từ Hyprland 0.55 cấu hình viết bằng Lua thay cho `hyprland.conf` cũ, nên sau khi sửa chỉ cần `Super+Shift+R` để nạp lại. Màn hình khoá dùng định dạng riêng của hyprlock (`~/.config/hypr/hyprlock.conf`).

### Steam báo "Steam needs to be online to update"

Chuỗi log `DownloadManifest - exhausted list of download hosts` → `Failed to load manifest` → `Download failed: http error 0` → `Steam needs to be online to update` là lỗi mạng của phiên live chứ không phải lỗi Steam: nó xảy ra khi tên máy chủ Valve không phân giải được, khi máy có IPv6 toàn cục nhưng IPv6 không ra được Internet, hoặc khi TLS bị chặn giữa đường — trong khi trình duyệt (có Happy Eyeballs, có cache) vẫn mở web bình thường. Bản ISO này xử lý sẵn ba nguyên nhân hay gặp nhất ngay từ lúc dựng:

- **Chỉ NetworkManager quản lý mạng.** releng của archiso bật sẵn `systemd-networkd` + `iwd`; profile của AniOS chỉ *thêm* file lên trên nên trước đây hai trình quản lý mạng cùng chạy, cùng giành card mạng, còn `iwd` giành luôn card Wi-Fi khỏi `wpa_supplicant` của NetworkManager — kết nối và DNS chập chờn, và Steam tải manifest thất bại. Từ bản này bốn unit `systemd-networkd.service`, `systemd-networkd.socket`, `systemd-networkd-wait-online.service`, `iwd.service` bị **mặt nạ** (`/etc/systemd/system/<unit>` → `/dev/null`) và `scripts/build-iso.sh` gỡ các symlink bật dịch vụ tương ứng của releng rồi dừng bản dựng nếu chúng còn sót. Wi-Fi do NetworkManager + wpa_supplicant đảm nhiệm như mọi thứ khác trong ảnh (`nmcli`, `nmtui`, Quickshell, Waybar).
- **DNS luôn có đường dự phòng.** NetworkManager được ghim `dns=systemd-resolved` (`/etc/NetworkManager/conf.d/10-anios-dns.conf`) — đúng chế độ NetworkManager tự chọn khi `/etc/resolv.conf` là symlink tới stub của resolved, nhưng ghi rõ để một thay đổi của releng không âm thầm đổi chủ — và `systemd-resolved` được đặt `FallbackDNS=1.1.1.1 8.8.8.8 9.9.9.9 149.112.112.112` (`/etc/systemd/resolved.conf.d/10-anios-live.conf`). Mạng không phát nameserver qua DHCP, hoặc phát máy chủ DNS hỏng/chặn tên Valve, không còn làm Steam chết ngay khi mở.
- **Tự kiểm tra khi vào desktop.** `anios-netcheck.service` chạy `anios-netcheck --quiet --fix` ngay sau NetworkManager; kết quả nằm trong `journalctl -u anios-netcheck`.

Khi vẫn thấy lỗi, gõ `anios-netcheck` trong Foot (hoặc mở **Kiểm tra mạng AniOS** trong launcher). Công cụ lần lượt kiểm tra đồng hồ hệ thống (giờ lệch làm mọi bắt tay TLS thất bại), liên kết mạng và máy chủ DNS đang dùng, phân giải bốn tên máy chủ Valve bằng đúng `getaddrinfo` mà Steam dùng, khả năng ra Internet bằng IPv4 lẫn IPv6, rồi tải thử manifest client của Steam và nhận diện captive portal. Các tuỳ chọn:

```bash
anios-netcheck                 # báo cáo đầy đủ, exit 1 nếu phát hiện lỗi
anios-netcheck --fix           # khởi động lại systemd-resolved, ghi DNS công cộng nếu DNS chết hẳn, ưu tiên IPv4 khi IPv6 "nửa sống"
anios-netcheck --fix-dns       # ép dùng DNS công cộng khi nhà mạng chặn/đầu độc DNS của Valve
anios-netcheck --pause         # đợi Enter trước khi thoát (khi mở từ menu ứng dụng)
```

`--fix-dns` ghi `/etc/resolv.conf` (bản gốc được sao lưu ở `/run/anios-netcheck`) và tạo `/etc/NetworkManager/conf.d/99-anios-netcheck.conf` (`dns=none`) để NetworkManager không ghi đè lại bằng DNS hỏng của DHCP; muốn trở về bình thường thì xoá tệp drop-in đó rồi chạy `sudo nmcli general reload`. Khi IPv6 "nửa sống" (máy có địa chỉ IPv6 toàn cục nhưng không ra được Internet), `--fix` thêm dòng `precedence ::ffff:0:0/96  100` vào `/etc/gai.conf` để mọi chương trình ưu tiên IPv4; xoá dòng đó khi mạng đã bình thường.

Vài thứ công cụ không tự sửa được, phải làm tay: đăng nhập captive portal (mở trình duyệt), tắt proxy trong **Steam → Settings → Downloads**, và xoá thư mục cài dở `~/.local/share/Steam` nếu lần cập nhật trước bị đứt giữa đường. Nếu mạng của quán chặn hẳn HTTPS tới `steampowered.com`/`steamstatic.com` thì máy không thể tự cập nhật Steam — đổi mạng hoặc dùng VPN ở tầng router.

### Đồng hồ sai giờ (múi giờ Việt Nam)

Ảnh live dựng từ archiso mặc định chạy **giờ UTC** (không có `/etc/localtime`), nên đồng hồ trên desktop lệch 7 tiếng so với giờ Việt Nam, ngày giờ của file và nhật ký sai; còn bộ cài Calamares thì lấy mặc định gốc **America/New_York** nên máy cài xong vẫn sai giờ nếu không đổi tay. Bản này đặt sẵn giờ Việt Nam ở cả ba chỗ:

- **Phiên live**: `profile/airootfs/etc/localtime` là symlink **tương đối** tới `../usr/share/zoneinfo/Asia/Ho_Chi_Minh` (UTC+7, không có giờ mùa hè). Dạng tương đối để symlink đọc được cả trong `work/` lúc dựng lẫn trong ảnh đã đóng; `scripts/build-iso.sh` ghi lại cho đúng nếu releng đổi và dừng bản dựng khi ảnh không mang múi giờ này.
- **Đồng bộ giờ qua mạng**: ảnh bật sẵn `systemd-timesyncd` (`etc/systemd/system/multi-user.target.wants/`) và ghim máy chủ NTP về cụm châu Á trong `etc/systemd/timesyncd.conf.d/10-anios-ntp.conf`, kèm `FallbackNTP` là cụm của Arch để không mất đường đồng bộ. Việc này quan trọng không kém múi giờ: máy quán net hay chạy song song Windows nên RTC có thể lệch, mà đồng hồ sai thì **mọi bắt tay TLS thất bại** — Steam báo `needs to be online to update`, trình duyệt báo lỗi chứng chỉ. Đó là bước 1/6 của `anios-netcheck`.
- **Hệ thống cài đặt**: `profile/installer/calamares/modules/locale.conf` đặt `region: Asia`, `zone: Ho_Chi_Minh` và tắt GeoIP (`style: "none"`). Thiếu file này thì Calamares dùng mặc định `America/New_York` của gói; còn bật GeoIP thì múi giờ suy ra từ IP — trạm net ra Internet qua NAT/proxy của nhà mạng nên IP thường bị định vị sang nước khác, và kết quả đó ghi đè luôn mặc định. Người dùng vẫn đổi được múi giờ trên bản đồ của bộ cài; module `locale` trong sequence là bước ghi `/etc/localtime` và `/etc/locale.conf` vào hệ thống đích, `hwclock` ghi `/etc/adjtime`.

Đồng hồ phần cứng (RTC) vẫn theo chuẩn Linux là **UTC**; AniOS không đổi `/etc/adjtime` của phiên live. Kiểm tra nhanh: `timedatectl` — dòng `Time zone` phải là `Asia/Ho_Chi_Minh (+07)`, và `System clock synchronized: yes` sau vài giây có mạng.

### Con trỏ chuột nhấp nháy hoặc đổi hình liên tục

Con trỏ chỉ ổn định khi **tên theme mà compositor nhận được là một theme có thật trong ảnh**. Lỗi từng xảy ra: ảnh live không khai báo gói theme con trỏ nào, trong khi mặc định của shell Immaterial Impulse là `Bibata-Modern-Classic` (chỉ có trên AUR), còn phiên Minimal và GTK lại nói `Adwaita`. `hyprctl setcursor` với một theme không tồn tại không phải lệnh vô hại: Hyprland đưa tên đó cho libXcursor, không thư mục theme nào khớp nên `XCursorManager::loadTheme()` báo `XCursor failed finding any shapes in theme` rồi giữ danh sách shape rỗng — compositor mất con trỏ của chính nó và cứ đổi qua lại với surface từng ứng dụng tự đặt, nên con trỏ nhấp nháy/đổi hình khi rê giữa các cửa sổ.

Bản này dùng **một theme duy nhất là Adwaita** ở mọi tầng:

- Gói `adwaita-cursors` (kho chính thức; `adwaita-cursor-theme` là tên gói của Fedora/RHEL) nằm trong cả `profile/packages.x86_64` lẫn manifest cài đặt `profile/install/packages.x86_64`, nên `/usr/share/icons/Adwaita/cursors` luôn có sẵn chứ không trông vào phụ thuộc bắc cầu của `adwaita-icon-theme`.
- `~/.icons/default/index.theme` với `Inherits=Adwaita`: đây là chỗ libXcursor — và Hyprland khi chưa ai gọi `setcursor` — phân giải theme tên `default`. Thiếu nó thì app X11 qua XWayland và compositor mỗi nơi một con trỏ.
- `apply_saved_cursor.sh` (chạy lúc vào phiên Immaterial Impulse) kiểm tra theme trong cấu hình có được cài không **trước khi** gọi `hyprctl setcursor`, và rơi về Adwaita nếu không; nếu ảnh không có theme nào thì giữ nguyên con trỏ mặc định của compositor chứ không xoá shape của nó. Shell cũng tự đối chiếu theme đang lưu với danh sách theme quét được (`CursorThemes.qml`) để **Settings → Cursor** đánh dấu đúng con trỏ compositor đang dùng.
- Mặc định của Settings → Cursor (`Config.qml`) là Adwaita 24, khớp `gtk-cursor-theme-name` trong `gtk-3.0/settings.ini` và `XCURSOR_THEME` của phiên Minimal.

Đổi theme/cỡ con trỏ ở **Settings → Cursor**: mỗi lựa chọn áp cùng lúc cho Hyprland (`hyprctl setcursor`), GTK 3/4, `~/.icons/default/index.theme` và gsettings, và chỉ được lưu vào cấu hình khi áp thành công. `scripts/selftest-apply-saved-cursor.sh` chạy đúng script khởi động đó với `hyprctl` giả trên cây icon giả để khoá lại hành vi trên (không cần Arch Linux, không cần phiên đồ hoạ).

### Lưu trữ trên USB (không chạy trong RAM kiểu Tails)

AniOS **không** chạy theo kiểu "live trong RAM, tắt máy là mất hết" như Tails. Ghi ISO ra USB (Rufus chế độ DD, `dd`, balenaEtcher) chỉ dùng phần đầu đĩa, chỉ đọc; phần còn lại của USB để trống. AniOS dùng chính phần đó làm lớp ghi của hệ thống, nên USB 64 GB cho gần 64 GB chỗ trống chứ không phải vài GB phụ thuộc RAM:

- Ảnh hệ thống được đọc thẳng từ USB (`copytoram=n`), không chép vào RAM.
- **Lần boot đầu tiên** `anios-persist.service` (chạy trước SDDM) tạo phân vùng ext4 nhãn `ANIOS_PERSIST` trên toàn bộ phần trống của USB, chỉ thêm phân vùng mới và không đụng tới phân vùng sẵn có, rồi **tự khởi động lại một lần** (UEFI). Cần ít nhất 2 GiB trống; không đủ chỗ thì phiên chạy ở chế độ RAM dự phòng.
- Sau khi tạo phân vùng, `anios-persist` ghi thêm file đánh dấu `EFI/BOOT/anios-persist` lên phân vùng ESP của USB; từ lần boot sau mục AniOS Live trong GRUB thấy file này thì dùng `ANIOS_PERSIST` làm lớp ghi (kiểm tra file nên im lặng, không còn dòng `error: no such device` ở lần boot đầu như khi dùng `search --label`). Nếu phân vùng đã có mà thiếu file đánh dấu, lần boot kế tiếp sẽ tự bổ sung rồi khởi động lại một lần. `df -h /` hiện dung lượng cả phần còn lại của USB; gói cài thêm (`yay -S ...`), game Steam, model AI và file trong home được giữ giữa các lần boot.
- **BIOS (Syslinux)** không tự dò được phân vùng: lần đầu phân vùng được tạo nhưng máy không tự khởi động lại; hãy khởi động lại và chọn mục "AniOS Live (BIOS) with persistent storage". Nếu GRUB (UEFI) không nhận ra file đánh dấu, chọn mục "ép dùng ổ lưu dữ liệu ANIOS_PERSIST".
- Mục "chế độ dự phòng trong RAM, bỏ qua ổ lưu dữ liệu" (`anios_persist=off`) boot không dùng phân vùng, dùng khi phân vùng gặp sự cố; mục này cũng không tạo phân vùng mới.
- `anios-persist` xem trạng thái; `anios-persist setup` tạo phân vùng thủ công (cũng có shortcut trên desktop).

**Dữ liệu nào được giữ lại** (khi phiên chạy trên ổ lưu trữ `ANIOS_PERSIST`, không phải RAM): mọi thay đổi trên hệ thống live, gồm thư mục home (`/home/anios`: file tải về, tài liệu, Desktop, cấu hình ứng dụng, phiên đăng nhập lưu trong file như Steam, trình duyệt), game Steam đã tải, gói cài thêm bằng `yay`/`pacman` và model AI đã tải. Mỗi lần khởi động AniOS chỉ bổ sung các file mặc định còn thiếu, không ghi đè những gì bạn đã sửa.

**Tắt máy khi Steam đang chạy:** khi bạn tắt hoặc khởi động lại, AniOS yêu cầu Steam tự thoát (`anios-steam-quit`) và chờ tối đa 45 giây trước khi hệ thống dừng tiến trình. Nếu Steam bị dừng cưỡng bức (SIGKILL) khi đang tải hoặc cập nhật, lần khởi động sau Steam có thể báo `didn't shutdown cleanly` hoặc tải lại client. Khi đang tải game, vẫn nên chọn **Steam → Exit** và chờ tải xong rồi mới tắt máy.

**Dữ liệu nào không được giữ**:
- Mọi thứ trong phiên khi đang chạy trong **RAM** (chế độ dự phòng, hoặc khi chọn nhầm mục `anios_persist=off`). Phiên RAM sẽ hiện cảnh báo đỏ trên màn hình ngay khi đăng nhập; nếu thấy cảnh báo này, khởi động lại và chọn mục AniOS Live có lưu trữ.
- Các thứ tạm thời theo thiết kế của Linux: `/run`, `/tmp` và socket của phiên.
- Dữ liệu đã mã hoá bằng keyring (mật khẩu, token của Discord/trình duyệt) có thể phải đăng nhập lại nếu keyring không được mở khoá tự động khi boot.

Lưu ý: USB phải luôn cắm khi dùng. Dữ liệu lưu theo từng bản ISO (thư mục `persistent_<UUID ISO>` trên phân vùng), nên ghi ISO mới sẽ bắt đầu lại từ trạng thái sạch; dữ liệu cũ vẫn nằm trên phân vùng. Chọn thủ công mục có `cow_label` khi chưa có phân vùng sẽ khiến initramfs rơi vào shell.

### Khi Hyprland báo lỗi cấu hình Lua

Chạy `hyprctl configerrors` để xem lỗi và `hyprctl version` để kiểm tra phiên bản.
Với API Lua của Hyprland 0.56, gradient phải là bảng
`{ colors = { "rgba(2f6be8ff)", "rgba(4ea6eaff)" }, angle = 45 }`, không phải
chuỗi hyprlang `"rgba(...) rgba(...) 45deg"`. Theme/cỡ con trỏ đặt bằng
`hl.env("XCURSOR_THEME", "Adwaita")`, `XCURSOR_SIZE` và các biến `HYPRCURSOR_*`,
không dùng option `cursor.name`/`cursor.size` — và theme đó phải do gói
`adwaita-cursors` cài ra, xem [mục con trỏ nhấp nháy](#con-trỏ-chuột-nhấp-nháy-hoặc-đổi-hình-liên-tục).
`decoration.shadow.render_power`
chỉ nhận số nguyên từ 1 đến 4. Sau khi sửa, chạy `hyprctl reload` rồi kiểm tra lại
`hyprctl configerrors` (áp dụng cả Minimal và Immaterial Impulse).

Trong repo, `scripts/check-hyprland.sh` kiểm tra cú pháp mọi module Lua, nạp thử
cả hai giao diện với API giả lập tối thiểu và kiểm tra mẫu màu Matugen; hai bản
skel phải đồng bộ. Bài kiểm tra này bắt các lỗi trên nhưng **không thay thế**
việc thử trên Hyprland thật/GPU thật.

## Diện mạo AniOS Minimal

Bản Minimal giữ triết lý "nhẹ nhưng chỉn chu": cùng một ngôn ngữ thiết kế xuyên suốt mọi thành phần người dùng nhìn thấy.

- **Bảng màu "Gura Blue"** trích từ wallpaper Gura (nền xanh trời lưới sáng, chữ GURA trắng, xanh royal đậm, teal, vàng, đỏ): lớp chrome desktop dùng nền navy đậm `#0a1626`, accent xanh royal `#2f6be8`, xanh trời `#4ea6ea`, teal `#3ec3d8`, vàng `#edb62f`, đỏ `#d8404f`, chữ trắng xanh `#eaf4fd`; dùng chung cho Waybar, Fuzzel, Foot, Kitty, Mako, hyprlock, prompt starship/fish, theme SDDM AniOS và `gtk.css`.
- **Waybar dạng viên thuốc nổi**: nền thanh trong suốt, mỗi module là một pill bo tròn bán trong suốt (được Hyprland blur nhẹ), workspace hiện icon số Nerd Font, đồng hồ kèm lịch tooltip, thêm module CPU/RAM và nút khoá màn hình.
- **Hiệu ứng rẻ**: viền cửa sổ đang chọn là gradient xanh royal → xanh trời, bo góc 10px, shadow mềm chỉ cho cửa sổ nổi, animation fade/popin ngắn; cửa sổ xếp lưới không blur để tiết kiệm GPU.
- **Màn hình khoá hyprlock** dàn cục diện wordmark + đồng hồ lớn + ngày + ô mật khẩu bo tròn, nền wallpaper tự blur, kèm cảnh báo Caps Lock.
- **Font & icon**: chữ UI dùng Noto Sans (đủ dấu tiếng Việt), terminal dùng font monospace của hệ thống; icon lấy từ `ttf-nerd-fonts-symbols` (Symbols Nerd Font) đã cài sẵn.
- **Ứng dụng GTK** vào dark theme đồng bộ qua `~/.config/gtk-3.0|4.0/settings.ini` + `gtk.css` (bo góc CSD, thanh cuộn mảnh, màu chọn theo accent). Ở chế độ imi, matugen ghi đè `gtk.css` bằng bảng màu Material.

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
- Hệ thống Live đọc ảnh nén trực tiếp từ USB (`copytoram=n`, không chép vào RAM; zram là swap nén, `vm.swappiness=100` để giảm nghẽn khi mở nhiều game) và không phải trình cài đặt vào ổ đĩa. Cần đủ RAM cho hệ thống và game; để dùng ổn định trong quán net, nên cài lên ổ đĩa và kiểm thử từng mẫu máy trước.

### Sober (Roblox) và GNOME Disks

- **Sober** (`org.vinegarhq.Sober`, chỉ phát hành dạng Flatpak trên Flathub) được cài sẵn vào ảnh lúc dựng bằng hook chroot (`flatpak install --system`). Mở bằng icon **Sober** trên Desktop/menu hoặc `anios-sober`. Nếu bước cài lúc dựng thất bại (hook chỉ cảnh báo, không làm hỏng bản dựng), `anios-sober` tự cài cho người dùng ở lần mở đầu tiên (cần Internet). Bỏ qua bước này khi dựng: `ANIOS_SKIP_FLATPAK=1 sudo ./scripts/build-iso.sh`. Runtime Flatpak làm ISO nặng thêm khoảng 1 GB trở lên. Sober cần Vulkan và đã cài trình điều khiển Mesa cho Intel/AMD.
- **GNOME Disks** (`gnome-disk-utility`, lệnh `gnome-disks`): phân vùng, định dạng, SMART, đo tốc độ ổ. Cẩn thận: đừng thao tác lên chính USB đang chạy hệ live.

### Tối ưu độ mượt giao diện

- Hyprland (cả Immaterial Impulse lẫn Minimal): giảm blur (2 lượt, size 6; Minimal 1 lượt), bật `xray`, bóng đổ nhẹ hơn, tắt dim cửa sổ không focus. Immaterial Impulse tắt widget visualizer trên hình nền. Chỉ đổi giá trị của các khoá đã có, không thêm khoá mới vì Hyprland 0.56 từ chối khoá lạ.
- Hệ thống: `vm.dirty_background_bytes`/`vm.dirty_bytes` nhỏ để ghi USB đều thay vì đứng hình khi xả cache, `vm.vfs_cache_pressure=50`, udev tăng `read_ahead_kb` lên 4096 cho USB rời, systemd chờ tối đa 10 giây khi tắt dịch vụ, Firefox tắt telemetry và bật giải mã video VA-API.
- Giá trị dựa trên kinh nghiệm chung, chưa đo FPS/độ trễ trên máy thật; nếu muốn đẹp hơn, chỉnh `blur`/`shadow` trong `~/.config/hypr/hyprland/general.lua`.

## Chạy AI cục bộ

Ảnh live kèm sẵn một stack AI chạy offline (model tải một lần rồi dùng lại không cần mạng):

- **Ollama (bản Vulkan)** — server LLM dùng backend Vulkan nên chạy được trên iGPU Intel lẫn AMD có trong máy phòng net; máy quá cũ không có Vulkan thì tự fallback về CPU. Service `ollama` được bật sẵn trong phiên live:
  ```bash
  ollama run llama3.2        # tải model lần đầu (cần mạng) rồi chat trong terminal
  ollama list                # xem model đã có
  curl localhost:11434       # API server cho app khác bám vào
  ```
  Không dùng tới thì tắt cho nhẹ RAM: `sudo systemctl disable --now ollama`.
- **llama-cpp / whisper-cpp** — suy luận LLM và nhận dạng tiếng nói (speech-to-text) dạng CLI, kèm backend ggml Vulkan (`ggml-vulkan`) và OpenVINO (`ggml-openvino`) để tăng tốc.
- **OpenVINO + plugin GPU Intel + intel-compute-runtime** — tối ưu hoá model cho CPU/iGPU Intel (OpenCL/Level Zero).
- **onnxruntime-cpu** — chạy model định dạng ONNX.
- **Jan AI** (`jan-bin`) và **LM Studio** (`lmstudio-bin`) — hai ứng dụng GUI nướng sẵn từ AUR lúc dựng ISO, mở từ launcher (`Super+D`): Jan là bản thay thế ChatGPT chạy 100% offline kèm engine llama.cpp, LM Studio dò và chạy model GGUF với giao diện dễ dùng.

Lưu ý cho môi trường live: **model không nướng vào ISO** (kẻo ảnh phình thêm hàng chục GB). Model tải trong phiên được ghi vào ổ lưu trữ trên USB nên được giữ giữa các lần boot; model lớn nên trỏ `OLLAMA_MODELS` (hoặc thư mục model của Jan/LM Studio) sang ổ cứng gắn ngoài để không chiếm hết chỗ trên USB. Ảnh không kèm CUDA/ROCm: máy có GPU rời NVIDIA/AMD mạnh có thể tự cài thêm `ollama-cuda`/`ollama-rocm` bằng `yay`.

## Cấu trúc repository

- `profile/airootfs/` — tài khoản Live, SDDM tự đăng nhập và theme **Wuthering Waves** (Qylock) đã tinh chỉnh khởi tạo video có dự phòng, phiên Hyprland (cấu hình Lua `hyprland.lua` + `hyprlock.conf` hỗ trợ song song Minimal và Immaterial Impulse), Quickshell, Waybar, Matugen, dotfile cài sẵn, ibus & fcitx5, công cụ chuyển đổi giao diện (`usr/local/bin/anios-switch-desktop`), dàn âm thanh tự khởi động (`etc/systemd/user/`, `usr/local/bin/anios-audio-setup`, `usr/local/bin/anios-audio-check`), mạng **chỉ do NetworkManager quản lý** (mặt nạ `systemd-networkd*` + `iwd`, drop-in `dns=systemd-resolved` cùng `FallbackDNS` của resolved, `usr/local/bin/anios-netcheck` và unit chạy nó), đồng hồ/múi giờ Việt Nam (`etc/localtime` → `Asia/Ho_Chi_Minh`, bật sẵn `systemd-timesyncd`, drop-in NTP cụm châu Á) và theme con trỏ Adwaita dùng chung cho Hyprland/GTK/XWayland (`~/.icons/default/index.theme`), kèm pacman hook (`etc/pacman.d/hooks/anios-live-user.hook`) tạo sẵn tài khoản live và mật khẩu `1111` trong ảnh lúc build.
- `profile/airootfs/usr/share/sddm/themes/wuwa/` — theme Qylock Wuthering Waves, mã nguồn giấy phép GPL-3.0; thông tin upstream và commit nguồn ở `UPSTREAM`.
- `profile/airootfs/etc/os-release` — tên AniOS hiển thị cho người dùng, `ID=arch` để giữ tương thích công cụ Arch.
- `profile/branding/` — wallpaper và splash menu khởi động; dựng lại bằng `./scripts/make-branding-assets.sh` (cần ImageMagick).
- `profile/packages.x86_64` — các gói desktop, kernel, game, firmware, ibus-unikey, theme con trỏ `adwaita-cursors`, Cốc Cốc/Wine/Python/Node.js/Java và tiện ích bổ sung vào Archiso `releng`.
- `profile/packages.aur.x86_64` — manifest gói AUR cần nướng vào ảnh (`calamares`, `yay`, `coccoc-browser-stable`, `legacy-launcher`); cố tình tách khỏi `packages.x86_64` vì pacstrap không phân giải được AUR.
- `scripts/build-iso.sh` — dựng profile Archiso tạm thời (kernel `linux-zen`, ảnh thương hiệu, gỡ bỏ xung đột agetty tty1, ghim `/etc/localtime` về `Asia/Ho_Chi_Minh` và bảo đảm `systemd-timesyncd` được bật trong ảnh, sao chép dotfile cho tài khoản live), stage Calamares và các theme/helper installer khi bật AUR, khai báo lại quyền/bit thực thi của các script trong ảnh bằng **một** danh sách `ANIOS_FILE_PERMISSIONS` (mkarchiso chép airootfs với `--no-preserve=mode`), chuẩn bị hook dựng gói (`root/.anios-aur` + `customize_airootfs.sh`, tuỳ chọn `--no-aur` để bỏ qua), chạy `mkarchiso`, rồi tự xác nhận gói AUR có trong pacman DB của ảnh và không còn tàn dư builder.
- `scripts/anios-aur-build.sh` — chạy **trong chroot airootfs**: tải PKGBUILD từ AUR, dựng bằng `makepkg` dưới tài khoản tạm `aniosbuild` với quyền đã hạ, root cài phụ thuộc/gói và dọn mồ côi, cài cấu hình Calamares vào `/etc/calamares`, ghi `/usr/share/anios/aur-packages.txt`.
- `scripts/check-profile.sh` — kiểm tra cấu trúc profile, danh sách gói (kể cả manifest AUR và ràng buộc của bước dựng AUR), cấu hình Calamares/installer (gồm `modules/locale.conf` để hệ thống cài ra đúng giờ Việt Nam), định danh AniOS, dotfile, cấu hình âm thanh (drop-in + symlink bật sẵn), múi giờ/NTP của ảnh live và tính nhất quán của theme con trỏ (gói `adwaita-cursors`, `~/.icons/default/index.theme`, mặc định của Settings → Cursor), mức độ bao phủ của CI và cú pháp script ngoại tuyến.
- `scripts/check-hyprland.sh` — kiểm tra cú pháp và smoke test Lua cho Minimal/Immaterial Impulse, mẫu Matugen và đồng bộ hai skel; cần Lua 5.4 trở lên, không cần GPU.
- `scripts/check-live-aur.sh` — kiểm tra Calamares/packagechooser, helper installer, gói AUR, `python`/`nodejs`/`wine` và tàn dư builder ngay trong `airootfs.sfs` vừa dựng.
- `scripts/selftest-anios-aur-build.sh` — tự kiểm tra `anios-aur-build.sh` trên chroot giả (fake pacman/makepkg/runuser), không cần Arch Linux.
- `scripts/selftest-check-live-aur.sh` — tự kiểm tra `check-live-aur.sh` trên ảnh live giả cùng `unsquashfs` giả.
- `scripts/selftest-installer.sh` — mô phỏng giao diện Material Live/Install (và nhánh dự phòng KDialog), rồi kiểm tra pacstrap, staging dotfiles, lựa chọn GRUB/SDDM và finalizer trong sandbox.
- `scripts/selftest-build-iso-sudoers.sh` — tự kiểm tra bước "không có luật sudo `NOPASSWD` nào lọt vào ảnh" ở cuối `build-iso.sh` trên airootfs giả: `/etc/sudoers` mặc định của gói `sudo` phải sạch, luật thật phải bị bắt kèm `file:dòng`; không cần Arch Linux.
- `scripts/selftest-build-iso-permissions.sh` — tự kiểm tra bước khai báo `file_permissions` của `build-iso.sh` (mảng `ANIOS_FILE_PERMISSIONS`, hàm ghi và hàm đối chiếu) trên một profile `releng` giả: mọi mục phải nằm trong mảng mà `mkarchiso` thật sự nạp, còn thiếu khai báo, khai báo đường dẫn không có trong ảnh, `releng` đổi dòng mở mảng và mục sai định dạng đều phải bị chặn; không cần Arch Linux.
- `scripts/check-live-audio.sh` — kiểm tra dàn âm thanh ngay trong `airootfs.sfs` vừa dựng (tự đi theo symlink tuyệt đối, vì `unsquashfs -cat` không đọc được loại symlink đó).
- `scripts/selftest-check-live-audio.sh` — tự kiểm tra script trên một ảnh live giả, chạy trên mọi push/PR mà không cần Arch Linux.
- `scripts/selftest-anios-netcheck.sh` — tự kiểm tra `anios-netcheck` bằng `getent`/`curl`/`nmcli`/`resolvectl` giả trên cây `/etc` giả: DNS chết hẳn, DNS chỉ sai với tên Valve, IPv6 "nửa sống", captive portal, các bước `--fix`/`--fix-dns` và chế độ `--quiet` dùng cho unit.
- `scripts/selftest-apply-saved-cursor.sh` — tự kiểm tra `apply_saved_cursor.sh` (script áp theme con trỏ lúc Hyprland khởi động) với `hyprctl` giả trên cây icon giả: theme đã lưu được giữ, theme không được cài rơi về Adwaita, JSON hỏng/size sai không làm chết phiên, theme hyprcursor vẫn được nhận, và khi ảnh không có theme nào thì không gọi `hyprctl` để compositor giữ con trỏ mặc định.
- `.github/workflows/build-iso.yml` — dựng ISO tự động, kiểm tra ảnh live (gồm dàn âm thanh PipeWire: plugin SPA ALSA, unit người dùng, cấu hình bật sẵn và công cụ chẩn đoán; Calamares/packagechooser, helper installer, gói AUR, `python`/`nodejs`/`wine` và tàn dư builder), xuất artifact và phát hành release.
- `.github/workflows/profile-check.yml` — kiểm tra nhanh profile trên mỗi push và pull request, kèm các bài tự kiểm tra chạy trong vài giây (AUR, ảnh live, âm thanh, mạng, theme con trỏ, installer, quyền tệp trong ảnh).

## Kiểm tra nhanh

```bash
./scripts/check-profile.sh               # cấu trúc profile, danh sách gói, manifest AUR, ràng buộc CI
./scripts/check-hyprland.sh              # kiểm tra Lua bắt buộc (Arch: lua; Ubuntu: lua5.4)
./scripts/selftest-check-live-audio.sh    # logic đọc ảnh live (cần bash, không cần Arch)
./scripts/selftest-anios-netcheck.sh     # chẩn đoán/tự sửa mạng của phiên live trên /etc giả
./scripts/selftest-apply-saved-cursor.sh # theme con trỏ lúc vào phiên (hyprctl giả, không nhấp nháy vì theme thiếu)
./scripts/selftest-anios-aur-build.sh     # bước dựng gói AUR trong chroot giả
./scripts/selftest-check-live-aur.sh      # bước kiểm tra Calamares/gói AUR/python/nodejs/wine trong ảnh giả
./scripts/selftest-installer.sh           # mô phỏng chọn Live/Install và các bước cài hệ thống
./scripts/selftest-build-iso-sudoers.sh   # bước kiểm tra NOPASSWD ở cuối build-iso.sh trên airootfs giả
./scripts/selftest-build-iso-permissions.sh # bước khai báo file_permissions (quyền/bit thực thi) của build-iso.sh
```

Các bài kiểm tra chạy nhanh, không cần dựng ISO. Có thể đặt `LUA=lua5.4` nếu
trình thông dịch không có tên `lua`. Khi dựng ISO xong, kiểm tra thêm ngay trên ảnh thật:

```bash
./scripts/check-live-audio.sh work/x86_64/airootfs.sfs
./scripts/check-live-aur.sh  work/x86_64/airootfs.sfs
```

Lệnh kiểm tra không cần Arch Linux. Để tạo và kiểm thử ISO vẫn cần máy Archiso (hoặc máy ảo Arch Linux). Nên boot thử ISO với từng GPU trước khi phát hành.
