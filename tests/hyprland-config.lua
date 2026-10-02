-- Offline smoke test for the shipped Lua configs; no compositor/apps are started.
-- This is NOT a full Hyprland API emulator. The regression checks below follow
-- Hyprland v0.56.2's LuaConfigGradient.cpp and ConfigValues.cpp:
-- https://github.com/hyprwm/Hyprland/tree/v0.56.2/src/config
local config_dir, entry, mode, template = assert(arg[1]), assert(arg[2]), assert(arg[3]), assert(arg[4])
package.path = config_dir .. "/?.lua;" .. config_dir .. "/?/init.lua;" .. package.path

local function color(value)
    assert(type(value) == "string", "expected a single color string")
    local hex = value:match("^rgba%((%x+)%)$")
    assert(hex and #hex == 8, "expected rgba(RRGGBBAA), not a legacy gradient: " .. value)
end

local function gradient(value)
    if type(value) == "string" then
        color(value)
        return
    end
    assert(type(value) == "table" and type(value.colors) == "table" and #value.colors > 0,
        "gradient requires a color string or { colors = {...}, angle = number }")
    for _, item in ipairs(value.colors) do color(item) end
    assert(value.angle == nil or type(value.angle) == "number", "gradient angle must be numeric")
end

local configs, rules, binds, bind_list, events, commands, environment = {}, {}, {}, {}, {}, {}, {}
local function noop() end
local function dispatcher() return noop end
local function command(text)
    assert(type(text) == "string" and #text > 0, "empty exec command")
    commands[text] = true
    return noop
end
local function strict(api)
    return setmetatable(api, { __index = function(_, key) error("unexpected hl API: " .. key) end })
end

-- Mirrors Hyprland v0.56.2's modFromSv + parseKeyString in LuaBindingsToplevel.cpp:
-- every hl.bind chord must have a non-modifier key after its leading modifiers.
local valid_mods = {
    SHIFT = true, CAPS = true, CTRL = true, CONTROL = true,
    ALT = true, MOD1 = true, MOD2 = true, MOD3 = true,
    SUPER = true, WIN = true, LOGO = true, MOD4 = true, META = true,
    MOD5 = true,
}
local valid_bind_flags = {
    repeating = true, locked = true, release = true, non_consuming = true,
    auto_consuming = true, transparent = true, ignore_mods = true,
    dont_inhibit = true, long_press = true, submap_universal = true,
    description = true, desc = true, click = true, drag = true,
    device = true, allow_input_capture = true, mouse = true,
}
local function normalize_chord(chord)
    return (chord:gsub("%s+", ""):lower())
end
local function validate_chord(chord)
    assert(type(chord) == "string" and #chord > 0, "keybind chord must be a non-empty string")
    local tokens = {}
    for token in (chord .. "+"):gmatch("([^+]*)+") do
        tokens[#tokens + 1] = (token:gsub("^%s+", ""):gsub("%s+$", ""))
    end
    local seen_key = false
    for _, tok in ipairs(tokens) do
        assert(#tok > 0, "empty token in keybind chord: " .. chord)
        if valid_mods[tok] then
            assert(not seen_key, "modifier '" .. tok .. "' after key in chord: " .. chord)
        else
            seen_key = true
        end
    end
    assert(seen_key, "keybind chord '" .. chord .. "' has only modifiers and no key")
end

hl = strict({
    config = function(options)
        local cursor = options.cursor or {}
        assert(cursor.name == nil, "cursor:name is not a Hyprland option; use cursor environment variables")
        assert(cursor.size == nil, "cursor:size is not a Hyprland option; use cursor environment variables")
        local col = (options.general or {}).col or {}
        for _, value in pairs(col) do gradient(value) end
        local shadow = (options.decoration or {}).shadow or {}
        if shadow.color then gradient(shadow.color) end
        if shadow.render_power then
            assert(math.type(shadow.render_power) == "integer" and shadow.render_power >= 1 and shadow.render_power <= 4,
                "decoration:shadow:render_power must be an integer from 1 to 4")
        end
        configs[#configs + 1] = options
    end,
    window_rule = function(rule)
        if rule.border_color then gradient(rule.border_color) end
        rules[#rules + 1] = rule
    end,
    bind = function(key, action, flags)
        validate_chord(key)
        assert(type(action) == "function", "invalid keybind action for " .. tostring(key))
        if flags ~= nil then
            assert(type(flags) == "table", "hl.bind flags must be a table for " .. key)
            for k in pairs(flags) do
                assert(valid_bind_flags[k], "unknown hl.bind flag '" .. tostring(k) .. "' on " .. key)
            end
        end
        binds[key] = action
        bind_list[#bind_list + 1] = { key = key, norm = normalize_chord(key), action = action, flags = flags or {} }
    end,
    unbind = function(key)
        validate_chord(key)
        local norm = normalize_chord(key)
        for k in pairs(binds) do
            if normalize_chord(k) == norm then
                binds[k] = nil
            end
        end
        for i = #bind_list, 1, -1 do
            if bind_list[i].norm == norm then
                table.remove(bind_list, i)
            end
        end
    end,
    on = function(event, action)
        assert(event == "hyprland.start" and type(action) == "function", "unexpected event")
        events[#events + 1] = action
    end,
    env = function(key, value) environment[key] = value end,
    exec_cmd = command,
    monitor = noop, gesture = noop, layer_rule = noop, workspace_rule = noop,
    curve = noop, animation = noop,
    define_submap = function(_, action) action() end,
    dispatch = function(action) action() end,
    get_config = function() return 1 end,
    get_active_workspace = function() return { id = 1 } end,
    get_current_submap = function() return "" end,
    dsp = strict({
        exec_cmd = command, exit = dispatcher,
        focus = function(opts)
            assert(type(opts) == "table", "hl.dsp.focus requires a table argument")
            return noop
        end,
        global = function(name)
            assert(type(name) == "string" and name:find(":", 1, true), "hl.dsp.global requires 'app:name'")
            return noop
        end,
        layout = dispatcher, submap = dispatcher,
        window = strict({
            close = dispatcher, drag = dispatcher, float = dispatcher,
            -- Hyprland v0.56.2 dsp_fullscreen calls checkArgTypes(..., {LUA_TTABLE}):
            -- calling hl.dsp.window.fullscreen() with 0 args throws a Lua error.
            fullscreen = function(opts)
                assert(type(opts) == "table", "hl.dsp.window.fullscreen requires a table argument")
                if opts.mode ~= nil then
                    assert(opts.mode == "fullscreen" or opts.mode == "maximized",
                        "hl.dsp.window.fullscreen mode must be 'fullscreen' or 'maximized'")
                end
                return noop
            end,
            fullscreen_state = function(opts)
                assert(type(opts) == "table", "hl.dsp.window.fullscreen_state requires a table argument")
                return noop
            end,
            move = function(opts)
                assert(type(opts) == "table", "hl.dsp.window.move requires a table argument")
                return noop
            end,
            pin = dispatcher, resize = dispatcher,
        }),
        workspace = strict({ toggle_special = dispatcher }),
    }),
})

-- Ensure the guards really reject each previously shipped failure.
assert(not pcall(hl.config, { general = { col = { active_border = "rgba(2f6be8ff) rgba(4ea6eaff) 45deg" } } }))
assert(not pcall(hl.config, { cursor = { name = "Adwaita" } }))
assert(not pcall(hl.config, { cursor = { size = 24 } }))
assert(not pcall(hl.config, { decoration = { shadow = { render_power = 10 } } }))
assert(not pcall(hl.window_rule, { border_color = "rgba(afc6ffAA) rgba(afc6ff77)" }))
assert(not pcall(hl.dsp.window.fullscreen))
assert(not pcall(hl.bind, "SUPER", noop))

-- Start hooks may register shell commands but must never execute them here.
os.execute = function() error("smoke test must not execute shell commands") end
io.popen = os.execute

dofile(config_dir .. "/" .. entry)
for _, action in ipairs(events) do action() end
assert(#configs > 0 and #rules > 0, "config did not load")
for _, chord in ipairs({
    "SUPER + Return", "SUPER + E", "SUPER + W", "SUPER + Q", "SUPER + F",
    "SUPER + V", "SUPER + P", "SUPER + M", "SUPER + ALT + M",
    "SUPER + SHIFT + A", "SUPER + SHIFT + S",
    "SUPER + mouse:272", "SUPER + mouse:273",
    "SUPER + 1", "SUPER + 2", "SUPER + 3", "SUPER + 4", "SUPER + 5",
    "SUPER + 6", "SUPER + 7", "SUPER + 8", "SUPER + 9", "SUPER + 0",
}) do
    assert(binds[chord], "missing desktop keybind: " .. chord)
end
assert(commands["/usr/local/bin/anios-audio-setup --notify"], "audio startup missing")
assert(commands["fcitx5 -d"], "input method startup missing")
if mode == "minimal" then
    assert(commands.waybar and commands.mako, "Minimal startup missing")
    assert(environment.XCURSOR_THEME == "Adwaita" and environment.XCURSOR_SIZE == "24")
    assert(environment.HYPRCURSOR_THEME == "Adwaita" and environment.HYPRCURSOR_SIZE == "24")
    local border = configs[1].general.col.active_border
    assert(type(border) == "table" and #border.colors == 2 and border.angle == 45, "Gura gradient changed")
    for _, chord in ipairs({
        "SUPER + Space", "SUPER + D", "SUPER + SUPER_L", "SUPER + SHIFT + Space",
        "SUPER + SHIFT + L", "SUPER + SHIFT + E", "SUPER + SHIFT + R",
        "SUPER + Left", "SUPER + Right", "SUPER + Up", "SUPER + Down",
        "SUPER + SHIFT + Left", "SUPER + SHIFT + Right", "SUPER + SHIFT + Up", "SUPER + SHIFT + Down",
        "SUPER + SHIFT + 1", "SUPER + SHIFT + 9", "SUPER + SHIFT + 0",
    }) do
        assert(binds[chord], "missing Minimal keybind: " .. chord)
    end
else
    assert(environment.qsConfig == "imi", "Immaterial Impulse variables missing")
    assert(commands["QSG_RENDER_LOOP=threaded qs -c $qsConfig"], "Quickshell startup missing")
    assert(binds["SUPER_L"] and binds["SUPER_R"], "missing Super press/release binds")
    assert(binds["SUPER + SUPER_L"] and binds["SUPER + SUPER_R"], "missing Super release launcher binds")
    assert(binds["SUPER + Slash"], "missing cheatsheet keybind")
    assert(binds["SUPER + ALT + Page_Down"] and binds["SUPER + ALT + Page_Up"], "missing workspace move Page_Down/Page_Up binds")
    assert(not binds["SUPER + ALT + Page_down"] and not binds["SUPER + ALT + Page_up"], "legacy lowercase Page_down/Page_up bind present")
    local counts = {}
    for _, item in ipairs(bind_list) do
        counts[item.norm] = (counts[item.norm] or 0) + 1
    end
    for _, overridden in ipairs({ "super+alt+m", "super+shift+a", "ctrl+super+alt+slash" }) do
        assert(counts[overridden] == 1, "expected exactly 1 active bind for " .. overridden .. ", got " .. tostring(counts[overridden]))
    end
end

-- Render the shipped Matugen template with sample hex values. Validating only
-- colors.lua would let a wallpaper change reintroduce the broken string form.
local f = assert(io.open(template, "r"))
local rendered, replacements = f:read("*a"):gsub("{{colors%.[%w_%.]+%.hex_stripped}}", "afc6ff")
f:close()
assert(replacements > 0 and not rendered:find("{{", 1, true), "unhandled Matugen placeholder")
assert(load(rendered, "@" .. template))()
assert(type(rules[#rules].border_color) == "table", "Matugen must emit a Lua gradient table")
print("OK: " .. entry .. " (" .. mode .. ") + Matugen template")
