AniOS — phiên live Arch Linux + Hyprland
========================================

Super+Return     Mở terminal (Foot)
Super+D          Mở launcher (Steam nằm trong đây)
Super+E          Mở trình quản lý file (Thunar)
Super+Shift+A    Kiểm tra âm thanh (mở công cụ chẩn đoán trong Foot)
Ctrl+Space       Bật/tắt gõ tiếng Việt (fcitx5 + Unikey)
Super+Space      Bật/tắt cửa sổ nổi
Super+Shift+L    Khoá màn hình (mật khẩu: 1111)
Ctrl+Alt+F2      Mở TTY cứu hộ (Ctrl+Alt+F1 để quay lại desktop)
Super+Shift+E    Thoát phiên Hyprland

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

Chọn "Install Immaterial Impulse" trên Desktop để cài desktop Quickshell đầy
đủ của XephyLon (cần Internet, tải thêm nhiều gói).

Lưu ý: đây là phiên live tạm thời. File cá nhân, tài khoản Steam và game cài
trong phiên sẽ mất khi tắt máy, trừ khi bạn dùng ổ ngoài có lưu trữ bền vững.

AniOS — Arch Linux based · https://github.com/yushichivnllc/AniOS
