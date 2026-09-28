-- AniOS Custom Keybinds for Immaterial Impulse
hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Edit user keybinds"})

-- Phím tắt kiểm tra âm thanh AniOS (Super+Shift+A)
hl.bind("SUPER + SHIFT + A",
    hl.dsp.exec_cmd([=[foot sh -c "/usr/local/bin/anios-audio-check; printf '
Nhấn Enter để đóng cửa sổ... '; read -r _"]=]),
    { description = "AniOS: Audio diagnostic check" })

-- Phím tắt chuyển đổi sang giao diện AniOS Minimal (Super+Alt+M)
hl.bind("SUPER + ALT + M",
    hl.dsp.exec_cmd("/usr/local/bin/anios-switch-desktop minimal"),
    { description = "AniOS: Switch to Minimal desktop" })
