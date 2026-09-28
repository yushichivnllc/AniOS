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
1. AniOS Minimal: Giao diện nhẹ với Waybar + Mako, tối ưu cho GPU đời cũ.
2. Immaterial Impulse: Giao diện Material 3 tuyệt đẹp với Quickshell + Matugen.
- Chuyển đổi nhanh bất kỳ lúc nào:
    anios-switch-desktop imi       (chuyển sang Immaterial Impulse)
    anios-switch-desktop minimal   (chuyển sang AniOS Minimal)
    hoặc bấm đúp shortcut trên Desktop / phím tắt Super+Alt+M.
- Chọn phiên tại màn hình đăng nhập SDDM:
    AniOS (Hyprland - Minimal) hoặc AniOS (Immaterial Impulse).

Cắm USB/ổ cứng ngoài: ổ sẽ tự hiện trong Thunar và trên thanh trạng thái.

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
