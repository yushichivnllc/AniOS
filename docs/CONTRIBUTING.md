# Đóng góp cho AniOS

AniOS là một bản phân phối Arch Linux cho desktop chơi game, có ba bản ISO
(`anios`, `aniterals`, `anix`) dùng chung một profile nền.

Mọi thay đổi đều phải giữ **hợp đồng hành vi**: bản live và bản đã cài phải
chạy giống nhau, và ảnh dựng được phải giữ nguyên hành vi của bản trước đó.

---

## 1. Trước khi mở pull request

```bash
make check
```

Lệnh này chạy đúng những gì CI chạy:

| Bước | Kiểm tra |
| --- | --- |
| `make lint` | `ruff check apps/` + `shellcheck -x -S error` cho mọi script shell (kể cả `profile/installer/scripts/`) |
| `make test` | `pytest` cho `apps/anios-manga` và `apps/anios-reddit` |
| `make selftest` | toàn bộ bài tự kiểm tra dạng shell (`scripts/selftest-*.sh`) |
| `make profile` | `scripts/check-profile.sh` — đặc tả profile, installer, Lua của bộ dotfile |

Nếu `make check` chưa chạy được vì thiếu công cụ, xem [mục 6](#6-cài-công-cụ).

---

## 2. Quy tắc bắt buộc

### C1 — Một nguồn dotfile duy nhất

Bộ dotfile nằm ở **một** chỗ duy nhất: `profile/shared/skel/`.

Trong ảnh nó xuất hiện ở `/usr/share/anios/skel`, `/etc/skel` và `/home/anios`,
nhưng cả ba đều là **sản phẩm dựng** do `scripts/sync-skel.sh` sinh ra.

- Sửa dotfile → sửa `profile/shared/skel/`, **không** sửa bản trong `profile/airootfs/`.
- Tuyệt đối không commit bản sao dotfile vào cây repo. `sync-skel.sh --check`
  (chạy trong `make profile`) sẽ chặn.
- Khi sinh bản đích trong ảnh, phải lấy từ **cây đã qua `remove.paths` của
  edition**, không phải từ nguồn trong repo — nếu không, AniTails sẽ hồi sinh
  `Desktop/Steam.desktop` trong ảnh amnesic.

Vì sao nghiêm trọng: sửa một bản mà quên bản kia là kiểu hỏng âm thầm tệ nhất —
mọi bài kiểm tra vẫn xanh, nhưng máy live và máy đã cài chạy hai bộ cấu hình
khác nhau.

### C2 — Một manifest gói cho mỗi tầng

- `profile/packages.x86_64` — ảnh live.
- `profile/install/packages.x86_64` — hệ thống đã cài.
- `profile/packages.aur.x86_64` — gói AUR (pacstrap không phân giải được AUR).
- `profile/editions/<id>/packages.x86_64` — gói riêng của từng bản.

Đừng thêm gói AUR vào manifest chính; đừng thêm gói của một bản vào manifest
nền.

### C3 — Test phải chạy trong CI

Mọi đoạn code mới phải kèm test và phải được CI gọi. Một lỗi chỉ lộ ra trên
máy người dùng là lỗi chưa được xử lý.

- Logic trong `scripts/` → bài `scripts/selftest-*.sh` chạy được **không cần
  Arch Linux, không cần root** (dùng cây giả: `hyprctl` giả, `unsquashfs` giả,
  sysfs giả…).
- Code Python trong `apps/` → `pytest` trong `apps/<app>/tests/`.
- Cấu hình Lua của bộ dotfile → `scripts/check-hyprland.sh`.

### C4–C8 — Tóm tắt

| Mã | Quy tắc |
| --- | --- |
| C4 | `file_permissions` phải khai báo **mọi** script trong ảnh (mkarchiso chép bằng `--no-preserve=mode`) |
| C5 | Không đụng tới `profile/editions/` khi không liên quan tới edition |
| C6 | Mọi thao tác ghi/xoá dữ liệu người dùng phải có `--dry-run` và chỉ xoá trong danh sách cho phép |
| C7 | Không thêm dependency ngoài mà không cần thiết; ưu tiên công cụ có sẵn trong Arch |
| C8 | Mọi thay đổi hành vi phải kèm bài selftest và cập nhật `README.md` |

---

## 3. Quy trình pull request

1. **Nhánh**: tạo nhánh từ `main`, đặt tên theo loại thay đổi
   (`fix/steam-autostart`, `feat/doctor`, `docs/…`).
2. **Thay đổi nhỏ, một ý mỗi lần**. PR sửa cả build lẫn app khó review và
   khó rollback.
3. **`make check` phải xanh.** Nếu không chạy được (thiếu `lua5.4`, thiếu
   PySide6), nói rõ trong PR và chạy được phần nào.
4. **Cập nhật tài liệu**: `README.md` cho hành vi người dùng thấy,
   `profile/editions/README.md` cho thay đổi theo edition.
5. **Mô tả PR** nói rõ: vấn đề, cách sửa, cách kiểm chứng, ảnh hưởng.

---

## 4. Bài tự kiểm tra (selftest)

Selftest là bài kiểm tra dạng shell chạy trong vài giây, **không cần dựng ISO**
và **không cần root**. Chúng nạp đúng hàm cần kiểm tra từ `build-iso.sh` hoặc
từ script thật, rồi chạy trên cây giả — nhờ vậy lỗi lộ ra trong vài giây thay
vì sau một lượt dựng ISO hàng chục phút.

Ma trận đầy đủ: [`tests/README.md`](../tests/README.md).

Khi thêm bài mới:

- đặt tên `scripts/selftest-<phạm vi>.sh`;
- in `OK`/`FAIL` rõ ràng cho từng trường hợp;
- trả về mã khác 0 khi có trường hợp sai;
- thêm vào `make selftest` (tự động nhận qua wildcard) **và** vào
  `.github/workflows/profile-check.yml`.

---

## 5. Dựng ISO

Cần máy Arch Linux có `archiso` + `grub` + quyền root:

```bash
make iso EDITION=anios        # hoặc aniterals, anix, all
```

Lượt dựng mất khoảng 25–40 phút. Trước khi phát hành, kiểm tra trên ảnh thật:

```bash
./scripts/check-live-audio.sh work/x86_64/airootfs.sfs
./scripts/check-live-aur.sh  work/x86_64/airootfs.sfs
```

---

## 6. Cài công cụ

```bash
# Python 3.11 + công cụ test/lint
python3 -m venv .venv-dev
.venv-dev/bin/pip install ruff pytest pytest-cov shellcheck-py "PySide6==6.12.0"

# Lua cho bài kiểm tra Hyprland
#   Arch:   sudo pacman -S lua
#   Ubuntu: sudo apt-get install -y lua5.4
```

Sau đó `make check` sẽ tự dùng `.venv-dev/bin/*` nếu có.

---

## 7. Báo cáo lỗ hổng

Xem [`SECURITY.md`](SECURITY.md).
