-- AniOS Custom Keybinds for Immaterial Impulse
-- Lưu ý: hl.bind trong Hyprland thêm mới chứ không ghi đè tổ hợp phím cũ.
-- Phải gọi hl.unbind trước khi gán lại để tránh chạy đồng thời 2 lệnh.

--#!
--##! AniOS
hl.unbind("CTRL + SUPER + ALT + Slash")
hl.bind("CTRL + SUPER + ALT + Slash",
    hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"),
    { description = "AniOS: Edit user keybinds" })

-- Phím tắt kiểm tra âm thanh AniOS (Super+Shift+A — gỡ Google Lens mặc định trước)
hl.unbind("SUPER + SHIFT + A")
hl.bind("SUPER + SHIFT + A",
    hl.dsp.exec_cmd([=[foot sh -c "/usr/local/bin/anios-audio-check; printf '\nNhấn Enter để đóng cửa sổ... '; read -r _"]=]),
    { description = "AniOS: Audio diagnostic check" })

-- Phím tắt chuyển đổi sang giao diện AniOS Minimal (Super+Alt+M — gỡ tắt mic mặc định trước)
hl.unbind("SUPER + ALT + M")
hl.bind("SUPER + ALT + M",
    hl.dsp.exec_cmd("/usr/local/bin/anios-switch-desktop minimal"),
    { description = "AniOS: Switch to Minimal desktop" })

-- Phím tắt mở menu phiên / đăng xuất (Super+Shift+E — đồng bộ với tài liệu AniOS)
hl.unbind("SUPER + SHIFT + E")
hl.bind("SUPER + SHIFT + E",
    hl.dsp.global("quickshell:sessionToggle"),
    { description = "AniOS: Session menu / Exit" })
hl.bind("SUPER + SHIFT + E",
    hl.dsp.exec_cmd("qs -c $qsConfig ipc call TEST_ALIVE || hyprctl dispatch 'hl.dsp.exit()'"))

