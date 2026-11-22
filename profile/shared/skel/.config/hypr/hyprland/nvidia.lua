-- Hồ sơ GPU/mức hiệu ứng của phiên, dùng chung cho cả hai desktop
-- (Minimal và Immaterial Impulse).
--
-- /usr/local/bin/anios-session đặt ANIOS_GPU sau khi đọc /usr/local/lib/anios/gpu-env.sh:
--   "nvidia"        máy chỉ có NVIDIA (hoặc NVIDIA là card chính của firmware)
--   "nvidia-hybrid" có iGPU lo phần xuất hình, NVIDIA chỉ render (PRIME)
--   "" (không đặt)  máy Intel/AMD, hoặc driver NVIDIA chưa nạp
-- ANIOS_SAFE=1 do `anios-session --safe` (phiên "AniOS - Safe") đặt, và cũng được
-- anios-session tự bật khi lần chạy đầu của Hyprland thoát ngay với mã lỗi.
--
-- Vì sao cần phân biệt: trên driver proprietary, mặt phẳng con trỏ phần cứng của
-- NVIDIA làm con trỏ nhấp nháy/lệch vị trí trong Hyprland, và VFR (variable frame
-- rate) làm hình rung khi có app vẽ liên tục. Hyprland khuyến nghị tắt cả hai
-- trên NVIDIA. Máy Intel/AMD vẫn giữ nguyên cấu hình cũ (VFR bật) cho mượt pin.

local profile = {
    nvidia = false,
    hybrid = false,
    safe = false,
    -- Con trỏ phần cứng của NVIDIA không ổn định dưới Hyprland.
    software_cursors = false,
    animations = true,
    blur = true,
    shadow = true,
    vfr = true,
}

local gpu = os.getenv("ANIOS_GPU") or ""
profile.nvidia = gpu:match("^nvidia") ~= nil
profile.hybrid = gpu == "nvidia-hybrid"
profile.safe = (os.getenv("ANIOS_SAFE") or "") == "1"

profile.software_cursors = profile.nvidia or profile.safe
profile.animations = not profile.safe
profile.blur = not profile.safe
profile.shadow = not profile.safe
-- VFR tắt trên NVIDIA (rung hình) và luôn tắt ở phiên an toàn.
profile.vfr = not profile.nvidia and not profile.safe

return profile
