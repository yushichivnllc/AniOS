AniOS — phiên live Arch Linux + Hyprland
========================================

Phím tắt chung:
Super+Return     Mở terminal (Foot)
Super+D          Mở launcher (Steam nằm trong đây)
Super+E          Mở trình quản lý file (Thunar)
Super+Shift+A    Kiểm tra âm thanh (mở công cụ chẩn đoán trong Foot)
Ctrl+Space       Bật/tắt gõ tiếng Việt (fcitx5 + Unikey)
Super+Space      Bật/tắt cửa sổ nổi
Super+Shift+L    Khoá màn hình (mật khẩu: 1111)
Ctrl+Alt+F2      Mở TTY cứu hộ (Ctrl+Alt+F1 để quay lại desktop)
Super+Shift+E    Thoát phiên Hyprland

Hai chế độ giao diện cài sẵn:
1. Immaterial Impulse (mặc định): Giao diện Material 3 tuyệt đẹp (https://github.com/XephyLon/immaterial-impulse) với Quickshell + Matugen và hình nền Gawr Gura.
2. AniOS Minimal: Giao diện nhẹ với Waybar + Mako, tối ưu cho GPU đời cũ.
- Chuyển đổi nhanh bất kỳ lúc nào:
    anios-switch-desktop imi       (chuyển sang Immaterial Impulse)
    anios-switch-desktop minimal   (chuyển sang AniOS Minimal)
    hoặc bấm đúp shortcut trên Desktop / phím tắt Super+Alt+M.
- Chọn phiên tại màn hình đăng nhập SDDM:
    AniOS (Immaterial Impulse) hoặc AniOS (Minimal / Waybar).

Cắm USB/ổ cứng ngoài: ổ sẽ tự hiện trong Thunar và trên thanh trạng thái.

Phần mềm cài sẵn trong ảnh (ngoài Steam, trình duyệt, Discord, VS Code...):
  Cốc Cốc Browser  trình duyệt Chromium tiếng Việt, tải media tốt
  Wine + Winetricks  chạy phần mềm/game Windows: wine <file.exe>
  Legacy Launcher  launcher Minecraft bản classic (llaun.ch) - cần Java
  Python 3 + pip   lập trình Python (python, pip)
  Node.js + npm    lập trình JavaScript/TypeScript (node, npm)
  Java OpenJDK     chạy app Java và Minecraft
  yay              cài thêm gói từ AUR ngay trong phiên live:
                     yay -S <tên gói>     cài gói (kể cả gói ngoài kho chính thức)
                     yay -Syu             cập nhật toàn bộ, gồm cả AUR
                     hoặc gõ: update-aur
  Seanime          server anime chạy nền ở http://127.0.0.1:43211, Firefox mở
                   sẵn trang này mỗi lần khởi động. Kiểm tra server:
                     seanime-status       (= systemctl status anios-seanime)
  Flatpak          cài và chạy ứng dụng từ Flathub (flatpak install <app-id>)
  AI cục bộ        Ollama backend Vulkan chạy nền (service bật sẵn):
                     ollama run <tên-model>   chat LLM trong terminal
                   llama-cpp / whisper-cpp cho dòng lệnh, OpenVINO tăng tốc
                   trên máy Intel. Tắt service nếu không dùng cho nhẹ RAM:
                     sudo systemctl disable --now ollama
  Jan AI           Chat offline kiểu ChatGPT, mở từ launcher (Super+D)
  LM Studio        Dò và chạy model GGUF bằng giao diện đồ hoạ (Super+D)
                   Model tải lần đầu cần Internet và nằm trong RAM của phiên
                   live; muốn giữ model giữa các lần boot thì trỏ OLLAMA_MODELS
                   (hoặc thư mục model của Jan/LM Studio) sang ổ USB gắn ngoài.

Không có tiếng?
AniOS tự bật dàn âm thanh PipeWire khi vào phiên, tự bỏ trạng thái tắt tiếng
mặc định của card ở lần vào desktop đầu tiên sau khi khởi động, và cảnh báo khi
thiết bị xuất là HDMI/DisplayPort trong khi máy còn cổng analog (loa phòng net
thường cắm jack 3.5mm). Nếu vẫn không nghe thấy gì:

  anios-audio-check           xem chỗ hỏng (hoặc bấm Super+Shift+A)
  anios-audio-setup --force   dựng lại dàn âm thanh
  pavucontrol                 chọn đúng thiết bị xuất
  alsamixer                   bật các kênh đang [off]

Mật khẩu tài khoản live và sudo là 1111. Hãy nhập mật khẩu này khi
mở khoá màn hình hoặc đăng nhập lại sau khi thoát phiên.

Lưu ý: đây là phiên live tạm thời. File cá nhân, tài khoản Steam và game cài
trong phiên sẽ mất khi tắt máy, trừ khi bạn dùng ổ ngoài có lưu trữ bền vững.

AniOS — Arch Linux based · https://github.com/yushichivnllc/AniOS
