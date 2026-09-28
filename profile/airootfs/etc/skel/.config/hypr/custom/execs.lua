-- AniOS Custom Autostart for Immaterial Impulse
hl.on("hyprland.start", function()
    -- Dàn âm thanh PipeWire AniOS (bật unit, cấu hình âm lượng mặc định 50%)
    hl.exec_cmd("/usr/local/bin/anios-audio-setup --notify")
    -- Bộ gõ tiếng Việt fcitx5
    hl.exec_cmd("fcitx5 -d")
    -- Hình nền AniOS
    hl.exec_cmd("swaybg -i /usr/share/anios/wallpaper.png")
end)
