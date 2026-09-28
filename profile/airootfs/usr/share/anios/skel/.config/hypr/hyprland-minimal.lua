-- AniOS live desktop: Hyprland gọn nhẹ, hợp với GPU tích hợp đời cũ trong quán net.
--
-- Hyprland 0.55 trở lên đọc cấu hình Lua tại ~/.config/hypr/hyprland.lua;
-- định dạng hyprlang (.conf) cũ đã bị thay thế, nên đây là cấu hình chính thức
-- của phiên AniOS. Có thể tách ra nhiều file rồi nạp bằng require("ten_file").

-- Chương trình mặc định của AniOS: đặt ở đầu để các phím tắt dùng lại.
local mainMod  = "SUPER"
local terminal = "foot"
local menu     = "fuzzel"

-- Màn hình: để Hyprland tự chọn độ phân giải ưu tiên của từng máy quán net.
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1,
})

-- Tự chạy khi vào phiên (thay cho exec-once của định dạng cũ).
-- Dàn âm thanh chạy trước tiên: bật PipeWire + pipewire-pulse + WirePlumber,
-- rồi sửa trạng thái tắt tiếng mặc định của card. `--notify` hiện cảnh báo
-- ngay trên desktop (âm lượng 0%, thiết bị xuất đang là HDMI...) khi cần.
-- fcitx5 + Unikey cho tiếng Việt (bật/tắt bằng Ctrl+Space), sau đó là thanh
-- trạng thái, thông báo, mạng, polkit và hình nền AniOS.
hl.on("hyprland.start", function()
    hl.exec_cmd("/usr/local/bin/anios-audio-setup --notify")
    hl.exec_cmd("fcitx5 -d")
    hl.exec_cmd("waybar")
    hl.exec_cmd("mako")
    hl.exec_cmd("nm-applet --indicator")
    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")
    hl.exec_cmd("swaybg -i /usr/share/anios/wallpaper.png")
end)

hl.config({
    input = {
        kb_layout    = "us",
        follow_mouse = 1,
        sensitivity  = 0,
    },

    general = {
        gaps_in       = 3,
        gaps_out      = 6,
        border_size   = 2,
        layout        = "dwindle",
        allow_tearing = false,
        col = {
            active_border   = "rgba(7aa2f7ff)",
            inactive_border = "rgba(444a5eff)",
        },
    },

    decoration = {
        rounding        = 4,
        active_opacity   = 1.0,
        inactive_opacity = 1.0,
        blur = {
            enabled = false,
        },
        shadow = {
            enabled = false,
        },
    },

    animations = {
        enabled = false,
    },

    misc = {
        disable_hyprland_logo   = true,
        disable_splash_rendering = true,
    },

    -- VFR giúp giảm công việc render khi không có gì thay đổi; từ bản 0.56 khoá
    -- này nằm trong mục debug thay vì misc như trước.
    debug = {
        vfr = true,
    },
})

-- Ứng dụng.
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd("thunar"))

-- Cửa sổ.
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen())
hl.bind(mainMod .. " + space", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + SHIFT + space", hl.dsp.window.pin())
hl.bind(mainMod .. " + Q", hl.dsp.window.close())

-- Phiên: khoá màn hình, thoát và nạp lại cấu hình.
hl.bind(mainMod .. " + SHIFT + L", hl.dsp.exec_cmd("hyprlock"))
hl.bind(mainMod .. " + SHIFT + E", hl.dsp.exit())
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd("hyprctl reload"))

-- Chuyển focus theo hướng.
hl.bind(mainMod .. " + H", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + L", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + K", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + J", hl.dsp.focus({ direction = "down" }))

-- Workspace 1-3 và đưa cửa sổ đang chọn sang workspace đó.
for i = 1, 3 do
    hl.bind(mainMod .. " + " .. i, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
end

-- Phím âm lượng: thêm locked để vẫn chỉnh được khi màn hình đang khoá.
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })

-- Không có tiếng: mở công cụ kiểm tra âm thanh trong foot (giữ cửa sổ lại để
-- đọc kết quả). Công cụ này chỉ đọc trạng thái và phát thử một tiếng bíp; muốn
-- sửa thì chạy `anios-audio-setup --force` trong cửa sổ đó.
hl.bind(mainMod .. " + SHIFT + A",
    hl.dsp.exec_cmd([[foot sh -c "/usr/local/bin/anios-audio-check; printf '\nNhấn Enter để đóng cửa sổ... '; read -r _"]]))

-- Chụp màn hình: chọn vùng bằng slurp rồi đưa thẳng ảnh vào clipboard.
hl.bind("Print", hl.dsp.exec_cmd([[grim -g "$(slurp)" - | wl-copy]]))
