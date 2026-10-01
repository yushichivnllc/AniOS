-- AniOS live desktop: Hyprland gọn nhẹ, hợp với GPU tích hợp đời cũ trong quán net.
--
-- Hyprland 0.55 trở lên đọc cấu hình Lua tại ~/.config/hypr/hyprland.lua;
-- định dạng hyprlang (.conf) cũ đã bị thay thế, nên đây là cấu hình chính thức
-- của phiên AniOS. Có thể tách ra nhiều file rồi nạp bằng require("ten_file").
--
-- Thẩm mỹ (bản "làm đẹp" cho chế độ Minimal):
--   * Bảng màu Gura Blue đồng bộ Waybar / Fuzzel / Foot / Mako / hyprlock.
--   * Viền cửa sổ đang chọn là gradient xanh -> cyan, bo góc 10px.
--   * Hiệu ứng giữ ở mức RẺ: animation fade/popin ngắn; blur chỉ dành cho các
--     layer phủ (waybar, fuzzel, mako) qua layerrule, cửa sổ thường KHÔNG blur;
--     shadow mềm chỉ vẽ cho cửa sổ nổi. iGPU đời cũ vẫn mượt.

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

-- Con trỏ chuột: theme Adwaita (đi kèm adwaita-icon-theme), cỡ 24 cho dễ nhìn
-- trên màn hình phòng net; giữ đồng nhất giữa các app GTK/Qt.
hl.env("XCURSOR_THEME", "Adwaita")
hl.env("XCURSOR_SIZE", "24")

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
        repeat_delay = 250,
        repeat_rate  = 35,

        touchpad = {
            natural_scroll       = true,
            disable_while_typing = true,
        },
    },

    general = {
        gaps_in          = 5,
        gaps_out         = 8,
        border_size      = 2,
        layout           = "dwindle",
        allow_tearing    = false,
        resize_on_border = true,

        col = {
            -- Viền cửa sổ đang chọn: gradient Gura Blue xanh -> cyan nghiêng 45 độ.
            active_border   = "rgba(2f6be8ff) rgba(4ea6eaff) 45deg",
            inactive_border = "rgba(1e4266ff)",
        },
    },

    decoration = {
        rounding         = 10,
        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        -- Bật công tắc blur nhưng cửa sổ thường đã bị `no_blur` chặn ở dưới;
        -- chỉ các layer phủ (waybar, fuzzel, mako) nhận blur qua layerrule,
        -- nên chi phí GPU chỉ bằng vài dải hẹp chứ không phải toàn màn hình.
        blur = {
            enabled           = true,
            size              = 6,
            passes            = 2,
            new_optimizations = true,
            noise             = 0.02,
            contrast          = 0.9,
            brightness        = 0.85,
            vibrancy          = 0.2,
            xray              = false,
        },

        -- Shadow mềm chỉ dành cho cửa sổ nổi (xem window_rule bên dưới).
        shadow = {
            enabled      = true,
            range        = 16,
            render_power = 3,
            offset       = { 0, 4 },
            color        = "rgba(00000040)",
        },

        -- Cửa sổ mất focus hơi tối đi một chút cho dễ nhận biết focus.
        dim_inactive = true,
        dim_strength = 0.06,
    },

    animations = {
        enabled = true,
    },

    dwindle = {
        preserve_split = true,
        smart_split    = false,
    },

    misc = {
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        mouse_move_enables_dpms  = true,
        key_press_enables_dpms   = true,
        focus_on_activate        = true,
    },

    cursor = {
        name = "Adwaita",
        size = 24,
    },

    -- VFR giúp giảm công việc render khi không có gì thay đổi; từ bản 0.56 khoá
    -- này nằm trong mục debug thay vì misc như trước.
    debug = {
        vfr = true,
    },
})

-- Đường cong animation: giảm tốc dần, không nảy mạnh để đỡ chóng mặt.
hl.curve("aniosDecel", {
    type   = "bezier",
    points = { { 0.05, 0.7 }, { 0.1, 1 } }
})
hl.curve("aniosMenu", {
    type   = "bezier",
    points = { { 0.1, 1 }, { 0, 1 } }
})

-- Cửa sổ: fade + popin ngắn (~nhẹ nhàng, không bay lượn).
hl.animation({ leaf = "windowsIn",  enabled = true, speed = 4, bezier = "aniosDecel", style = "popin 85%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 4, bezier = "aniosDecel", style = "popin 92%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 4, bezier = "aniosDecel", style = "slide" })
hl.animation({ leaf = "fadeIn",     enabled = true, speed = 4, bezier = "aniosDecel" })
hl.animation({ leaf = "fadeOut",    enabled = true, speed = 4, bezier = "aniosDecel" })
hl.animation({ leaf = "border",     enabled = true, speed = 8, bezier = "aniosDecel" })

-- Layer phủ (launcher, thông báo): trượt/mờ nhanh gọn.
hl.animation({ leaf = "layersIn",      enabled = true, speed = 3, bezier = "aniosMenu", style = "popin 95%" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 3, bezier = "aniosMenu", style = "popin 96%" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 3, bezier = "aniosMenu" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 3, bezier = "aniosMenu" })

-- Chuyển workspace trượt ngang nhanh.
hl.animation({ leaf = "workspaces", enabled = true, speed = 6, bezier = "aniosMenu", style = "slide" })

-- Cửa sổ thường KHÔNG blur: blur chỉ dành cho layer phủ bên dưới.
hl.window_rule({ match = { class = ".*" }, no_blur = true })

-- Cửa sổ xếp lưới không vẽ shadow (chỉ cửa sổ nổi mới cần bóng đổ).
hl.window_rule({ match = { float = 0 }, no_shadow = true })

-- Cửa sổ fullscreen thì bỏ bo góc để không hở viền đen ở mép màn hình.
hl.window_rule({ match = { fullscreen = 1 }, rounding = 0 })

-- Hộp thoại nhỏ nên nổi và nằm giữa màn hình cho dễ thao tác bằng chuột.
for _, dlg in ipairs({
    "^(pavucontrol)$",
    "^(org.pulseaudio.pavucontrol)$",
    "^(nm-connection-editor)$",
    "^(polkit-gnome-authentication-agent-1)$",
    "^(blueman-.*)$",
}) do
    hl.window_rule({ match = { class = dlg }, float = true })
    hl.window_rule({ match = { class = dlg }, center = true })
end
for _, dlg in ipairs({
    "^(Open File)(.*)$",
    "^(Select a File)(.*)$",
    "^(Open Folder)(.*)$",
    "^(Save As)(.*)$",
    "^(File Upload)(.*)$",
}) do
    hl.window_rule({ match = { title = dlg }, float = true })
    hl.window_rule({ match = { title = dlg }, center = true })
end

-- Game: bỏ vsync (immediate) để giảm input latency, giống chế độ imi.
hl.window_rule({ match = { title = ".*\\.exe" },        immediate = true })
hl.window_rule({ match = { title = ".*minecraft.*" },   immediate = true })
hl.window_rule({ match = { class = "^(steam_app).*" },  immediate = true })

-- Blur nhẹ cho các layer phủ bán trong suốt (ngưỡng ignore_alpha bỏ qua
-- phần viền trong suốt để không blur lãng phí).
hl.layer_rule({ match = { namespace = "waybar" }, blur = true, ignore_alpha = 0.2 })
hl.layer_rule({ match = { namespace = "waybar" }, no_anim = true })
hl.layer_rule({ match = { namespace = "fuzzel" }, blur = true, ignore_alpha = 0.2 })
hl.layer_rule({ match = { namespace = "mako" },   blur = true, ignore_alpha = 0.2 })

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

-- Đổi giao diện tại chỗ: Minimal <-> Immaterial Impulse.
hl.bind(mainMod .. " + ALT + M", hl.dsp.exec_cmd("/usr/local/bin/anios-switch-desktop toggle"))

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

-- Phím độ sáng màn hình (máy quán net hay laptop mang theo).
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl set 5%+"), { locked = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%-"), { locked = true })

-- Không có tiếng: mở công cụ kiểm tra âm thanh trong foot (giữ cửa sổ lại để
-- đọc kết quả). Công cụ này chỉ đọc trạng thái và phát thử một tiếng bíp; muốn
-- sửa thì chạy `anios-audio-setup --force` trong cửa sổ đó.
hl.bind(mainMod .. " + SHIFT + A",
    hl.dsp.exec_cmd([[foot sh -c "/usr/local/bin/anios-audio-check; printf '\nNhấn Enter để đóng cửa sổ... '; read -r _"]]))

-- Chụp màn hình: chọn vùng bằng slurp rồi đưa thẳng ảnh vào clipboard.
hl.bind("Print", hl.dsp.exec_cmd([[grim -g "$(slurp)" - | wl-copy]]))
