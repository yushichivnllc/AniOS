# AniOS — DEEP RESEARCH AUDIT (BƯỚC 1 → BƯỚC 4)

> Bằng chứng thu thập trực tiếp từ checkout `yushichivnllc/AniOS` @ `18489e7c3e22526168435c628992d413aaff830d`
> Lệnh dùng để kiểm kê: `git ls-files | wc -l` (3.437) · `find . -type f | xargs wc -l` theo phần mở rộng · `grep`/`diff` trên cây profile.

---

## BƯỚC 1 — CHUẨN HÓA ĐỊNH DANH & MỔ XẺ GITHUB REPO

### 1.1 Định danh đã chuẩn hóa

| Trường | Giá trị chốt | Cơ sở |
|---|---|---|
| Tên dự án | **AniOS — Live Gaming & AI Desktop Distribution** | Giữ tên (đã gắn với 3 ISO + cộng đồng); bổ sung "Distribution" để nói đúng bản chất: `ID=arch` bên trong, Arch-based |
| Dành cho ai | (1) Khách quán net ~70% · (2) Chủ quán/máy quầy POS · (3) DIY nội bộ | Đọc `profile/airootfs/usr/local/bin/anios-cafe` (có vai trò `pos`), `README.md` §"Chạy trong quán net" |
| Vấn đề cụ thể | Chuỗi 7 điểm gãy: boot không lên hình (GPU/VMD) → Steam offline (DNS/IPv6) → câm âm thanh (SPA ALSA) → giật game (thiếu Proton) → rò dữ liệu khách → treo máy không chẩn đoán được → **AniTails hứa Tor nhưng không cài Tor** | Đọc `anios-gpu-doctor`, `anios-netcheck`, `anios-audio-check`, `README.md` §Lỗi |
| Giải quyết thế nào | USB duy nhất đã nướng sẵn kernel/driver/Proton/audio/AI + lớp ghi persist + 5 công cụ tự chẩn đoán TTY | `profile/packages.x86_64`, `anios-steam-provision.sh`, `usr/local/bin/anios-*` (18 tool) |

### 1.2 Bản đồ cấu trúc repo (3.437 file)

```
AniOS/
├── profile/                      # archiso profile
│   ├── packages.x86_64           # manifest gói Live   (~200 gói)
│   ├── packages.aur.x86_64       # manifest AUR (calamares, yay, nvidia-580xx…)
│   ├── install/packages.x86_64   # manifest gói máy đích
│   ├── airootfs/                 # overlay hệ thống
│   │   ├── etc/                  # systemd units, pacman hook, PAM, sysctl, SDDM autologin, Firefox policies
│   │   ├── usr/local/bin/        # 18 CLI chẩn đoán/điều khiển  (~3.1k LOC)
│   │   ├── usr/local/lib/anios/  # 4 thư viện (cafe.sh, gpu-env.sh, create-live-user, live-home-setup)
│   │   ├── usr/share/anios/skel/ # 1.526 file dotfile
│   │   └── usr/share/{sddm,grub,wayland-sessions}
│   ├── editions/{anios,aniterals,anix}/edition.conf   # 3 bản ISO
│   ├── installer/                # Calamares: 15 module .conf + 5 script + branding + licenses
│   └── branding/                 # wallpaper.png 2560×1440 (2,7 MB) · syslinux-splash.png 640×480
├── scripts/                      # 25 script · ~10.700 LOC bash
│   ├── build-iso.sh (1.626) · check-profile.sh (1.418) · anios-aur-build.sh (935)
│   ├── check-live-audio.sh · check-live-aur.sh · check-hyprland.sh
│   └── selftest-*.sh × 14        # ~1.900 LOC — tự kiểm tra offline
├── apps/
│   ├── anios-manga/              # PySide6/QML · 10 QML · 11 test file + 7 fixture
│   └── anios-reddit/             # PySide6/QML · 6 QML · 5 test file + 3 fixture
├── design/ (CHƯA CÓ — đề xuất mới) · docs/ (mới) · Makefile (mới)
├── .github/workflows/            # build-iso.yml (44 KB) · profile-check.yml (17 KB)
└── tests/hyprland-config.lua
```

### 1.3 Quy mô đo được

| Chỉ số | Giá trị |
|---|---|
| File tracked | 3.437 |
| Tổng LoC (QML+JS+PY+SH+LUA+CSS) | ~247.000 |
| QML / JS / Python / Bash / Lua / CSS | 1.963 / 282 / 134 / 127 / 47 / 10 file |
| Shell Quickshell (IMI) | 805 module QML + 282 service JS + 14 file dịch |
| Câu lệnh Lua Hyprland | 4.597 |
| Bash (scripts/) | ~10.700 |
| Python + QML (2 app) | 7.750 |

### 1.4 Điểm yếu & nợ kỹ thuật đã xác minh

| # | Vấn đề | Bằng chứng lệnh | Mức độ |
|---|---|---|---|
| 1 | **Cây skel nhân đôi 100%** | `find profile/airootfs/etc/skel -type f \| wc -l` = 1.526 = `…/usr/share/anios/skel` | 🔴 nghiêm trọng |
| 2 | **Pytest không hề chạy trong CI** | `grep -rn pytest .github/workflows/*.yml` → **0 kết quả** | 🔴 nghiêm trọng |
| 3 | **Không có lint nào** (shellcheck/luacheck/ruff/mypy) | `grep -rn "shellcheck\|luacheck\|ruff\|mypy" .github/workflows/*.yml` → **0** | 🟠 cao |
| 4 | **AniTails không có Tor** dù README quảng bá | `grep -i tor profile/packages.x86_64 profile/editions/aniterals/edition.conf` → chỉ khớp chữ trong comment | 🔴 lời hứa sai |
| 5 | **2 app chưa vào ISO** | README §"Chưa làm": *"cần thêm gói `pyside6`"* | 🟠 cao |
| 6 | **Manifest máy đích thiếu Mesa/Vulkan/lib32** | `profile/install/packages.x86_64` dừng ở `xorg-xwayland`, không có `mesa`, `vulkan-*`, `lib32-*` → máy cài lên **không chạy được game** | 🔴 nghiêm trọng |
| 7 | **Monolith Bash** không module | `build-iso.sh` 1.626 LOC, `check-profile.sh` 1.418 LOC | 🟠 cao |
| 8 | **Không tái lập / không SBOM** | `grep "SOURCE_DATE_EPOCH\|SBOM" .github/workflows/*.yml` → **0** (chỉ có sha256 file) | 🟠 cao |
| 9 | **5 hệ màu cạnh tranh** | GRUB `#004CB6` · SDDM `#0A1626` · Waybar `#2F6BE8` · IMI Material3 sinh động · **anios-manga dùng tím `#7C4DFF`** | 🟠 cao |
| 10 | 805 module QML nạp không kiểm soát | không có manifest lazy-load | 🟡 trung bình |
| 11 | Bảo mật: live password `1111` + autologin | `etc/shadow` (hash), `10-anios-autologin.conf` | 🟡 chấp nhận có chủ đích, **nhưng thiếu bộ quét bí mật tự động** |
| 12 | Không có `Makefile`, không có `CONTRIBUTING`/`SECURITY`/`docs/` | `ls` gốc repo | 🟡 trung bình |

**Kết luận Bước 1:** nền tảng kỹ thuật **rất tốt** (14 selftest offline, 5 công cụ chẩn đoán, 3 edition, build CI rất kỹ). Điểm yếu **không nằm ở chất lượng ý tưởng** mà nằm ở: **trùng lặp cấu trúc**, **thiếu lint/test trong CI**, **lời hứa không khớp sản phẩm**, và **thiếu một design system chung**.

---

## BƯỚC 2 — QUY HOẠCH CHỨC NĂNG (60.000 LoC)

### 2.1 Chức năng cốt lõi hiện có (đã kiểm kê đầy đủ, 12 miền)

| # | Miền | Chức năng đã có (đường dẫn thật) |
|---|---|---|
| 1 | **Dựng ISO** | `build-iso.sh` (3 edition, `--clean/--skip-checks/--no-aur/--edition all`), `build-all-editions.sh`, `anios-aur-build.sh` (fallback AUR→GitHub→cgit, retry, phân loại lỗi → annotation CI), `anios-steam-provision.sh` |
| 2 | **Kiểm định** | `check-profile.sh` (1.418 LOC, ~15 nhóm kiểm tra), `check-live-audio.sh` (đọc symlink tuyệt đối qua `unsquashfs -ll`), `check-live-aur.sh`, `check-hyprland.sh` (Lua smoke test 3 hồ sơ GPU) |
| 3 | **Tự kiểm tra** | 14 `selftest-*.sh` chạy offline, không cần Arch: aur-build, cafe, dmesg-check, gpu-doctor, netcheck, session, steam-setup, apply-saved-cursor, build-iso-nvidia-params, build-iso-permissions, build-iso-sudoers, check-live-audio, check-live-aur, editions, installer |
| 4 | **Cấu hình hệ thống** | systemd units (anios-cafe-watchdog, live-home, netcheck, persist, steam-autostart/quit), pacman hook `anios-live-user.hook`, PAM `anios-live`, sysctl `90-anios-live.conf`, zram-generator, tmpfiles, udev USB readahead |
| 5 | **Desktop** | 2 phiên: `anios-minimal` (Waybar + Mako + Fuzzel + foot) và `anios-imi` (Quickshell Immaterial Impulse 805 module); thêm `anios-safe`; `anios-switch-desktop`; `anios-session` (dbus-run-session, tự lùi safe mode) |
| 6 | **Phần cứng** | `anios-gpu-doctor` (601 LOC, `--fix`), `anios-dmesg-check` (299 LOC, 3 mức VÔ HẠI/CHÚ Ý/CẦN SỬA), `anios-audio-check`/`-setup`, `anios-netcheck` (514 LOC, `--fix/--fix-dns`), `gpu-env.sh` (AQ_DRM_DEVICES), mkinitcpio drop-in NVIDIA + VMD |
| 7 | **Game** | Steam + lib32, gamemode/gamescope/MangoHud, Proton (chính thức + GE ở Anix), VKD3D, protontricks, Steam Runtime (`anios-steam-setup` giải nén offline, **không bao giờ chặn Steam**), Sober (Roblox) qua Flatpak |
| 8 | **AI cục bộ** | ollama-vulkan, llama-cpp, whisper-cpp, ggml-vulkan, ggml-openvino, openvino + intel-gpu-plugin, onnxruntime-cpu; panel AI trong IMI (AiChat, AiRag, AiMemory, AiPersonas, AiToolRegistry, AiInline, AiDictation…) |
| 9 | **Trình cài** | Calamares + 15 module conf (locale → Asia/Ho_Chi_Minh, GeoIP tắt, packagechooser GRUB/SDDM/dotfile, users, partition, bootloader, shellprocess pacstrap/skel/finalize), theme Grubphemous, theme Qylock |
| 10 | **Lưu trữ & riêng tư** | `anios-persist` (phân vùng ext4 ANIOS_PERSIST, copytoram=n), AniTails copytoram=y + journald RAM, `anios-cafe` (dọn dữ liệu khách, watchdog reboot, vai trò `pos`) |
| 12 | **App nội bộ** | `anios-manga` (2 nguồn: MangaDex + thư viện cục bộ, 3 chế độ đọc, tải offline, SQLite), `anios-reddit` (OAuth read-only, feed/bình luận) |

### 2.2 Lộ trình "Ultimate Evolution" — 5 chiều (chi tiết trong Master Prompt §2.2–§2.6)

1. **Code & Architecture Perfection** → `scripts/lib/*.sh` (10 module) + `scripts/checks/*.sh` (8 module) + `apps/anios_core` + `design/tokens.json` + `Makefile`; mọi file ≤ 600 LOC; cây skel 1 nguồn.
2. **Feature Perfection** → 12 tính năng mới: Tor thật cho AniTails, manifest máy đích đầy đủ Mesa/Vulkan/lib32, `anios-doctor`+`anios-report`, `anios-ai`+`anios-ai-doctor`, **AniOS Hub** (app thứ 3), nướng 2 app vào ISO, kênh cập nhật + rollback, `anios-cafe` seat-policy + nhật ký kiểm toán, LUKS tuỳ chọn cho persist, gettext cho toàn CLI.
3. **Performance Perfection** → ngân sách đo được: boot ≤ 25 s, ISO ≤ 4,0 GiB, RSS Minimal ≤ 600 MiB, RSS IMI ≤ 1,4 GiB, lazy-load 805 module, index SQLite, retry/backoff HTTP, giải nén Proton song song.
4. **Security & Reliability Perfection** → `anios-verify-no-secrets.sh` (regex GitHub/Google/DISCORD/Reddit/private key), systemd hardening, build tái lập + SBOM + sha256, self-healing 3 tầng (reboot → safe mode → `anios-doctor --auto`).
5. **DX & Testing Perfection** → CI mới `quality.yml` (shellcheck · luacheck · ruff · pytest ≥85 % · qmllint · 18 selftest), `Makefile` 8 target, `docs/{ARCHITECTURE,DESIGN-SYSTEM,RUNBOOK}.md` + `ADR/`, `CONTRIBUTING`/`SECURITY`/`CODEOWNERS`, dựng ISO trong container để hạ rào cho contributor.

---

## BƯỚC 3 — TƯ DUY NGƯỢC (INVERSION THINKING)

> *"Nếu dự án 60K LoC này thất bại / bị bỏ xó, nguyên nhân là gì?"*

### 3.1 Góc kỹ thuật & Repo
| Suy đoán thất bại | Kiểm chứng | Giải pháp đảo ngược |
|---|---|---|
| Spaghetti — 2 bản skel lệch nhau, 3 file bash > 1.000 LOC | 2 × 1.526 file trùng lặp | **C1** 1 nguồn + CI chặn lệch; **C2** mọi file ≤ 600 LOC |
| Test suite có nhưng không ai chạy → hỏng âm thầm | 0 pytest trong CI | **C3** test phải là gate của PR |
| Sửa lỗi không kèm test → tái phát | Lịch sử lỗi trong README (sudoers, skeleton, ALSA) | **P3** mọi fix kèm selftest < 5 s |
| Build 40 phút, không tái lập, không cache | `SOURCE_DATE_EPOCH` = 0 kết quả | **C5** reproducible + SBOM + cache pacman |
| Docs 100 KB dạng "cẩm nang lỗi" → khó dùng | README 100.242 byte | README 3 tầng + RUNBOOK triệu chứng→lệnh |

### 3.2 Góc kinh doanh & người dùng
| Suy đoán thất bại | Kiểm chứng | Giải pháp đảo ngược |
|---|---|---|
| **Lời hứa sai** = mất niềm tin tuyệt đối | AniTails "có Tor" nhưng ảnh không có `tor` | **C4** mọi tuyên bố phải có bài kiểm chứng trong CI |
| Khách không vào được game trong 60 s → bỏ USB | 7 điểm gãy chuỗi | P1 "không chặn" + 2 Enter là vào game |
| Khách sau thấy dữ liệu khách trước → mất niềm tin | đã có `anios-cafe` | mở rộng seat-policy + nhật ký kiểm toán + role `pos` |
| Chủ quán sợ máy tự reboot giữa ca | đã có `--pos` | khóa bằng test + badge "POS" trên thanh trạng thái |
| Người dùng không rành kỹ thuật bị "chết" khi lỗi | 5 tool rời rạc | `anios-doctor`/`anios report` — 1 lệnh, 1 file, đã redact |
| Sản phẩm có app riêng nhưng app không nằm trong sản phẩm | README §"Chưa làm" | **C8** nướng 2 app + AniOS Hub vào ảnh, có bài CI đọc `airootfs.sfs` |
| 5 hệ màu → trông như "assembled" | tím `#7C4DFF` trong app vs Gura Blue | **C7** `design/tokens.json` là nguồn duy nhất |

### 3.3 8 nguyên tắc sống còn (C1–C8) + 3 nguyên tắc dự án (P1–P3)
→ Đã đóng gói vào Master Prompt §1.

---

## BƯỚC 4 — ĐỒNG BỘ HÓA IMAGE STYLE (200 OK) & UX/UI

### 4.1 Lớp DA — Visual Skin (trích từ `profile/branding/*`)

- **Ảnh 1 — `wallpaper.png` (2560×1440):** chủ đề **Gura Blue** (Gawr Gura): nền xanh cobalt→cyan có lưới mờ, panel khung truyện tranh viền xanh đậm, wordmark "GAURA" trắng đậm.
- **Ảnh 2 — `syslinux-splash.png` (640×480):** logo **AniOS** trắng đậm trên nền navy sâu `#12151D` với quầng sáng xanh ở giữa, chữ "Hyprland live gaming desktop" và "Arch Linux based".

**Palette trích bằng ImageMagick (`convert -colors 16 -format %c histogram:info:`):**

| Nhóm | HEX đã trích |
|---|---|
| Trắng/ánh sáng | `#F8F8F8` · `#D6E1EA` · `#DDE2ED` · `#AEAFC4` · `#A8D7E9` |
| Xanh điện | `#4AAFEE` · `#34AEEF` · `#56A0DC` · `#2398E7` · `#0120E8` · `#0F65DF` |
| Cyan | `#59CBE9` · `#33CAEF` |
| Navy/tối | `#292C39` · `#3C5FAF` · `#141B27` · `#12151D` · `#0D1118` |
| Nhấn | `#BD4A5A` · `#4E95AF` |

**Token chuẩn đã dùng trong code (để hợp nhất):** `#2F6BE8` primary · `#6FB5F0` hover · `#1D5BE0` press · `#EAF4FD` text · `#7E97B8` dim · `#0A1626` surface · `#10233C` field · `#1E4266` border · `#55708F` muted · `#4EA6EA` · `#3EC3D8` · `#D8404F` danger · GRUB `#004CB6` / `#E5EFFF` / `#BEDAFF`.

→ **Bảng HEX chuẩn cuối cùng: Master Prompt §3.1.**

### 4.2 Lớp XƯƠNG & HÀNH VI — đắp bộ xương của UX lên da

- **Xương (bố cục/luồng):** chuỗi GRUB → SDDM → màn chào 2 thẻ → desktop; 2 phiên Minimal/IMI; 3 trạng thái Steam; 4 vai trò `anios-cafe`; 7 màn hình AniOS Manga; 6 màn hình AniOS Reddit; 3 phiên Wayland (`anios`, `anios-minimal`, `anios-imi`, `anios-safe`).
- **Da (màu/chữ/bo góc):** Gura Blue + Noto Sans + bo 10/16 + pill + frosted `rgba(10,22,38,.72)` + blur chỉ lớp phủ + gradient viền 45°.
- **Mâu thuẫn phát hiện & cách hoà giải:** `anios-manga` dùng Material tím `#7C4DFF` (lệch hẳn Gura Blue) → chuyển sang `#2F6BE8` + `#3EC3D8`; IMI sinh màu động bằng Matugen → **giữ cơ chế Matugen** nhưng nguồn màu phải là `design/tokens.json`; theme Wuthering Waves có video → giữ video, thêm fallback tĩnh Gura Blue.

### 4.3 Danh mục UI Component cần đập lại (ánh xạ STEP 1)

| Nhóm | Thành phần | Hành động |
|---|---|---|
| Boot | GRUB Ayanami · SDDM `anios` · SDDM `wuwa` · `boot-choice.qml` | Đồng bộ Gura Blue, 2 thẻ, Enter = Live |
| Minimal | Waybar `config`+`style.css` · Fuzzel · Mako · foot · hyprlock · Thunar · polkit | Token hoá, cỡ chữ 13px, thêm badge persist/AI |
| IMI | 805 module QML + 282 service JS | Token chung, lazy-load, empty-state, đủ 14 bản dịch |
| Apps | Manga (10) + Reddit (6) + **Hub (mới)** | Bỏ tím, đồng bộ token, skeleton load, reader gestures |
| Installer | Calamares 15 module + branding | Preview đúng tông, thêm trang "Tóm tắt" |
| CLI/TUI | 18 `anios-*` + `anios` CLI gộp + `anios doctor --tui` | Một hệ thông thông điệp tiếng Việt có mã lỗi + lệnh sửa |
| Docs | README 3 tầng + RUNBOOK + ảnh chụp tự động (`make screenshots`) | Dùng `ANIOS_MANGA_SHOT`/`ANIOS_REDDIT_SHOT` đã có sẵn |

---

## PHỤ LỤC — LỆNH ĐÃ DÙNG ĐỂ KIỂM KÊ (tái lập được)

```bash
git ls-files | wc -l                                   # 3437
find . -type f -name "*.qml" | wc -l                   # 1963
find profile/airootfs/etc/skel -type f | wc -l          # 1526  (trùng với usr/share/anios/skel)
diff -rq profile/airootfs/etc/skel profile/airootfs/usr/share/anios/skel
grep -rn "pytest\|shellcheck\|luacheck\|ruff" .github/workflows/*.yml   # 0 kết quả
grep -rin "\btor\b" profile/packages.x86_64 profile/editions/aniterals/edition.conf
grep -n "mesa\|vulkan\|lib32" profile/install/packages.x86_64          # rất ít
wc -l scripts/build-iso.sh scripts/check-profile.sh scripts/anios-aur-build.sh
convert profile/branding/wallpaper.png -colors 16 -format %c histogram:info:
python3 -c "import struct;d=open('profile/branding/wallpaper.png','rb').read(33);print(struct.unpack('>II',d[16:24]))"
```
