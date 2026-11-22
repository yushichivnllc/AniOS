-- AniOS Custom Autostart for Immaterial Impulse
hl.on("hyprland.start", function()
    -- Dàn âm thanh PipeWire AniOS (bật unit, cấu hình âm lượng mặc định 50%)
    hl.exec_cmd("/usr/local/bin/anios-audio-setup --notify")
    -- Bộ gõ tiếng Việt fcitx5
    hl.exec_cmd("fcitx5 -d")
    -- Hình nền AniOS (swaybg làm nền tức thì + matugen đồng bộ bảng màu Material 3)
    hl.exec_cmd("swaybg -i /usr/share/anios/wallpaper.png")
    hl.exec_cmd([[sh -c 'mkdir -p "$HOME/.local/state/quickshell/user/generated/wallpaper" "$HOME/.local/state/quickshell/user/generated/apps" && if [ ! -s "$HOME/.local/state/quickshell/user/generated/colors.json" ] && command -v matugen >/dev/null 2>&1; then matugen image /usr/share/anios/wallpaper.png --mode dark --type scheme-tonal-spot >/dev/null 2>&1 || true; fi']])
end)
