# Ma trận bài tự kiểm tra (selftest)

Mỗi bài ở đây là một script shell chạy trong **vài giây**, **không cần Arch
Linux**, **không cần root** và **không cần dựng ISO**. Chúng nạp đúng hàm cần
kiểm tra từ `scripts/build-iso.sh` hoặc từ script thật, rồi chạy trên cây giả
(sysfs giả, `hyprctl` giả, `unsquashfs` giả, airootfs giả…).

Nhờ vậy một lỗi lộ ra trong vài giây thay vì sau một lượt dựng ISO hàng chục
phút — hoặc tệ hơn, sau khi người dùng đã cài ISO lên máy thật.

Chạy tất cả:

```bash
make selftest
```

Chạy riêng một bài:

```bash
./scripts/selftest-<tên>.sh
```

---

## Ma trận

| Bài | Bảo vệ cái gì | Dùng khi nào | Thời gian |
| --- | --- | --- | --- |
| `selftest-skel-single-source.sh` | **C1**: bộ dotfile chỉ có MỘT nguồn (`profile/shared/skel`). Chặn mọi bản sao trong cây repo, đối chiếu các mục bắt buộc, và chứng minh `--stage` chép trung thành (symlink, quyền thực thi) — kể cả khi sinh từ cây đã qua `remove.paths` của edition | Sửa bất kỳ thứ gì trong `profile/shared/skel/`; thêm đường dẫn dotfile mới | < 1s |
| `selftest-installer.sh` | Bộ cài Calamares: `pacstrap`, dọn skeleton, chọn dotfile, finalizer. Chạy đúng `anios-installer-skel` trên **cây dotfile thật** của repo để bắt lỗi "Live password text remains in the target skeleton" (mã màu hex `#111111` từng làm hỏng mọi lượt cài) | Sửa `profile/installer/`, đổi bộ dotfile, đổi module Calamares | ~5s |
| `selftest-editions.sh` | Ba bản ISO dùng chung profile nền: bản amnesic không được mang Steam, Anix phải có tầng Proton riêng, gói dùng chung không được mất, manifest không được có dòng trùng; nạp đúng hàm `anios_apply_edition_packages()` | Thêm bản mới, đổi `packages.remove`, đổi `remove.paths` | ~2s |
| `selftest-anios-aur-build.sh` | `anios-aur-build.sh` chạy trong chroot lúc dựng ISO, với `pacman`/`makepkg`/`git`/`curl` giả: đọc sai manifest, thiếu phụ thuộc, chạy `makepkg` dưới root, quên `pacman -U`, dọn mồ côi làm mất gói, cấp sudo/NOPASSWD | Sửa `scripts/anios-aur-build.sh` hoặc `profile/packages.aur.x86_64` | ~3s |
| `selftest-check-live-aur.sh` | `check-live-aur.sh` đọc `airootfs.sfs` thật trong workflow dựng ISO: Calamares, helper installer, gói AUR, `python`/`nodejs`/`wine`, tàn dư builder | Sửa `check-live-aur.sh` hoặc danh sách gói | ~2s |
| `selftest-check-live-audio.sh` | `check-live-audio.sh` trên ảnh live giả, mô phỏng việc `unsquashfs -cat` từ chối symlink tuyệt đối | Sửa dàn âm thanh hoặc `check-live-audio.sh` | ~2s |
| `selftest-build-iso-sudoers.sh` | Bước cuối của `build-iso.sh`: **không** luật sudo `NOPASSWD` nào lọt vào ảnh. `/etc/sudoers` mặc định của gói `sudo` phải sạch, luật thật phải bị bắt kèm `file:dòng` | Đụng tới `sudoers`, PAM hoặc quyền root trong ảnh | < 1s |
| `selftest-build-iso-permissions.sh` | Khai báo `file_permissions` của `build-iso.sh` (mảng `ANIOS_FILE_PERMISSIONS`, hàm ghi, hàm đối chiếu) trên profile `releng` giả: mọi mục phải nằm trong mảng mkarchiso thật sự nạp | Thêm script mới vào `profile/airootfs/usr/local/bin/` | ~2s |
| `selftest-build-iso-nvidia-params.sh` | Tham số kernel NVIDIA (`nvidia_drm.modeset=1`, `fbdev=1`) trên GRUB/Syslinux/systemd-boot giả: mọi mục menu nhận đúng một lần, chạy lại không nhân đôi | Sửa `build-iso.sh` hoặc file boot | < 1s |
| `selftest-iso-aur-verify.sh` | Đối chiếu gói AUR với pacman DB của airootfs: đủ gói, thiếu gói, trùng tiền tố (`yay` vs `yay-bin`), `pkgver` kiểu epoch | Đổi `packages.aur.x86_64` | < 1s |
| `selftest-anios-netcheck.sh` | `anios-netcheck` với `getent`/`curl`/`nmcli`/`resolvectl` giả: DNS chết hẳn, DNS chỉ hỏng với tên Valve, IPv6 "nửa sống", captive portal, các bước `--fix`/`--fix-dns`/`--quiet` | Sửa script chẩn đoán mạng của phiên live | ~2s |
| `selftest-anios-session.sh` | `anios-session` với `dbus-run-session`/`Hyprland` giả: cờ `--safe` tới được cấu hình, Hyprland chết ngay được thử lại **đúng một lần**, nhật ký phiên có mã thoát | Sửa launcher của phiên | ~2s |
| `selftest-anios-gpu-doctor.sh` | `anios-gpu-doctor` trên cây sysfs/`/etc`/`/dev` giả: bắt `modeset=0`, thiếu `modprobe.d`/drop-in, `nouveau` giữ card, `efifb` giữ `fb0`, Intel VMD/RST; `--fix` ghi đủ, gọi `mkinitcpio`, không làm mất dòng khác | Sửa chẩn đoán GPU hoặc cấu hình NVIDIA | ~2s |
| `selftest-anios-dmesg-check.sh` | `anios-dmesg-check` trên nhật ký giả: lỗi firmware ACPI `AE_ALREADY_EXISTS` và `RAS: Correctable Errors` phải là VÔ HẠI (mã thoát 0), còn segfault/OOM/GPU treo phải là CẦN SỬA kèm lệnh tra cứu | Sửa phân loại lỗi kernel | < 1s |
| `selftest-anios-cafe.sh` | `cafe.sh` + `anios-cafe` trên cây `$HOME` giả: từ chối đường dẫn tuyệt đối/`..`, chỉ xoá danh sách cho phép, symlink trỏ ra ngoài không mất dữ liệu đích, giữ dotfiles Hyprland/`~/Desktop`, `--dry-run` không xoá gì, watchdog chỉ reboot khi đủ ngưỡng | Sửa chế độ quán net — đây là script **xoá dữ liệu** | ~3s |
| `selftest-anios-steam-setup.sh` | `anios-steam-setup` chạy lúc mở Steam lần đầu trên cache giả có tarball thật: giải nén Proton vào `compatibilitytools.d`, đặt Steam Runtime vào `ubuntu12_32`, bỏ qua khi đã cài, cài lại khi manifest đổi, **không bao giờ** chặn Steam khi cache thiếu/hỏng, và hoàn toàn offline | Sửa `anios-steam-setup` hoặc `anios-steam-provision.sh` | ~2s |
| `selftest-apply-saved-cursor.sh` | `apply_saved_cursor.sh` với `hyprctl` giả: theme đã lưu được giữ, theme chưa cài rơi về Adwaita, JSON hỏng/size sai không làm chết phiên, theme hyprcursor vẫn được nhận, và **không** gọi `hyprctl` khi ảnh không có theme nào | Sửa script theme con trỏ | ~1s |
| `selftest-gpu-env.sh` | Biến môi trường GPU NVIDIA + `AQ_DRM_DEVICES` của phiên Hyprland trên cây sysfs giả (chế độ chỉ-NVIDIA vs hybrid) | Sửa `gpu-env.sh` hoặc cấu hình NVIDIA | < 1s |

---

## Bài kiểm tra khác (không phải selftest)

| Bài | Bảo vệ cái gì | Cần gì |
| --- | --- | --- |
| `scripts/check-profile.sh` | Đặc tả toàn bộ profile: danh sách gói, ràng buộc AUR, cấu hình Calamares/installer, định danh AniOS, dotfile, âm thanh, múi giờ/NTP, theme con trỏ, mức độ bao phủ CI | `lua` (tuỳ chọn) |
| `scripts/check-hyprland.sh` | Cú pháp và smoke test Lua cho Minimal/Immaterial Impulse + mẫu Matugen, chạy với ba hồ sơ GPU (`default`, `ANIOS_GPU=nvidia`, `ANIOS_SAFE=1`) | Lua ≥ 5.4 |
| `scripts/sync-skel.sh --check` | Bất biến "một nguồn dotfile" (xem `selftest-skel-single-source.sh`) | không |
| `scripts/check-live-audio.sh` | Dàn âm thanh trong `airootfs.sfs` **thật** vừa dựng | ảnh đã dựng |
| `scripts/check-live-aur.sh` | Calamares/gói AUR trong `airootfs.sfs` **thật** vừa dựng | ảnh đã dựng |
| `make test` | `pytest` cho `apps/anios-manga` và `apps/anios-reddit` | Python 3.11 + PySide6 |
| `make lint` | `ruff` + `shellcheck` | ruff, shellcheck |
