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

local configs, rules, binds, events, commands, environment = {}, {}, {}, {}, {}, {}
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
    bind = function(key, action)
        assert(type(key) == "string" and type(action) == "function", "invalid keybind")
        binds[key] = action
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
        exec_cmd = command, exit = dispatcher, focus = dispatcher, global = dispatcher,
        layout = dispatcher, submap = dispatcher,
        window = strict({ close = dispatcher, drag = dispatcher, float = dispatcher,
            fullscreen = dispatcher, fullscreen_state = dispatcher, move = dispatcher,
            pin = dispatcher, resize = dispatcher }),
        workspace = strict({ toggle_special = dispatcher }),
    }),
})

-- Ensure the guards really reject each previously shipped failure.
assert(not pcall(hl.config, { general = { col = { active_border = "rgba(2f6be8ff) rgba(4ea6eaff) 45deg" } } }))
assert(not pcall(hl.config, { cursor = { name = "Adwaita" } }))
assert(not pcall(hl.config, { cursor = { size = 24 } }))
assert(not pcall(hl.config, { decoration = { shadow = { render_power = 10 } } }))
assert(not pcall(hl.window_rule, { border_color = "rgba(afc6ffAA) rgba(afc6ff77)" }))

-- Start hooks may register shell commands but must never execute them here.
os.execute = function() error("smoke test must not execute shell commands") end
io.popen = os.execute

dofile(config_dir .. "/" .. entry)
for _, action in ipairs(events) do action() end
assert(#configs > 0 and #rules > 0, "config did not load")
assert(binds["SUPER + Return"] and binds["SUPER + ALT + M"], "missing desktop keybinds")
assert(commands["/usr/local/bin/anios-audio-setup --notify"], "audio startup missing")
assert(commands["fcitx5 -d"], "input method startup missing")
if mode == "minimal" then
    assert(commands.waybar and commands.mako, "Minimal startup missing")
    assert(environment.XCURSOR_THEME == "Adwaita" and environment.XCURSOR_SIZE == "24")
    assert(environment.HYPRCURSOR_THEME == "Adwaita" and environment.HYPRCURSOR_SIZE == "24")
    local border = configs[1].general.col.active_border
    assert(type(border) == "table" and #border.colors == 2 and border.angle == 45, "Gura gradient changed")
else
    assert(environment.qsConfig == "imi", "Immaterial Impulse variables missing")
    assert(commands["QSG_RENDER_LOOP=threaded qs -c $qsConfig"], "Quickshell startup missing")
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
