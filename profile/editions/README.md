# Ba bản ISO của họ AniOS

Cùng một profile nền (`profile/airootfs`, `profile/packages.x86_64`), ba bản dựng
khác nhau. Mỗi bản là một thư mục ở đây, và `scripts/build-iso.sh --edition <tên>`
ghép nó lên profile nền lúc dựng.

| Bản | File ISO | Điểm khác biệt chính |
| --- | --- | --- |
| **AniOS** (`anios`) | `anios-<ngày>-x86_64.iso` | Bản chính. Hyprland, **Steam tự khởi động**, Proton + Steam Runtime nướng sẵn, stack AI, lớp ghi trên USB. |
| **AniTails** (`aniterals`) | `aniterals-<ngày>-x86_64.iso` | Bản **amnesic**. Ảnh chạy trong RAM (`copytoram=y`), Tor, journal chỉ ở RAM, MAC ngẫu nhiên, **không Steam, không lưu trữ, không AUR**. |
| **Anix** (`anix`) | `anix-<ngày>-x86_64.iso` | Bản **đầy đủ nhất**. Mọi thứ của AniOS cộng Proton GE, VKD3D, `protontricks`, lớp kiểm chứng Vulkan 32-bit, thư viện lib32 bổ sung và công cụ theo dõi GPU. |

## Dựng

```bash
# Cả ba bản, một lần chạy (cần ~75 GiB chỗ trống cho ba work dir)
sudo ./scripts/build-all-editions.sh

# Từng bản riêng
sudo ./scripts/build-iso.sh --edition anios
sudo ./scripts/build-iso.sh --edition aniterals
sudo ./scripts/build-iso.sh --edition anix

# Cả ba, dùng thẳng build-iso.sh
sudo ./scripts/build-iso.sh --edition all
```

CI dựng cả ba trong một lần chạy: job `build` lo bản `anios` (kèm toàn bộ kiểm tra
sâu đã có từ trước), job `build-editions` là matrix `[aniterals, anix]`. Artifact tên
`anios-iso`, `anios-iso-aniterals`, `anios-iso-anix`.

## Cấu trúc một thư mục edition

Mọi file đều **tùy chọn** — thiếu nghĩa là bản đó dùng mặc định.

| File | Ý nghĩa |
| --- | --- |
| `edition.conf` | Biến đặc tả của bản. `build-iso.sh` `source` file này. |
| `packages.x86_64` | Gói **chỉ** bản này có. Chỉ được là gói kho chính thức (pacstrap đọc trực tiếp). |
| `packages.remove` | Gói **loại** khỏi manifest nền. Tên không có trong manifest thì bỏ qua im lặng. |
| `remove.paths` | Đường dẫn **trong ảnh** phải xóa sau khi overlay nền đã chép vào. Phải là đường dẫn tuyệt đối và phải tồn tại trong `profile/airootfs`, nếu không bản dựng dừng. |
| `airootfs/` | Overlay chép **sau** `profile/airootfs`, nên ghi đè được file của bản nền. Script có bit thực thi ở đây được tự khai báo vào `file_permissions`. |

### Biến trong `edition.conf`

| Biến | Mặc định | Ý nghĩa |
| --- | --- | --- |
| `ANIOS_EDITION_ID` | tên thư mục | Phải trùng tên thư mục. Ghi vào `/etc/anios/edition` trong ảnh. |
| `ANIOS_EDITION_NAME` | `AniOS` | Tên hiển thị. |
| `ANIOS_EDITION_ISO_NAME` | `anios` | Tiền tố tên file ISO. **Ba bản phải khác nhau**, nếu không chúng ghi đè nhau trong `out/`. |
| `ANIOS_EDITION_ISO_LABEL` | `ANIOS_$(date +%Y%m)` | Nhãn volume. Viết thẳng vào `profiledef.sh` nên `$(date)` do mkarchiso tính. |
| `ANIOS_EDITION_APPLICATION` | — | Chuỗi mô tả trong metadata ISO. |
| `ANIOS_EDITION_MENU_NAME` | `AniOS` | Tên trong menu khởi động Syslinux/GRUB/EFI. |
| `ANIOS_EDITION_COPYTORAM` | `n` | `y` = chép ảnh vào RAM rồi chạy từ đó (amnesic). `n` = đọc thẳng từ USB. |
| `ANIOS_EDITION_COW_SPACE_SIZE` | `10G` | Dung lượng lớp ghi tmpfs. |
| `ANIOS_EDITION_PERSISTENCE` | `1` | `1` = có mục menu lớp ghi `ANIOS_PERSIST`. `0` = bỏ hẳn khối lưu trữ bền vững. |
| `ANIOS_EDITION_AUR` | `1` | `0` = không dựng gói AUR (tương đương `--no-aur`). |
| `ANIOS_EDITION_SOBER` | `1` | `0` = không cài sẵn Sober (Roblox) từ Flathub. |
| `ANIOS_EDITION_STEAM_AUTOSTART` | `0` | `1` = ghi `/etc/anios/steam-autostart`, unit `anios-steam-autostart.service` sẽ mở Steam khi phiên sẵn sàng. |
| `ANIOS_EDITION_STEAM_PROVISION` | `off` | `standard` = nướng Proton chính thức; `full` = thêm Proton GE; `off` = không nướng. |

## Steam

Ba mảnh ghép, tách nhau rõ:

1. **`scripts/anios-steam-provision.sh`** — chạy **trong chroot lúc dựng ISO**, tải
   Proton (và Proton GE khi `level=full`) vào `/usr/share/anios/steam-cache`. Tải
   hỏng chỉ cảnh báo rồi bỏ qua: một lượt dựng hàng chục phút không nên chết vì
   mạng, và ảnh thiếu runtime vẫn mở được Steam. Bỏ qua hẳn: `ANIOS_SKIP_STEAM_PROVISION=1`.

   Steam Runtime **tắt mặc định**. Valve phát hành runtime Scout theo snapshot có
   build-id và đường dẫn thay đổi theo thời gian; đoán URL rồi nướng một bản sai
   vào ảnh tệ hơn là để Steam tự tải bản đúng. Muốn nướng thì truyền `--runtime-url`
   (hoặc đặt `ANIOS_STEAM_RUNTIME_URL`) trỏ tới tarball `steamrt_scout_*_amd64.tar.xz`
   đã kiểm tra.

2. **`profile/airootfs/usr/local/bin/anios-steam-setup`** — chạy **lúc người dùng mở
   Steam lần đầu**, giải nén cache vào `~/.local/share/Steam`. Hoàn toàn offline.
   Lý do không nhét Proton thẳng vào skeleton: home của tài khoản live được dựng lại
   từ `/usr/share/anios/skel` mỗi lần khởi động, nên vài GB Proton trong skel là vài
   GB bị chép mỗi lần boot. Giữ chúng **nén** trong squashfs rồi chỉ giải nén khi
   thật sự cần. Có file đánh dấu `.anios-provisioned` nên lần mở thứ hai trở đi
   không phải chờ, còn ISO mới (manifest khác) thì tự cài bản Proton mới.

   Script **không bao giờ chặn việc mở Steam**: cache thiếu hay tarball hỏng đều chỉ
   cảnh báo rồi trả về 0. `--strict` (dành cho CI) mới trả về khác 0.

3. **`profile/airootfs/usr/local/bin/anios-steam-autostart`** — chạy từ unit người
   dùng `anios-steam-autostart.service`, có `ConditionPathExists=/etc/anios/steam-autostart`
   nên chỉ bản nào ghi marker mới tự mở Steam. Unit đặt `Restart=no`: người dùng tắt
   Steam thì nó phải tắt, không khởi động lại thành vòng lặp. Ghi chữ `silent` vào
   file marker để Steam mở thu gọn xuống khay.

Mở Steam bằng `/usr/local/bin/anios-steam` (nạp `/etc/anios/steam/steam.env`, cài
runtime, rồi gọi Steam).

## AniTails và giới hạn của nó

Bản này chống **dấu vết để lại trên đĩa**, không phải chống forensic trên RAM đang
chạy: ảnh nằm trong RAM, journal `Storage=volatile`, swap bị tắt lúc khởi động
(`anitals-hardening`), MAC ngẫu nhiên. Ai đọc được RAM khi máy còn bật vẫn đọc được
dữ liệu của phiên.

`anitals-hardening --scrub-usb` ghi đè an toàn phân vùng `ANIOS_PERSIST` đang cắm —
dùng khi cắm nhầm USB từng chạy AniOS bản chính. Lệnh này **không bao giờ chạy tự
động**: xóa dữ liệu mà không ai yêu cầu là hành vi không chấp nhận được.

## Kiểm tra

```bash
./scripts/check-profile.sh            # đặc tả của cả ba bản + cách chúng được ghép
./scripts/selftest-editions.sh        # manifest của từng bản, CLI --edition
./scripts/selftest-anios-steam-setup.sh
```

`check-profile.sh` đối chiếu từng bản với chính đặc tả của nó: bản amnesic phải
`copytoram=y`, không persistence, không Steam, có Tor và journal volatile; AniOS và
Anix phải tự khởi động Steam và nướng runtime; Anix phải ở mức `full`.
