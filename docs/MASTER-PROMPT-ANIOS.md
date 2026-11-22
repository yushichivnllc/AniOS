# SYSTEM PROMPT: ULTIMATE ARCHITECTURE & UX/UI BLUEPRINT (60,000 LoC — INFINITE PERFECTION EDITION)

> **Target repository:** `yushichivnllc/AniOS` (branch gốc `18489e7c3e22526168435c628992d413aaff830d` của `main`)
> **Quy mô thực tế đo được:** 3.437 file tracked · ~247.000 LoC (QML/JS/Python/Lua/CSS/Shell) · pipeline build ~10.700 LoC Bash · 2 app PySide6/QML · 1 shell Quickshell 805 module QML + 282 service JS · 3 bản ISO (AniOS / AniTails / Anix) · 2 bản SDDM · 1 theme GRUB · 2 phiên desktop (Minimal + Immaterial Impulse)
> **Visual source `{ IMAGE_UPLOAD }` (200 OK):** `profile/branding/wallpaper.png` (2560×1440, Gura Blue) + `profile/branding/syslinux-splash.png` (640×480, AniOS wordmark) — đã trích xuất bảng màu ở §3.1.

---

## 1. ĐỊNH DANH DỰ ÁN & MỤC TIÊU CỰC HẠN

- **Tên Dự án \*:** **AniOS — Live Gaming & AI Desktop Distribution (Infinite Perfection Edition)**

  *Vì sao giữ tên "AniOS":* tên đã gắn với ba bản ISO (AniOS / AniTails / Anix), với `ID=arch` bên trong, với cộng đồng và với cả 3.437 file hiện có. Đổi tên lúc này là đổi bản chất sản phẩm chứ không phải đổi nhãn. Nhưng phải làm rõ một điều mà tên hiện tại che giấu: **AniOS không phải một hệ điều hành, AniOS là một *bản phân phối* (distribution) của Arch Linux** — một sản phẩm gồm 3 bản ISO cài sẵn, một trình cài đặt, một stack AI cục bộ, và hai giao diện desktop. Bản nâng cấp này không đổi tên, nhưng **làm rõ trong toàn bộ tài liệu và giao diện rằng AniOS = Arch-based distribution**, đúng như `README.md` đã tự tuyên bố.

- **Mục tiêu Cốt lõi (Target Mode):**
  **CẢI TIẾN & TÁI CẤU TRÚC GITHUB REPO `yushichivnllc/AniOS` ĐẾN HOÀN HẢO CỰC HẠN VÔ CỰC.**
  Không dựng lại từ đầu. Mọi thay đổi phải: (1) giữ được hợp đồng hành vi hiện tại của 3 bản ISO; (2) giữ được toàn bộ 14 bài selftest đang chạy trong CI; (3) không phá vỡ đường cài hiện có của người dùng quán net (USB → boot → vào desktop → chơi game trong ≤ 60 giây).

- **Mô tả dự án \*:**
  + **Dành cho ai (Target Audience):** Ba nhóm người dùng với một điểm chung là **không có máy tính riêng và không có thời gian để cài hệ điều hành**:
    1. **Khách quán net** (đối tượng chính, ~70% lượt dùng): dùng máy tính dùng chung, muốn vào game/Steam/Discord ngay, không quan tâm bảo quản hệ thống, và **không được thấy dữ liệu của khách trước**.
    2. **Chủ quán / quản trị viên máy quầy (POS)**: cần máy *không bao giờ* tự khởi động lại giữa ca (mất hoá đơn) và *không bao giờ* bị dọn dữ liệu (mất phiên đăng nhập phần mềm bán hàng) — đã có vai trò `pos` trong `anios-cafe` nhưng mới dừng ở cờ cấu hình.
    3. **Người dùng DIY/nội bộ**: muốn một bản Arch đã cài sẵn Steam, Proton, driver NVIDIA, driver Intel/AMD, stack AI chạy offline, và bộ công cụ chẩn đoán tự chữa (đã có `anios-gpu-doctor`, `anios-dmesg-check`, `anios-netcheck`, `anios-audio-check` — nhưng rời rạc, chưa có lệnh hợp nhất).
  + **Vấn đề cụ thể (Core Problem):** "Cài game trên máy phòng net" nghe đơn giản nhưng thực tế là **một chuỗi 7 điểm gãy**: (a) USB boot không vào được desktop vì driver GPU/NVIDIA/VMD → màn hình đen; (b) vào desktop rồi nhưng Steam báo *"needs to be online"* vì DNS/IPv6 của mạng quán net; (c) âm thanh câm vì PipeWire không có plugin SPA ALSA; (d) game giật vì không có Proton/runtimes nướng sẵn; (e) khách sau thừa hưởng dữ liệu khách trước; (f) máy treo giữa ca và quản trị viên không biết chẩn đoán; (g) bản AniTails được quảng bá "Tor + amnesic" nhưng **thực tế không cài `tor` vào ảnh** — một lời hứa sai với người dùng.
  + **Giải pháp của App (Core Solution):** **Đóng gói sẵn toàn bộ chuỗi 7 điểm gãy thành một USB duy nhất**: kernel `linux-zen` + driver mã nồng mở & NVIDIA 580xx (nướng từ AUR trong chroot), Proton/Proton GE/Steam Runtime nướng sẵn có checksum, PipeWire + SPA ALSA bật sẵn, lớp ghi `ANIOS_PERSIST` trên USB (không mất dữ liệu khi reboot), stack AI cục bộ (Ollama-Vulkan, llama.cpp, whisper.cpp, OpenVINO) chạy không cần Internet, **và một lớp "self-healing" gồm 5 công cụ chẩn đoán TTY** để người không rành kỹ thuật cũng tự xử lý được trong 30 giây. Bản nâng cấp này biến "bộ sưu tập script dựng ISO" thành **một bản phân phối có hợp đồng chất lượng**: build tái lập được, có SBOM, có kiểm thử tự động, có design system một nguồn, và **không còn lời hứa nào trong README mà ảnh không thực sự làm**.

- **Chiến lược Chống Lỗ & Chống Thất Bại (Từ Tư Duy Ngược):**

  > *"Nếu AniOS 60K LoC này bị bỏ xó, nguyên nhân là gì?"* → 8 nguyên nhân đã được kiểm chứng bằng đọc code, và 8 quy tắc sống còn sinh ra từ đó:

  | # | Nguyên nhân thất bại (đã xác minh trong repo) | Quy tắc sống còn (bắt buộc trong mọi PR) |
  |---|---|---|
  | 1 | **Cây skel bị nhân đôi**: `profile/airootfs/etc/skel` và `profile/airootfs/usr/share/anios/skel` là **2 bản giống hệt, mỗi bản 1.526 file** (mỗi bản ~198k LoC Quickshell). Sửa một bản quên bản kia → máy live và máy đã cài lệch nhau. | **C1 — Single Source of Truth cho skel.** `profile/shared/skel/` là nguồn duy nhất; `scripts/sync-skel.sh` sinh ra các bản đích **trong ảnh** (`/usr/share/anios/skel`, `/etc/skel`, `/home/anios`); cây repo **không** chứa bản sao nào và CI **fail** nếu bản sao xuất hiện lại (bài `selftest-skel-single-source.sh`). Bản đích phải sinh từ cây **đã qua `remove.paths` của edition** để AniTails không hồi sinh `Steam.desktop`. |
  | 2 | **Monolith Bash**: `build-iso.sh` 1.626 LOC, `check-profile.sh` 1.418 LOC, `anios-aur-build.sh` 935 LOC — không có module, không có lint, mỗi lần sửa là cả một vùng nguy hiểm. | **C2 — Không file nào vượt 600 LOC.** Tách `scripts/lib/*.sh` theo miền; `check-profile.sh` trở thành runner gọi `scripts/checks/*.sh`. Bắt buộc `shellcheck -S warning` + `luacheck` trong CI. |
  | 3 | **Test chưa được nối vào CI**: `apps/*/tests/` có pytest + fixture đầy đủ nhưng **`grep -n pytest .github/workflows/*.yml` = 0 kết quả** → test suite có thể hỏng từ lâu mà không ai biết. | **C3 — Test phải chạy trong CI, không phải "nên có".** Mọi job đều chạy `make check` (shellcheck + luacheck + ruff + pytest + qmllint + 14 selftest). Test hỏng = PR đỏ. |
  | 4 | **Lời hứa sai với người dùng**: README quảng bá AniTails có "Tor" nhưng **không có `tor` trong `profile/packages.x86_64` cũng không có trong `edition.conf` của aniterals**. | **C4 — Không tính năng nào được tuyên bố nếu không có bài kiểm chứng tự động trong CI.** Thêm `tor`/`obfs4proxy`/`macchanger` + bài `check-live-animals` xác nhận chúng có mặt trong `airootfs.sfs`. |
  | 5 | **Không tái lập được**: không có `SOURCE_DATE_EPOCH`, không có SBOM, không pin phiên bản gói ở mức đủ để dựng lại cùng một ISO. | **C5 — Build tái lập được & truy vết được.** `SOURCE_DATE_EPOCH` cố định, danh sách file sắp xếp, `sha256sum` cho ISO + `pkglist`, SBOM CycloneDX sinh từ pacman DB, ghi kèm release. |
  | 6 | **Bảo mật "biết rõ nhưng chấp nhận"**: mật khẩu live `1111` nằm trong `/etc/shadow` của ảnh, autologin SDDM bật sẵn, `PASSWD: ALL` cho tài khoản live. Đúng là chấp nhận được cho live USB, nhưng **không có bộ quét tự động** nào chặn bí mật thật lọt vào ảnh. | **C6 — "Live ≠ Production".** Mọi bí mật thật (client ID, token, key) bị chặn bởi `anios-verify-no-secrets.sh`; mọi dịch vụ systemd có `NoNewPrivileges`/`ProtectSystem=strict`; mọi edition *không phải* live bắt buộc không có autologin. |
  | 7 | **UX rời rạc giữa 3 lớp giao diện**: GRUB (Ayanami xanh `#004CB6`), SDDM (AniOS navy + Wuthering Waves), desktop Minimal (Waybar "Gura Blue" `#2f6be8`), shell IMI (Material 3 do Matugen sinh động), và 2 app PySide6 (Manga dùng **tím `#7C4DFF`**, Reddit dùng màu riêng) — **5 hệ màu khác nhau trong một sản phẩm**. | **C7 — Một design system, một nguồn token.** `design/tokens.json` là nguồn duy nhất; Matugen/waybar/GTK/KDE/fuzzel/kitty/mako/hyprlock **và cả 2 app** đều uống từ đó. Không còn literal màu rải rác trong QML/CSS. |
  | 8 | **Ứng dụng của chính dự án chưa vào sản phẩm**: `apps/anios-manga` và `apps/anios-reddit` ghi trong README là *"Chưa đưa vào ISO: cần thêm gói `pyside6`…"* — hai app hoàn chỉnh, có test, nằm ngoài sản phẩm. | **C8 — Tính năng chỉ coi là có khi nằm trong ảnh.** Hai app phải được nướng vào ISO (`.desktop`, icon, launcher), có bài CI đọc thẳng `airootfs.sfs` xác nhận. |

  **Bổ sung — nguyên tắc bất di bất dịch của dự án (đã suy ra từ lịch sử lỗi trong README):**
  - **P1 — Không bao giờ chặn người dùng vào game.** Mọi bước tùy chọn (Steam runtime, Proton cache, AUR, Cốc Cốc) **luôn cảnh báo, không chặn** (đã làm đúng ở `anios-steam-setup` → giữ nguyên nguyên tắc này ở mọi tính năng mới).
  - **P2 — Mọi lỗi phải có thông điệp tiếng Việt + lệnh sửa cụ thể.** Đây là chuẩn đã được 5 công cụ chẩn đoán tuân thủ (`anios-gpu-doctor`, `anios-dmesg-check`, `anios-netcheck`, `anios-audio-check`, `anios-cafe`). Mọi công cụ mới **phải** theo đúng mẫu đó.
  - **P3 — Sửa lỗi phải kèm bài selftest** chạy trong vài giây, không cần Arch Linux (đúng tinh thần `scripts/selftest-*.sh` hiện có).

---

## 2. STEP 1 === { DESIGN & UPGRADE CHỨC NĂNG TRƯỚC } (60K LoC — INFINITE PERFECTION)

### 2.1 Bản đồ hiện trạng (đã kiểm kê — dùng làm mốc so sánh)

| Miền | Vị trí | Quy mô | Tình trạng |
|---|---|---|---|
| Pipeline dựng ISO | `scripts/build-iso.sh` | 1.626 LOC | Monolith, đúng chức năng nhưng khó bảo trì |
| Kiểm tra profile | `scripts/check-profile.sh` | 1.418 LOC | 1 file, nhiều miền kiểm tra lẫn nhau |
| Dựng gói AUR trong chroot | `scripts/anios-aur-build.sh` | 935 LOC | Có fallback 3 nguồn, có phân loại lỗi — tốt, giữ nguyên |
| Tự kiểm tra | `scripts/selftest-*.sh` (14 file) | ~1.900 LOC | Tốt nhất của repo — nhưng rời rạc, không có index, không có coverage matrix |
| Manifest gói | `profile/packages.x86_64`, `profile/packages.aur.x86_64`, `profile/install/packages.x86_64` | ~400 dòng | Tốt, nhưng **3 nguồn tr truth** cho cùng một "bộ gói" → dễ lệch |
| Overlay hệ thống | `profile/airootfs/etc`, `usr/local/bin` (18 tool), `usr/local/lib/anios` (4 lib) | ~4.500 LOC | Chất lượng cao — đây là "linh hồn" sản phẩm |
| Dotfile desktop | `profile/airootfs/{etc,usr/share/anios}/skel` | 2 × 1.526 file | **Trùng lặp 100%** → vi phạm C1 (đã đóng: nguồn còn ở `profile/shared/skel/`) |
| Shell Quickshell (IMI) | `skel/.config/quickshell/imi/` | 805 QML + 282 JS, 14 ngôn ngữ | Rất lớn, không có manifest lazy-load, không có design token riêng |
| Cấu hình Hyprland | `skel/.config/hypr/` | 4.597 LOC Lua | Tốt, có hồ sơ GPU 3 tầng (nvidia/safe/default) — giữ nguyên |
| Theme GRUB | `usr/share/grub/themes/ayanami` | 100 icon + 2,8k dòng PNG | Nguồn upstream đã pin commit — giữ nguyên |
| Theme SDDM | `usr/share/sddm/themes/{anios,wuwa}` | QML | 2 theme, chưa có theme AniOS "chuẩn" theo Gura Blue |
| Trình cài | `profile/installer/` (15 module conf + 5 script) | ~364 LOC | Gọn, tốt |
| App desktop | `apps/anios-manga` (10 QML), `apps/anios-reddit` (6 QML) | 7.750 LOC | Hoàn chỉnh, có test — **nhưng chưa vào ISO** |
| CI | `.github/workflows/{build-iso,profile-check}.yml` | 61 KB | Rất kỹ cho ISO, **rỗng cho app/lint/pytest** |

### 2.2 Kế hoạch tái cấu trúc (Refactoring Plan) — 5 chiều

**R1 — Kiến trúc pipeline (Modular Monolith cho hệ build).**
Tạo `scripts/lib/` với 10 module đúng trách nhiệm, mỗi module có API rõ ràng và **không được `source` lẫn nhau theo vòng**:
```
scripts/lib/common.sh      # log/info/warn/die có màu, trap ERR, run_step, đọc config chung
scripts/lib/manifest.sh    # đọc/ghi/validate package manifests (live | target | aur), trả về mảng chuẩn hoá
scripts/lib/edition.sh     # resolve edition.conf → hợp đồng edition (ANIOS_EDITION_*), apply/diff 3 bản
scripts/lib/profile.sh     # stage profile archiso tạm (releng → AniOS): kernel zen, autologin, timezone, agetty
scripts/lib/permissions.sh # ANIOS_FILE_PERMISSIONS → nguồn duy nhất (JSON) → sinh file_permissions + dùng để verify
scripts/lib/branding.sh    # wallpaper/splash/logo, sinh variant theo kích thước, kiểm tra kích thước
scripts/lib/sddm.sh        # stage + kiểm tra theme SDDM, tạo theme.conf
scripts/lib/calamares.sh   # stage module/branding/license của Calamares, kiểm tra packagechooser
scripts/lib/steam.sh       # nướng Proton/Proton GE/Runtime, cache + manifest sha256
scripts/lib/aur.sh         # wrapper gọi anios-aur-build.sh, chuẩn hoá lỗi → annotation CI
scripts/lib/verify.sh      # post-build assertions (iso identity, pkglist, audio, perms, secrets)
```
`scripts/build-iso.sh` còn **≤ 400 LOC** và chỉ còn vai trò *orchestrator*: parse args → `common.init` → `check-profile` → `edition.resolve` → `profile.stage` → `aur.build` → `mkarchiso` → `verify.*`.
`scripts/check-profile.sh` còn **≤ 200 LOC** (runner) + `scripts/checks/{structure,packages,editions,installer,desktop,security,ci-coverage,syntax}.sh` (mỗi file ≤ 300 LOC), mỗi check trả về 0/1 và in kết luận một dòng.

**R2 — Hạ nền tảng dữ liệu: một cây skel, một manifest gói.**
- `profile/shared/skel/` (nguồn) → `scripts/sync-skel.sh --check` (CI) và `--stage DEST [SRC]` (dựng ISO).
- Manifest gói: hợp nhất 3 file thành **1 file YAML + 3 profile lọc** (`profile/packages.base.yaml` + `profiles: {live, target, anix, aniterals}`), có `scripts/manifest-diff.sh` in chính xác gói nào của bản nào khác bản nào (thay vì 3 file phải đối chiếu thủ công). Giữ **đường dẫn cũ** (`profile/packages.x86_64`…) dưới dạng file sinh tự động tương thích để không phá script hiện có.

**R3 — Chuẩn hoá app desktop thành một hệ.**
Tạo gói dùng chung `apps/anios_core/` (Python ≥ 3.11):
`anios_core/http.py` (urllib + retry + backoff + timeout + proxy), `settings.py` (JSON 600, migrate version), `i18n.py` (chuỗi `vi`/`en`, gettext-style), `theme.py` (đọc `design/tokens.json` → QML singleton), `logging.py` (structured, redact secrets), `paths.py` (XDG).
`anios-manga` và `anios-reddit` chuyển sang dùng `anios_core`, giữ nguyên API công khai + fixture test.

**R4 — Tách lớp "runtime" khỏi "build".**
`profile/airootfs/usr/local/bin/anios-*` (18 script, ~3.100 LOC) được gom theo 4 nhóm và dùng chung `usr/local/lib/anios/`:
`lib/common.sh` (log, i18n msg, `require_cmd`), `lib/diag.sh` (thu thập log chẩn đoán dùng chung), `lib/net.sh`, `lib/gpu.sh`, `lib/steam.sh`.
Mục tiêu: mọi `anios-*` dùng chung **một** hàm in thông điệp tiếng Việt có màu, **một** cơ chế `anios_doctor_collect` để gom log.

**R5 — Quy hoạch lại thư mục (không đổi đường dẫn người dùng thấy).**
```
/apps/{anios-manga,anios-reddit,anios_core}
/design/{tokens.json, matugen/, qml/, gtk/, waybar/, logos/}
/docs/{MASTER-PROMPT-ANIOS.md, ARCHITECTURE.md, DESIGN-SYSTEM.md, RUNBOOK.md, ADR/}
/profile/{shared/, editions/, installer/, branding/, install/}
/scripts/{lib/, checks/, selftest/, build-iso.sh, ...}
/tests/{shell/, python/}
Makefile
```

### 2.3 Nâng cấp tính năng (Feature Perfection) — bảng phủ 12 miền

| Miền | Hiện có | Nâng cấp lên cấp "vô cực" | Tiêu chí nghiệm thu |
|---|---|---|---|
| **F1 Build tái lập** | Không | `SOURCE_DATE_EPOCH` từ commit, `mksquashfs -Xbcj x86-64 -b 1M`, sort file list, `mkarchiso` deterministic, `sha256` + `pkglist` + **SBOM CycloneDX** | Dựng 2 lần → sha256 ISO trùng (trừ timestamp) |
| **F2 Editions** | 3 bản (anios/aniterals/anix) | **Sửa AniTails cho đúng lời hứa**: thêm `tor`, `obfs4proxy`, `macchanger`, `kill-switch` app, tắt `NetworkManager` IPv6 leak, `journalctl` volatile, mask `anios-persist`, chặn `steam`/`flatpak`; thêm **kiểm tra tự động** `scripts/checks/editions.sh` | `grep '^tor ' pkglist` có mặt trong `anios-aniterals` |
| **F3 Steam/proton** | `anios-steam-provision.sh` + `anios-steam-setup.sh` | **Manifest sha256 cho từng tarball**; giải nén song song (`pv \| xargs -P`); Steam Runtime tải **có pin build-id** thay vì đoán URL (đã ghi trong README là cố ý — giữ nguyên nguyên tắc nhưng **ghi rõ trạng thái vào `steam.env`**); `steam -shutdown` an toàn hơn | `anios-steam-setup` không bao giờ chặn Steam; checksum khớp → báo rõ |
| **F4 Hệ điều hành máy đích** | `profile/install/packages.x86_64` | Bổ sung `linux-firmware` (đã có), `fwupd`, `pavucontrol` (thiếu?), `mesa`/`vulkan-*` cho máy đích (thiếu — manifest target **không có Mesa/Vulkan/32-bit**!), `pulseaudio`-free, `flatpak`, `yay` từ kho cục bộ, `tlp`/`powertop` cho laptop, `ananicy` chống lag | Máy cài lên từ ISO → Steam chạy được ngay (manifest target phải chứa đủ Mesa + lib32 + Vulkan) |
| **F5 Chẩn đoán** | 4 tool rời | **`anios-doctor` hợp nhất**: gọi cả 4 tool, gom log (`journalctl -b`, `dmesg`, `hyprctl`, `pacman -Q`) → `anios-report-<date>.tar.gz` + `.sha256`, **tự redact** token/client-id; thêm `anios-doctor --tui` (giao diện TTY) | 1 lệnh → 1 file báo cáo không chứa bí mật |
| **F6 Quán net** | `anios-cafe` (status/on/off/clean, vai trò `pos`) | Thêm **chính sách theo chỗ ngồi** (`seat policy`: dọn theo user/không theo), `--timer` (tự dọn sau N phút không hoạt động), **log kiểm toán** ai dọn gì lúc nào (ẩn danh), chống `rm -rf` ngoài allowlist (đã có — giữ và test thêm), `pos` = **cấm cả reboot lẫn dọn** (đã có — khóa bằng test) | `selftest-anios-cafe.sh` mở rộng đủ 4 vai trò |
| **F7 AI cục bộ** | `ollama-vulkan`, `llama-cpp`, `whisper-cpp`, `openvino`, `onnxruntime` + panel AI trong IMI | Thêm **`anios-ai`** CLI thống nhất (list/pull/run/bench/warm), **model cache tùy chọn** (tải sẵn 1 model 1.5B vào USB persist, có checksum, dung lượng 0 = không tải), **kiểm tra phần cứng AI** (`anios-ai-doctor`: Vulkan compute, RAM, VRAM, tốc độ token/s), tắt AI tự động khi RAM < 4 GB | `anios-ai doctor` in ra số token/s thật, không đoán |
| **F8 App nội bộ** | 2 app, **chưa vào ISO** | Nướng vào ISO: `pyside6` + `python-pyside6`, `.desktop`, icon, launcher từ `anios-app-*`; thêm **AniOS Hub** (app thứ 3): bảng điều khiển một cửa sổ (trạng thái GPU/audio/net/disk, nút mở game, quản lý persistence, cài app từ AUR, xem log) | `unsquashfs -ll airootfs.sfs | grep anios-manga` có mặt trong CI |
| **F9 AniOS Hub (app mới)** | — | 1 cửa sổ QML: Health (CPU/RAM/GPU/Temp), Storage (USB persist, dung lượng), Net (DNS/VPN), Audio, Games (Steam/Proton), AI (model), Apps (2 app + cài thêm), Support (gọi `anios-doctor`, copy log) | Mở ≤ 1 giây, không block UI (mọi tác vụ nặng chạy nền) |
| **F10 Bảo mật** | Firefox policies, live password 1111, autologin | `anios-verify-no-secrets.sh` (quét ảnh tìm client-id/token/key/AIza…/ghp_…), `systemd` hardening (`NoNewPrivileges`, `ProtectSystem=strict`, `ProtectHome=read-only` cho service), **tuỳ chọn LUKS cho `ANIOS_PERSIST`**, `archlinux-keyring` refresh trước khi build, `sigrok`/`pacman-key` verify | CI đỏ nếu phát hiện mẫu bí mật trong ảnh |
| **F11 Cập nhật & rollback** | `anios-update` (batch, zstd swap, NoExtract) | Thêm **kênh cập nhật** (repo local `anios-aur` đã có → dùng làm kênh chính), **rollback**: giữ 2 kernel, `pacman -U` khôi phục gói, snapshot `ANIOS_SNAPSHOT` (btrfs/zstd) trước khi nâng cấp lớn | `anios-update --dry-run` in kế hoạch trước khi chạy |
| **F12 Nhận ký & i18n toàn hệ** | Thông điệp CLI tiếng Việt rời rạc, UI IMI có 14 ngôn ngữ | Chuỗi CLI chuyển sang gettext (`locale/vi.po`, `en.po`); log `journald` ở **JSON** với `MESSAGE_ID`; `anios doctor --lang en` | Không còn chuỗi hardcode tiếng Việt rải rác trong shell |

### 2.4 Hiệu năng (Performance Perfection) — ngân sách đo được

| Mục tiêu | Ngân sách | Cơ chế đo | Cách đạt |
|---|---|---|---|
| Thời gian từ USB → desktop | **≤ 25 s** (SSD/iGPU), ≤ 60 s (HDD) | `systemd-analyze blame` + `bootchart` trong CI VM | Tắt service không cần (`anios-steam-autostart` chỉ khi Steam), `systemd-analyze` gate trong `check-profile` |
| Dung lượng ISO | **≤ 4,0 GiB** (đang 4–4,5) | `ls -lh out/*.iso` | `NoExtract` man/doc/locale dư, dọn `/usr/share/{doc,man,locale}`, `optipng` logo, zstd squashfs |
| RSS của phiên Minimal | **≤ 600 MiB** | `ps` tổng | Waybar + Mako + Fuzzel tối giảu, không tải module IMI khi ở Minimal |
| RSS của phiên IMI | **≤ 1,4 GiB** | `ps` tổng | **Lazy-load manifest cho 805 module QML** (chỉ nạp panel đang mở) |
| Thời gian nạp IMI | **≤ 3 s** | `Quickshell` log | Chia `modules/` theo nhóm tải theo nhu cầu |
| Thời gian giải nén Steam cache | **≤ 45 s** (SSD) | đo trong `anios-steam-setup` | Giải nén song song, kiểm tra `.part` an toàn |
| Truy vấn SQLite (app) | **≤ 50 ms** p95 | `EXPLAIN QUERY PLAN` | Index đầy đủ, WAL, `PRAGMA synchronous=NORMAL` |
| HTTP tải ảnh (manga) | ≤ 2 s/ả�, có `Retry-After` | log trong `http.py` | Retry lũy thừa + jitter, timeout theo loại |
| Tải đồng thời | Không mất tiến độ | test | Hủy request cũ khi đổi truyện/chương (đã có — giữ) |

### 2.5 Bảo mật & độ tin cậy (Security & Reliability Perfection)

- **Zero-Trust cho ảnh live:** mọi service do AniOS định nghĩa chạy với `DynamicUser` hoặc user riêng, `PrivateTmp`, `ProtectSystem=strict`, `NoNewPrivileges=yes`, `RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6`.
- **Bí mật:** `anios-verify-no-secrets.sh` quét `airootfs.sfs` với regex: `gh[pousr]_[A-Za-z0-9]{20,}`, `AIza[0-9A-Za-z\-_]{35}`, `client_secret`, `-----BEGIN [A-Z ]*PRIVATE KEY-----`, `password\s*[:=]\s*["'][^"']{6,}`, Discord/Reddit token. Chạy trong CI trên **cả 3 bản**.
- **Tính toàn vẹn:** `sha256` cho ISO + `pkglist` + `SBOM`; `pacman-key` verify trong build; `SOURCE_DATE_EPOCH`.
- **Self-healing 3 tầng:** (T1) watchdog tự reboot khi desktop chết lặp (đã có, giữ); (T2) `anios-session` tự lùi về **Safe mode** khi Hyprland chết ngay (đã có, giữ + mở rộng: ghi log vào `~/.local/state/anios/`); (T3) `anios-doctor --auto` thử tự sửa những lỗi đã biết (DNS, PipeWire user unit, quyền file, con trỏ) — tất cả đều **ghi log trước khi sửa**.
- **Quản lý bí mật người dùng:** client ID Reddit (đang lưu `~/.config/anios-reddit/config.json` quyền 600 — giữ, bổ sung kiểm tra quyền tự động + tự chmod nếu sai).

### 2.6 Trải nghiệm nhà phát triển & kiểm thử (DX & Testing)

1. **`Makefile` ở gốc** (không thêm dependency ngoài `make`):
   `make check` (shellcheck + luacheck + ruff + pytest + qmllint) · `make selftest` (14+ bài) · `make profile` · `make iso EDITION=anios` · `make doctor` · `make clean` · `make docs`.
2. **CI mới — `.github/workflows/quality.yml`** (chạy mỗi PR, < 4 phút):
   `shellcheck -S warning -x scripts/**/*.sh` · `luacheck profile/**/*.lua` · `ruff check apps/` + `ruff format --check` · `pytest apps/ -q --cov` (ngưỡng **≥ 85%** cho `anios_core`, ≥ 80% cho app) · `qmllint` (nếu có `qt6-tools`) · `make selftest` · **`pytest` phải được nối vào CI — đây là C3** · báo cáo coverage upload artifact.
3. **Ma trận selftest** (`tests/README.md`): mỗi bài ghi rõ — bảo vệ cái gì, dùng khi nào, chạy mất bao lâu. Bổ sung bài mới: `selftest-skel-sync.sh`, `selftest-manifest-diff.sh`, `selftest-anios-doctor.sh`, `selftest-tokens-consistency.sh` (token JSON ↔ CSS/QML), `selftest-iso-reproducible.sh`.
4. **Tài liệu:** `docs/ARCHITECTURE.md` (sơ đồ lớp), `docs/DESIGN-SYSTEM.md`, `docs/RUNBOOK.md` (xử lý sự cố theo triệu chứng → lệnh), `docs/ADR/` (quyết định kiến trúc), README tách 3 tầng: **Bắt đầu nhanh (2 phút)** · **Vận hành** · **Tham chiếu kỹ thuật**.
5. **Quy trình đóng góp:** `CONTRIBUTING.md` (luồng PR, quy tắc bắt buộc C1–C8), `SECURITY.md` (báo cáo lỗ hổng), `CODEOWNERS`, `pull_request_template.md` (checkbox "Tôi đã chạy `make check`", "Tôi đã thêm selftest", "Tôi đã cập nhật README").
6. **Công cụ dựng:** `make iso` chạy được trên máy không phải Arch (dùng container `archlinux:base-devel` giống CI) → hạ rào cản cho contributor.

### 2.7 Thứ tự triển khai (bắt buộc theo thứ tự này)

```
WAVE 0 — Lưới an toàn (1–2 ngày)
  S0.1 Nối pytest + shellcheck + luacheck + ruff vào CI (đóng C3)  ✅ xong
  S0.2 scripts/sync-skel.sh + check lệch skel (đóng C1)             ✅ xong
  S0.3 docs/README 3 tầng + Makefile + CONTRIBUTING                 ✅ xong
  → Chạy được toàn bộ mà KHÔNG đổi hành vi sản phẩm.

WAVE 1 — Tái cấu trúc pipeline (3–5 ngày)
  S1.1 scripts/lib/*.sh (10 module) + build-iso.sh còn ≤ 400 LOC
  S1.2 scripts/checks/*.sh + check-profile.sh còn ≤ 200 LOC
  S1.3 Manifest hợp nhất + scripts/manifest-diff.sh
  S1.4 apps/anios_core + chuyển 2 app sang dùng chung (giữ nguyên test)
  → Mỗi bước phải giữ 14 selftest xanh.

WAVE 2 — Hoàn thiện tính năng (4–6 ngày)
  S2.1 Sửa AniTails: Tor + kill-switch + MAC + kiểm tra CI
  S2.2 Manifest máy đích: bổ sung Mesa/Vulkan/lib32/fwupd/pavucontrol
  S2.3 anios-doctor + anios-report (+ TUI)
  S2.4 Nướng 2 app vào ISO + AniOS Hub (app thứ 3)
  S2.5 anios-ai + anios-ai-doctor
  → Mỗi tính năng mới kèm selftest + cập nhật README.

WAVE 3 — Hiệu năng & bảo mật (2–4 ngày)
  S3.1 Build tái lập + SBOM + checksum
  S3.2 Lazy-load 805 module QML + giảm ISO xuống ≤ 4,0 GiB
  S3.3 anios-verify-no-secrets + systemd hardening
  S3.4 Ngân sách boot/RAM gắn vào CI (gate)
  → Cuối WAVE 3: ISO 3 bản dựng sạch, tất cả job xanh.

>>> DỪNG LẠI, ĐƯA NGƯỜI DÙNG DUYỆT <<<

WAVE 4 — STEP 2: DESIGN & UPGRADE UX/UI (xem mục 3)
```

> **Lệnh thực thi Step 1:** *Hãy thiết kế / tái cấu trúc toàn bộ kiến trúc hệ thống, mã nguồn và luồng chức năng này TRƯỚC.* Bắt đầu bằng **WAVE 0**, mỗi bước phải kèm bài selftest và cập nhật README tương ứng; **không được** mở WAVE 4 trước khi WAVE 0–3 xanh hoàn toàn.

---

## 3. STEP 2 === { DESIGN & UPGRADE UX/UI SAU } (IMAGE STYLE 200 OK + ĐÚNG Ý USER)

### 3.1 HỆ THỐNG DESIGN TOKENS (trích xuất từ IMAGE `{ 200 OK }`)

**Nguồn ảnh:** `profile/branding/wallpaper.png` (2560×1440) — chủ đề **Gura Blue** (Gawr Gura, VTuber cá mập): nền xanh cobalt→cyan có lưới mờ, các panel "khung truyện tranh" viền xanh đậm, wordmark "GAURA" trắng đậm. `profile/branding/syslinux-splash.png` (640×480) — logo **AniOS** trắng đậm trên nền navy sâu với quầng sáng xanh ở giữa.

- **Aesthetic & Mood:** *"Ocean-tech anime" — xanh biển sâu + cyan điện, tương phản cao, khối bo góc mềm, ánh sáng neon nhẹ, chữ đậm rộng, cảm giác nhanh & sạch như game HUD nhưng vẫn dùng được cho công việc.* Nhịp thị giác: **nền tối → bề mặt xanh navy → điểm nhấn cyan → chữ trắng**. Tuyệt đối tránh tím/vàng loè (đang là lỗi của `anios-manga`).

- **Color Palette (mã HEX chuẩn — nguồn duy nhất: `design/tokens.json`):**

  | Vai trò | HEX | Nguồn |
  |---|---|---|
  | `bg.base` | `#0D1118` | boot-choice gradient dưới + splash `#12151D` |
  | `bg.deep` | `#12151D` | syslinux splash |
  | `surface.1` | `#0A1626` | Waybar/SDDM surface hiện tại |
  | `surface.2` | `#14233A` | lớp nâng cao |
  | `surface.3` | `#293951` | chip/avatar (boot-choice) |
  | `surface.field` | `#10233C` | ô nhập (SDDM) |
  | `border.subtle` | `#1E4266` | viền pill Waybar |
  | `border.strong` | `#344364` | splash `#344364` |
  | `primary` | `#2F6BE8` | token Gura Blue đang dùng trong code |
  | `primary.hover` | `#6FB5F0` | |
  | `primary.press` | `#1D5BE0` | |
  | `primary.electric` | `#0120E8` / `#0F65DF` | ảnh (mảng xanh đậm) |
  | `accent.cyan` | `#3EC3D8` | token hiện tại |
  | `accent.cyan.soft` | `#59CBE9` / `#33CAEF` | ảnh |
  | `accent.sky` | `#4AAFEE` / `#34AEEF` / `#56A0DC` | ảnh |
  | `text.primary` | `#EAF4FD` | token |
  | `text.on-media` | `#F8F8F8` | ảnh (trắng tuyệt đối) |
  | `text.secondary` | `#A8D7E9` / `#DDE2ED` | ảnh |
  | `text.dim` | `#7E97B8` | token |
  | `text.muted` | `#55708F` / `#667189` | token + splash |
  | `border.hairline` | `#455B7C` | chip boot-choice |
  | `status.success` | `#3EC3D8` | dùng chung cyan (đúng chủ đề) |
  | `status.warning` | `#F0B429` | thêm mới (nổi trên nền xanh) |
  | `status.danger` | `#D8404F` / `#BD4A5A` | token + ảnh |
  | `grub.desktop` | `#004CB6` | theme Ayanami |
  | `grub.item` | `#E5EFFF` | theme Ayanami |
  | `grub.timer` | `#BEDAFF` | theme Ayanami |

  **Quy tắc tương phản:** chữ trên `surface.1` ≥ 7:1 (AA+); trên `primary` dùng `#060F1C` (đen xanh) — đúng như Waybar đang làm; không dùng `#4AAFEE` làm nền chữ trắng.

- **Typography, Grid & Effects:**
  - **Font:** UI = **Noto Sans** (đã có trong image); hiển thị/wordmark = **Archivo Black** hoặc **Sora** (thêm vào manifest, dùng cho logo & splash); terminal/code = **JetBrains Mono Nerd** (đã có); icon = **Symbols Nerd Font** (đã có).
  - **Thang chữ:** 12 (trạng thái) · 14 (nội dung) · 16 (điều khiển) · 20 (tiêu đề phụ) · 28 (tiêu đề trang) · 46 (logo, đã dùng ở SDDM) — nhảy theo bội số 4.
  - **Grid:** nền 8px; lề chuẩn 16 (nội dung) / 24 (trang) / 32 (màn hình chào); **Safe Area ≥ 48px** ở mọi bố cục quan trọng (màn quán net thường có OSD của game làm rối).
  - **Bo góc:** 8 (nút nhỏ) · **10** (cửa sổ — khớp `decoration.rounding = 10`) · 16 (chip/avatar) · pill (module Waybar) · 999 (nút tròn).
  - **Đổ bóng:** 1 tầng mềm `0 8px 24px rgba(0,0,0,.45)` cho lớp nổi (card, panel, menu); không đổ bóng cho nền dán.
  - **Kính (frosted):** `rgba(10,22,38,.72)` + viền `1px rgba(30,66,102,.55)` (đang dùng ở Waybar — giữ nguyên số này, đẹp và rẻ).
  - **Blur:** chỉ áp cho lớp phủ (Waybar, Fuzzel, Mako, dock) — `size 6, passes 1, noise .02, contrast .9, vibrancy .2`; **cửa sổ thường KHÔNG blur** (nguyên tắc đã viết trong `hyprland-minimal.lua` — giữ nguyên, vì đây là quyết định đúng cho iGPU đời cũ).
  - **Micro-interactions:** hover 140ms `ease` (đúng như `style.css`); focus ring 2px `#4EA6EA` + 2px offset; pressed scale 0.98; không animation > 200ms; **tôn trọng `prefers-reduced-motion`** và `ANIOS_SAFE=1` (tắt toàn bộ).
  - **Viền cửa sổ đang chọn:** gradient 45° `#2F6BE8 → #4EA6EA` (giữ nguyên `hyprland-minimal.lua`).

### 3.2 CẤU TRÚC GIAO DIỆN & LUỒNG UX (chuẩn yêu cầu User & tối ưu chuyển đổi)

- **Ràng buộc UX/UI bắt buộc từ User (đã suy ra từ yêu cầu và từ chính hành vi sản phẩm):**
  1. **Ưu tiên máy phòng net**: mục tiêu phần cứng = GPU tích hợp Intel/AMD đời cũ, RAM 8 GB, màn 1366×768 @60Hz. → mọi hiệu ứng nặng phải tự tắt khi phát hiện GPU yếu.
  2. **Độ trễ từ USB đến game < 60 giây** — màn hình chào phải cho lựa chọn trong **≤ 2 click**.
  3. **Hai giao diện song song** (Minimal nhẹ ↔ IMI đẹp) phải **chuyển qua lại tức thì** và giữ đúng cài đặt riêng.
  4. **Tiếng Việt là ngôn ngữ mặc định**; chữ lớn, tương phản cao (khách ở quán net nhìn xa).
  5. **Mọi thao tác phải dùng được bằng bàn phím**; người dùng không biết Linux vẫn phải vào được game.
  6. **Không bao giờ chặn** bằng lỗi (P1): mọi bước tùy chọn chỉ cảnh báo.
  7. Giao diện phải **đồng nhất giữa GRUB → SDDM → desktop → app**, kể cả với `img` và `theme` cũ.

- **Tối ưu hóa trải nghiệm cho khách quán net (luồng chính, tối ưu số click):**
  ```
  Cắm USB → GRUB (mặc định "AniOS Live") → [Enter]
  → SDDM tự đăng nhập → màn chào (2 thẻ lớn, Enter = Live)
  → [Enter] → desktop Minimal tự bật → Steam tự mở (có Proton sẵn) → chơi
  ```
  **Tổng thao tác của khách: 0 click + 2 Enter.** Mọi màn hình phải có lựa chọn mặc định = đường vào game. Nếu Steam cache hỏng → **vẫn mở Steam được** (P1) và hiện 1 thông báo dạng toast, không modal chặn.

- **Tối ưu cho chủ quán (vai trò POS):** một lệnh `anios-cafe on --pos` khóa cả dọn dữ liệu lẫn tự reboot; hiển thị rõ trạng thái ở thanh trạng thái (biểu tượng "POS") để không ai vô tình bật sai.
- **Tối ưu cho người dùng DIY:** `anios-doctor` + `anios-report` là **đường cứu hộ chính**; mọi thông báo lỗi phải dẫn tới `anios doctor` bằng 1 dòng.

### 3.3 CHI TIẾT HÓA CÁC MÀN HÌNH & UI COMPONENTS (ánh xạ trực tiếp với STEP 1)

**A. Chuỗi khởi động (nơi người dùng nhìn thấy AniOS đầu tiên)**

| Màn hình | File | Việc phải làm ở STEP 2 |
|---|---|---|
| GRUB menu | `profile/airootfs/usr/share/grub/themes/ayanami/theme.txt` | Giữ nguyên Ayanami (đã đúng thương hiệu); thêm **mục "AniOS Live (mặc định)"**, "AniOS Live + lưu trữ", "AniTails — ẩn danh", "Anix — full Proton"; timer 5s; `title-text` rỗng (giữ). Không thêm hiệu ứng mới (GRUB không có GPU). |
| SDDM — theme AniOS | `usr/share/sddm/themes/anios/Main.qml` | **Tái lập theo Gura Blue**: nền = wallpaper + overlay `#0A1626` 55%, card bo góc 16, viền gradient `#2F6BE8→#4EA6EA`, logo "AniOS" 46px + tracking 2px, subtitle "Arch Linux based" (đúng như splash), ô nhập `#10233C` + viền `#1E4266`, nút đăng nhập `#2F6BE8` → `#4EA6EA`, thông báo lỗi `#D8404F`. Bỏ hiệu ứng cũ (chỉ có nền). |
| SDDM — theme Wuthering Waves | `usr/share/sddm/themes/wuwa/Main.qml` | **Giữ nguyên video** nhưng thêm **fallback tĩnh Gura Blue** (đã có `fallback.png`) + bảng màu đồng bộ; bảo đảm `onErrorOccurred` (đã có) → hiện nền tĩnh, không trắng xanh. |
| Màn hình chào Live | `usr/share/anios/boot-choice.qml` | **Tái thiết kế 2 thẻ lớn** ("Dùng thử AniOS Live" / "Cài đặt AniOS"), nền gradient `#141B27→#0D1118` + wallpaper mờ 12%, chip logo bo 16, nút chính `#2F6BE8`, nút phụ outline `#1E4266`, cảm ứng **Enter = Live**, **Esc = Live**, thẻ "Cài đặt" bị disable trong bản `--no-aur` (đã có → giữ + hiện lý do rõ ràng). Thêm **thanh tiến trình** "đang chuẩn bị" + 3 gợi ý ngắn (Steam sẵn sàng / Proton sẵn sàng / AI chạy offline). |

**B. Phiên Minimal (Waybar + Fuzzel + Mako + foot)**
- **Waybar:** giữ bảng màu & "viên thuốc" hiện tại (đã rất tốt); chuẩn hoá token về `tokens.json`; thêm module **trạng thái pin/persistence (`ANIOS_PERSIST`)** và **badge AI**; cỡ chữ tối thiểu 12px (đã có) — quán net cần đọc từ xa → **mặc định 13px**; thêm `--toggle` ẩn/hiện.
- **Fuzzel (launcher):** theme lấy từ token; kết quả có **icon + mô tả phím tắt + nhãn tiếng Việt**; tìm kiếm tiếng Việt không dấu (quan trọng!).
- **Mako (thông báo):** bo góc 16, bóng 24px, accent theo mức độ (`success/warning/danger`), tự ẩn 5s, hỗ trợ nút hành động.
- **foot (terminal):** font JetBrains Mono Nerd 12, `opacity .94`, viền `#1E4266`, bo góc 10, tab 8.
- **hyprlock:** nền blur + logo AniOS + đồng hồ lớn `#EAF4FD`, accent `#2F6BE8`, **không đổi bất cứ logic khóa nào** (đang dùng `pam_unix` — giữ nguyên, chỉ đổi màu).
- **Thunar / polkit-gnome:** dùng theme GTK từ token; **polkit phải hiện rõ "AniOS cần mật khẩu quản trị"** bằng tiếng Việt.

**C. Phiên Immaterial Impulse (Quickshell — 805 module)**
- **Thiết kế hệ thống:** tạo `design/qml/AniOSTheme.qml` (singleton) làm **nguồn màu duy nhất** cho toàn bộ 805 module + 2 app; cấu hình `matugen` sinh ra `tokens.json` → Matugen → CSS/Lua/INI hiện tại (giữ nguyên cơ chế Matugen đang có — chỉ **nguồn màu** đổi về token chuẩn).
- **Các màn hình chính cần chuẩn hoá lại:** `bar` (panel chính), `sidebarLeft` (AI Chat — 1.586 LOC), `sidebarRight`, `dock`, `overview`, `notificationPopup`, `settings` (mục cài đặt), `wallpaperSelector`, `regionSelector`, `cheatsheet` (bảng phím tắt — **phải có tiếng Việt**), `lock`, `screensaver`, `sessionScreen`, `phone` (scrcpy), `rgb` (OpenRGB), `lyrics`, `booru`, `gmail`, `onScreenDisplay`, `mediaControls`, `editMode`, `dropShelf`, `imageViewer`.
- **Yêu cầu bắt buộc:** (1) mọi module **lazy-load** để giữ RSS ≤ 1,4 GiB; (2) mọi chuỗi dùng hệ `translations/vi_VN.json` (đã có file → **phải đầy đủ**, không để trống); (3) mọi panel mới có **trạng thái rỗng** đẹp (empty state) thay vì trống trơn; (4) mọi thao tác huỷ được (Esc) và không kẹt UI.
- **AI panel:** là điểm khác biệt lớn của sản phẩm → làm nổi bật: chip trạng thái model, chip "local/offline", trợ lý ngữ cảnh (trích đoạn màn hình), trợ lý giọng nói (whisper), **tiết kiệm VRAM**: chặn model quá lớn khi RAM thấp.

**D. Hai app PySide6 — phải đồng bộ hoàn toàn với design system (đây là nơi đang lệch nặng nhất)**
| App | Màn hình | Việc phải làm |
|---|---|---|
| **anios-manga** | `Main` (nav 212px + StackView), `LibraryPage`, `ExplorePage`, `DetailsPage`, `ReaderPage` (3 chế độ đọc), `HistoryPage`, `DownloadsPage`, `SettingsPage`, `MangaCard`, `ChapterItem` | **Xoá tím `#7C4DFF`** → dùng `primary #2F6BE8` + `accent.cyan #3EC3D8`; nền `#0D1118`/`#0A1626`, chữ `#EAF4FD`; nav dạng "pill" như Waybar; bo góc 10 đồng nhất; Reader: nền đen `#0D1118`, thanh tiến trình mảnh 2px `#2F6BE8`, **gesture vuốt + phím ←/→ + Space**, thanh điều khiểng tự ẩn; lưới bìa 4 cột → 2 trên màn 1366×768; **skeleton load** thay vì spinner trần; thông báo lỗi tiếng Việt kèm nút "Thử lại" |
| **anios-reddit** | `Main`, `FeedPage`, `PostCard`, `PostPage`, `CommentItem`, `SetupPage` | Cùng token; `SetupPage` (nhập client ID) **tự giải thích tại sao cần** + link tới tr prefs; `PostCard` có thumbnail + tiêu đề + điểm + số bình luận; **thanh lọc sắp xếp** dạng chip (Nổi bật/Mới/Top/Đang lên/Gây tranh cãi); thời gian "5 giờ trước" tiếng Việt; xử lý **rate limit** với đếm ngược (đã có cơ sở) |

**E. Trình cài (Calamares) + CLI**
- **Calamares:** branding AniOS (`profile/installer/calamares/branding/anios`) + màu token cho `branding.desc`; các module `locale` (Asia/Ho_Chi_Minh), `packagechooser-*` (Grubphemous / Qylock / dotfile) giữ nguyên logic, nhưng **mỗi lựa chọn phải có preview ảnh đúng tông Gura Blue**; thêm trang "Tóm tắt" cuối trước khi cài (hiện chưa có) — liệt kê gói sẽ cài, kích thước tối thiểu 30 GB, cảnh báo mất dữ liệu.
- **CLI/TUI (phần "giao diện" của hệ thống):** `anios` (lệnh gộp duy nhất) với `help`/`status`/`doctor`/`report`/`cafe`/`ai`/`steam`/`net`/`gpu`/`audio`/`update`/`switch-desktop`; mọi thông báo **tiếng Việt, có mã lỗi, có lệnh sửa tiếp theo**; `anios doctor --tui` dùng đúng token, có thanh tiến trình và tổng kết "3/7 hạng mục OK".

**F. Tài liệu & onboarding (một phần của UX)**
- **README 3 tầng** (Quickstart 2 phút → Vận hành → Kỹ thuật), ảnh chụp thật từ `make screenshots` (dùng `ANIOS_MANGA_SHOT`/`ANIOS_REDDIT_SHOT` đã có sẵn!), và **một `docs/RUNBOOK.md`** dạng "triệu chứng → nguyên nhân → lệnh" (đã có nền tảng từ 5 công cụ chẩn đoán).
- **Ảnh chụp màn hình tự động** (`make screenshots`) dùng offscreen Qt — biến UI thành **hợp đồng có thể kiểm thử bằng hình ảnh** (snapshot test), bắt được hồi quy màu (ví dụ app lại dùng tím).

---

## 4. WORKFLOW COMMAND (LỆNH ĐIỀU KHIỂN THỰC THI)

Hãy xác nhận bạn đã nắm rõ toàn bộ kiến trúc **60.000 LoC** và mục tiêu **{ HOÀN HẢO CỰC HẠN VÔ CỰC }** của dự án **AniOS — Live Gaming & AI Desktop Distribution**.

Thực thi theo đúng trình tự đã khoá:

1. **STEP 1 — DESIGN & UPGRADE CHỨC NĂNG (trước):**
   - Bắt đầu **WAVE 0** (lưới an toàn: nối pytest/shellcheck/luacheck/ruff vào CI, đồng bộ cây skel, Makefile + tài liệu).
   - Tiếp **WAVE 1** (tách `scripts/lib/*.sh` + `scripts/checks/*.sh`, hợp nhất manifest, `apps/anios_core`).
   - Tiếp **WAVE 2** (AniTails có Tor thật, manifest máy đích đầy đủ, `anios-doctor`/`anios-report`, nướng 2 app vào ISO + AniOS Hub, `anios-ai`).
   - Tiếp **WAVE 3** (build tái lập + SBOM, lazy-load 805 module QML, siết bảo mật, gắn ngân sách boot/RAM vào CI).
   - **Mỗi bước phải kèm bài selftest, cập nhật README tương ứng, và giữ 14 selftest hiện có xanh.**

2. **DỪNG LẠI — BÁO CÁO & CHỜ DUYỆT** trước khi chạm vào bất kỳ file giao diện nào.

3. **STEP 2 — DESIGN & UPGRADE UX/UI (sau):** chỉ bắt đầu khi Step 1 đã xanh hoàn toàn.
   - Thiết lập `design/tokens.json` làm nguồn duy nhất (bảng màu §3.1) → nối vào Matugen → Waybar / GTK / KDE / Fuzzel / kitty / Mako / hyprlock → **Quickshell 805 module** → **2 app PySide6**.
   - Lột xác theo thứ tự: **(a)** chuỗi khởi động (GRUB → SDDM → màn chào) → **(b)** phiên Minimal → **(c)** phiên Immaterial Impulse → **(d)** AniOS Hub + 2 app → **(e)** trình cài + CLI/TUI → **(f)** tài liệu & ảnh chụp tự động.
   - Mỗi màn hình phải: đúng token, có empty state, có trạng thái lỗi tiếng Việt, dùng được bằng bàn phím, và **tôn trọng `ANIOS_SAFE` / `prefers-reduced-motion`**.

4. **ĐIỀU KIỆN NGHIỆM THU (bắt buộc cho cả 2 Step):**
   - `make check` xanh (shellcheck · luacheck · ruff · pytest ≥ 85% · qmllint).
   - `make selftest` xanh (≥ 18 bài, mỗi bài < 5 giây).
   - Cả 3 bản ISO dựng sạch từ `main`; `sha256` + SBOM + `pkglist` phát hành kèm release.
   - `anios-verify-no-secrets.sh` không phát hiện bí mật trong bất kỳ bản nào.
   - Có **một lệnh duy nhất** để người dùng báo lỗi: `anios report` → file `.tar.gz` đã redact.
   - **Không một tuyên bố nào trong README mà ảnh không thực sự làm** (đóng C4).

> *"Hoàn hảo không phải là thêm thứ. Hoàn hảo là: mọi thứ đã hứa đều có, mọi thứ đã có đều chạy, và mọi thứ hỏng đều tự nói ra cách sửa."*
