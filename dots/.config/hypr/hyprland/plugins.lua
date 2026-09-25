-- Plugin loading and plugin configuration.
--
-- Shipped rather than seeded: this is the project's own machinery, no part of
-- it is a user override, and it lives in the tree that an update refreshes so a
-- machine that already exists receives changes to it. It used to sit in
-- custom/general.lua, which is written once at install and never again, so
-- anything added to it only ever reached new installs.
--
-- Everything the user can change is read from files under custom/ at reload
-- time, which is the tree that is left alone, so the two concerns stay apart.

-- Custom general overrides + plugin loading.
-- The Title Bars toggle sets plugin:hyprbars:enabled via the titlebars.enabled
-- flag read below; it does NOT rewrite the load line (which stays permanently
-- active). The Lua config manager cannot
-- read or write plugin config values for plugins still on the V1 plugin
-- API (HyprlandAPI::addConfigValue, addConfigKeyword, getConfigValue) —
-- those calls are hard-gated to CONFIG_LEGACY in Hyprland 0.55
-- (src/plugins/PluginAPI.cpp:179). Plugins must be ported to
-- addConfigValueV2 before their config keys become settable from Lua.
--
-- Status of our plugins:
--   * scrolloverview — V2-ported in the MainstreamOS/hyprland-scroll-overview fork.
--   * hyprbars       — V2-ported upstream in hyprwm/hyprland-plugins.
--     Settable from Lua via hl.config({ plugin = { hyprbars = { ... } } }).

local HOME = os.getenv("HOME") or ""

-- Runtime detection that hyprbars is loaded.
--
-- Upstream hyprbars registers `hl.plugin.hyprbars.add_button` via
-- addLuaFunction() inside PLUGIN_INIT. The function only appears in the
-- hl.plugin.<name>.<fn> table after the plugin's init completes
-- successfully. This is a stronger check than reading the load directive
-- because it captures the runtime truth — `hyprctl plugin load` from
-- TitleBars.qml toggles the runtime even before the conf is edited, and a
-- failed dlopen wouldn't register the function regardless of the directive.
local function hyprbarsActive()
    return hl.plugin
        and hl.plugin.hyprbars
        and hl.plugin.hyprbars.add_button ~= nil
end

-- scrolloverview plugin. The .so lives in ~/.local/share/hyprland/plugins/ —
-- installed by sdata/subcmd-install/3.files.sh or pre-shipped via /etc/skel
-- from archiso. Active by default — the niri-style overview is wired to
-- Super+O and the bar's top-left hot corner. The MainstreamOS fork uses
-- addConfigValueV2 so its keys are settable from this Lua config and
-- switchwall.sh's wallpaper_path rewrite is honored at runtime.
-- Refuse to load a plugin stamped for a different Hyprland than the one
-- this system has installed — a version-mismatched .so segfaults the
-- compositor at dlopen and locks the user out at SDDM.
--
-- /var/lib/hyprland-plugins/hyprland-version records the Hyprland this
-- system has installed; <plugin>.builtfor records the Hyprland each .so was
-- compiled against. Both are pkgver-pkgrel from `pacman -Q hyprland`.
--
-- The system version gates the check. Absent, this is not a system whose
-- plugins we manage (a hand-rolled or upstream install) and the check passes
-- open. Present, every .so must carry a matching stamp — an unstamped .so
-- has unknown provenance, which is the same conclusion quarantine_stale_targets
-- reaches in the rebuild scripts when it moves a stampless plugin aside.
local function plugin_matches_hyprland(so)
    local ef = io.open("/var/lib/hyprland-plugins/hyprland-version", "r")
    if not ef then return true end
    local expect = ef:read("*l") or ""
    ef:close()
    if expect == "" then return true end
    local sf = io.open(so .. ".builtfor", "r")
    if not sf then return false end
    local built = sf:read("*l") or ""
    sf:close()
    return built == expect
end

local scrolloverviewSo = HOME .. "/.local/share/hyprland/plugins/scrolloverview.so"
if plugin_matches_hyprland(scrolloverviewSo) then
    hl.plugin.load(scrolloverviewSo)
end

-- hyprbars plugin. Same install path. Always loaded — never unloaded at
-- runtime (a runtime unload leaves a dangling mouse-move hook that crashes
-- the compositor). The Title Bars toggle flips plugin:hyprbars:enabled from
-- the titlebars.enabled flag read below, applied on hyprctl reload.
local hyprbarsSo = HOME .. "/.local/share/hyprland/plugins/hyprbars.so"
if plugin_matches_hyprland(hyprbarsSo) then
    hl.plugin.load(hyprbarsSo)
end

-- Plugin config — applied DEFERRED via timer (not at parse time).
--
-- Why deferred: hl.plugin.load() is async. The plugin's PLUGIN_INIT runs
-- after parsing completes (via handlePluginLoads -> updateConfigPlugins ->
-- recursive reload). On the FIRST parse, plugin keys aren't yet in
-- m_configValues, so hl.config({plugin={...}}) hits "unknown config key"
-- for every key. Hyprland's auto-second-parse usually catches up — but
-- third-party reloads (e.g. hyprctl plugin load/unload for hyprbars
-- toggling) can re-trigger the race and accumulate visible overlay errors.
--
-- Firing from a hl.timer at the end of each config.reloaded event sidesteps
-- the race: by the time the timer callback runs, handlePluginLoads has
-- finished its async dance and every plugin's keys are settled in
-- m_configValues. Re-fires on every reload so config.reloaded fires once
-- per reload chain (not the racy first pass).
-- Probe whether a config key is registered in m_configValues. Lighter than
-- calling hl.config and getting "unknown config key" runtime notifications
-- pushed to the user (addError fires Notification::overlay for runtime
-- errors). hl.get_config returns (value, nil) on hit and (nil, errStr) on
-- miss; the second return is what we test.
local function keyAvailable(name)
    local _, err = hl.get_config(name)
    return err == nil
end

-- Title Bars on/off persists in a flag file next to this config
-- ("1"/"0", absent = enabled). Read fresh on every reload so the Settings
-- toggle takes effect via `hyprctl reload` — with NO plugin unload.
local function titleBarsEnabled()
    local f = io.open(HOME .. "/.config/hypr/custom/titlebars.enabled", "r")
    if not f then return true end
    local v = f:read("*l")
    f:close()
    return v ~= "0"
end

-- One value per file under custom/, saved by the Settings pages and read on
-- every reload, so a value survives a plugin power-cycle and an update. The
-- title bar's color and opacity and the overview's layout, gap and scale all
-- live this way.
local function readCustomValue(name)
    local f = io.open(HOME .. "/.config/hypr/custom/" .. name, "r")
    if not f then return nil end
    local v = f:read("*l")
    f:close()
    if v == nil or v == "" then return nil end
    return v
end

-- Light or dark, as switchwall.sh last settled it. Nothing here can ask
-- gsettings, so the script leaves the answer beside the other values. Before
-- it has ever run the desktop is dark, which is how it starts out.
local function colorMode()
    local v = readCustomValue("colormode")
    if v and v:match("^%s*light%s*$") then return "light" end
    return "dark"
end

-- Dark mode and light mode each keep their own title bar colors: the dark set
-- under the plain names, the light set under the same names ending in Light.
-- An empty or unreadable file is that mode's stock value below. The button
-- size is one value for both modes.
local TITLE_BAR_DEFAULTS = {
    dark = {
        color = "333333",
        opacity = 0.5333,
        buttonBackground = "rgba(49454e55)",
        buttonIconColor = "rgb(ffffff)",
        buttonHighlight = "rgba(6c667599)",
    },
    -- The dark set turned over: a chip a shade off the bar, near-black icons
    -- and a hover a clear step further, the same distances in lightness as
    -- the dark set keeps from its bar.
    light = {
        color = "f3f3f3",
        opacity = 0.3,
        buttonBackground = "rgba(d8d3dd55)",
        buttonIconColor = "rgb(1d1b20)",
        buttonHighlight = "rgba(b5afbc99)",
    },
}

local function titleBarSlot(name, mode)
    if mode == "light" then return name .. "Light" end
    return name
end

-- hyprbars takes a single bar_color carrying its own alpha, so the color and
-- the opacity are composed here rather than set as two keys. Always a value:
-- the plugin has one stock bar for both modes, and a dark bar on a light
-- desktop is what leaving the key to it would give.
local function titleBarColor(mode)
    local hex = readCustomValue(titleBarSlot("titlebars.color", mode))
    if hex then
        hex = hex:gsub("^#", "")
        if not hex:match("^%x%x%x%x%x%x$") then hex = nil end
    end
    hex = hex or TITLE_BAR_DEFAULTS[mode].color
    local on = tonumber(readCustomValue(titleBarSlot("titlebars.opacity", mode)) or "")
        or TITLE_BAR_DEFAULTS[mode].opacity
    if on < 0 then on = 0 elseif on > 1 then on = 1 end
    return string.format("rgba(%s%02x)", hex, math.floor(on * 255 + 0.5))
end

-- The buttons carry their own size and colors, kept apart from the bar's so a
-- bar color pick does not drag them along. Six digits are opaque, eight carry
-- their own alpha as RRGGBBAA, which is how a see-through button is written.
-- The bar's own height, and the ceiling it puts on a button: past about three
-- fifths of the bar there is no room left around the icon. Below about two
-- fifths the icon, drawn at 0.62 of the button, is too small to read and the
-- button too small to hit, so that is the floor.
local TITLE_BAR_HEIGHT = 30
local TITLE_BAR_BUTTON_MIN = math.ceil(TITLE_BAR_HEIGHT * 0.4)
local TITLE_BAR_BUTTON_MAX = math.floor(TITLE_BAR_HEIGHT * 0.6)
-- Half the bar, which sits inside that ceiling with room left around the icon.
local TITLE_BAR_BUTTON_DEFAULT = math.floor(TITLE_BAR_HEIGHT * 0.5 + 0.5)

local function titleBarButton(mode)
    local size = tonumber(readCustomValue("titlebars.buttonSize") or "") or TITLE_BAR_BUTTON_DEFAULT
    if size < TITLE_BAR_BUTTON_MIN then size = TITLE_BAR_BUTTON_MIN
    elseif size > TITLE_BAR_BUTTON_MAX then size = TITLE_BAR_BUTTON_MAX end
    local defaults = TITLE_BAR_DEFAULTS[mode]
    local function colorOf(name)
        local hex = readCustomValue(titleBarSlot("titlebars." .. name, mode))
        if hex then
            hex = hex:gsub("^#", "")
            if hex:match("^%x%x%x%x%x%x$") then return "rgb(" .. hex .. ")" end
            if hex:match("^%x%x%x%x%x%x%x%x$") then return "rgba(" .. hex .. ")" end
        end
        return defaults[name]
    end
    return size, colorOf("buttonBackground"), colorOf("buttonIconColor"), colorOf("buttonHighlight")
end

-- Minimizing puts a window on the scratchpad, the special workspace that opens
-- over the desktop, without following it there.
local SCRATCHPAD = "special:special"

local function toScratchpad()
    return hl.dsp.window.move({ workspace = "special", follow = false })
end

-- Restoring brings a minimized window back to the workspace on screen and
-- follows it, so it reappears where the user is looking. Global because the
-- title bar reaches this config only through `hyprctl dispatch`, which sees
-- globals and not this file's locals, and the minimize button and the scroll
-- gestures have to move a window the same way.
function MainstreamTitleBarMinimize()
    local w = hl.get_active_window()
    if w and w.workspace and w.workspace.special then
        local m = hl.get_active_monitor()
        local t = m and m.active_workspace
        if t then
            return hl.dsp.window.move({ workspace = tostring(t.id), follow = true })
        end
    end
    return toScratchpad()
end

-- Scrolling on a title bar steps its window one rung along minimized, normal,
-- maximized and fullscreen: up climbs and down descends. The plugin focuses the
-- window under the pointer before running the command, so the active window is
-- the one scrolled on. A step past either end is a dispatcher that does
-- nothing, which hl.dispatch accepts without a complaint. A fullscreen window
-- has no title bar, so down from fullscreen only comes from the command run by
-- hand, and it lands one rung lower like any other step. Minimized means the
-- scratchpad alone: a window a rule or the user put on a named special
-- workspace climbs and descends like any other, down to the scratchpad, where
-- the minimize button would bring it back to the desktop instead.
local FULLSCREEN_NONE, FULLSCREEN_MAXIMIZED = 0, 1

function MainstreamTitleBarStep(direction)
    local w = hl.get_active_window()
    if not w or (direction ~= "up" and direction ~= "down") then
        return hl.dsp.no_op()
    end
    local up = direction == "up"
    if w.workspace and w.workspace.name == SCRATCHPAD then
        if up then return MainstreamTitleBarMinimize() end
        return hl.dsp.no_op()
    end
    local mode = w.fullscreen or FULLSCREEN_NONE
    if up then
        if mode == FULLSCREEN_NONE then
            return hl.dsp.window.fullscreen({ mode = "maximized", action = "set" })
        elseif mode == FULLSCREEN_MAXIMIZED then
            return hl.dsp.window.fullscreen({ mode = "fullscreen", action = "set" })
        end
        return hl.dsp.no_op()
    end
    if mode == FULLSCREEN_NONE then
        return toScratchpad()
    elseif mode == FULLSCREEN_MAXIMIZED then
        return hl.dsp.window.fullscreen({ mode = "maximized", action = "unset" })
    end
    return hl.dsp.window.fullscreen({ mode = "maximized", action = "set" })
end

-- What the title bar's buttons and gestures run. Each is a shell command, and
-- `hyprctl dispatch X` runs `return hl.dispatch(X)` in this config, so X is a
-- Lua dispatcher, single-quoted so the shell leaves its parentheses and double
-- quotes alone. A middle-click closes the way the close button does, which
-- lets an app ask about unsaved work first, and a double-click maximizes and
-- restores the way the maximize button does.
local TITLE_BAR_CLOSE = [[hyprctl dispatch 'hl.dsp.window.close()']]
local TITLE_BAR_MAXIMIZE = [[hyprctl dispatch 'hl.dsp.window.fullscreen({mode = "maximized"})']]
local TITLE_BAR_MINIMIZE = [[hyprctl dispatch 'MainstreamTitleBarMinimize()']]
local TITLE_BAR_SCROLL_UP = [[hyprctl dispatch 'MainstreamTitleBarStep("up")']]
local TITLE_BAR_SCROLL_DOWN = [[hyprctl dispatch 'MainstreamTitleBarStep("down")']]

-- The wallpaper the overview draws, saved beside the other runtime flags by
-- switchwall.sh. Read from there rather than written into this file: this file
-- is refreshed on update, and a path spliced into it would be replaced by the
-- stock one the next time it was.
local function overviewWallpaper()
    local f = io.open(HOME .. "/.config/hypr/custom/overview.wallpaper", "r")
    if f then
        local v = f:read("*l")
        f:close()
        if v and v ~= "" then return v end
    end
    return HOME .. "/.config/quickshell/ii/assets/images/default_wallpaper.webp"
end

-- The overview's own numbers, saved by Settings the same way. A file that
-- does not parse or is out of range falls back to the shipped value, and an
-- absent layout file leaves that key alone, so a machine from before these
-- files existed keeps the layout its own custom/general.lua block sets.
local function overviewNumber(name, default, min, max)
    local v = tonumber(readCustomValue(name) or "")
    if v == nil or v < min or v > max then return default end
    return v
end

local function overviewLayout()
    local v = readCustomValue("scrolloverview.layout")
    if v == "vertical" or v == "horizontal" then return v end
    return nil
end

-- Settings a monitor keeps apart from the rest, one line each in
-- custom/scrolloverview.monitors ("DP-1 layout=vertical scale=0.40"). The plugin
-- forgets them on every reload, so they are handed over again each time. Only a
-- plugin with per-monitor settings has configure(), and a bad line is skipped
-- rather than stopping the others.
local function applyOverviewMonitors()
    local api = hl.plugin and hl.plugin.scrolloverview
    if not (api and api.configure) then return end
    local f = io.open(HOME .. "/.config/hypr/custom/scrolloverview.monitors", "r")
    if not f then return end
    for line in f:lines() do
        local output, rest = line:match("^%s*([%w%._%-]+)%s+(.-)%s*$")
        if output then
            local cfg = { output = output }
            local any = false
            for key, value in rest:gmatch("([%a_]+)=(%S+)") do
                local n = tonumber(value)
                if key == "layout" and (value == "vertical" or value == "horizontal") then
                    cfg.layout = value; any = true
                elseif key == "workspace_gap" and n and n >= 0 and n <= 500 then
                    cfg.workspace_gap = math.floor(n); any = true
                elseif key == "scale" and n and n >= 0.1 and n <= 0.9 then
                    cfg.scale = n; any = true
                end
            end
            if any then pcall(api.configure, cfg) end
        end
    end
    f:close()
end

local function applyPluginConfig()
    -- scrolloverview block — probe one key first. During a hyprbars toggle
    -- the file watcher + handlePluginLoads chain transiently re-parses
    -- before scrolloverview's V2 keys are addressable in m_configValues
    -- (specific cause is opaque to us — possibly the reset() loop at
    -- ConfigManager.cpp:454-456 runs before plugin re-registration in the
    -- recursive reload). Skip-on-miss avoids accumulating runtime errors.
    if keyAvailable("plugin:scrolloverview:scale") then
        local overviewCfg = {
            gesture_distance = 300,
            scale = overviewNumber("scrolloverview.scale", 0.50, 0.05, 1),
            workspace_gap = overviewNumber("scrolloverview.workspace_gap", 100, 0, 500),
            wallpaper = 2,           -- 0: global only, 1: per-workspace only, 2: both
            wallpaper_path = overviewWallpaper(),
            blur = true,
            shadow = {
                enabled = true,
                range = 50,
                render_power = 3,
                -- color is registered as CIntValue in the V1-port plugin
                -- (defaults to -1 = inherit decoration:shadow:color).
                -- Set via decimal-encoded ARGB if you want to override:
                --   color = 0x1a1a1aee,
            },
        }
        local layout = overviewLayout()
        if layout then overviewCfg.layout = layout end
        hl.config({
            plugin = {
                scrolloverview = overviewCfg,
            },
        })
        applyOverviewMonitors()
    end

    -- hyprbars config + buttons — also probed before apply.
    if hyprbarsActive() and keyAvailable("plugin:hyprbars:bar_height") then
        local tbOn = titleBarsEnabled()
        local mode = colorMode()
        -- Built first so a key that only a newer build knows can be added
        -- below, and left out entirely for an older one.
        local hyprbarsCfg = {
            enabled = tbOn,
            bar_text_font = "Google Sans Flex Medium, Rubik, Geist, AR One Sans, Reddit Sans, Inter, Roboto, Ubuntu, Noto Sans, sans-serif",
            bar_title_enabled = false,
            bar_height = tbOn and TITLE_BAR_HEIGHT or 0,
            bar_padding = 10,
            bar_button_padding = 5,
            bar_precedence_over_border = true,
            bar_part_of_window = true,
            bar_color = titleBarColor(mode),
        }
        -- Only a plugin built with buttons_on_hover knows the key, so an older
        -- build is not handed a setting it would report as unknown.
        if keyAvailable("plugin:hyprbars:buttons_on_hover") then
            hyprbarsCfg.buttons_on_hover = readCustomValue("titlebars.buttonsOnHover") == "1"
        end
        if keyAvailable("plugin:hyprbars:on_double_click") then
            hyprbarsCfg.on_double_click = TITLE_BAR_MAXIMIZE
        end
        if keyAvailable("plugin:hyprbars:on_middle_click") then
            hyprbarsCfg.on_middle_click = TITLE_BAR_CLOSE
        end
        -- Double-click and middle-click are always on. The scroll gestures
        -- have a switch in Settings, saved beside the other title bar values
        -- ("1"/"0", absent = on), and an empty command is the plugin's own
        -- "do nothing".
        if keyAvailable("plugin:hyprbars:on_scroll_up") and keyAvailable("plugin:hyprbars:on_scroll_down") then
            local scroll = readCustomValue("titlebars.scrollActions") ~= "0"
            hyprbarsCfg.on_scroll_up = scroll and TITLE_BAR_SCROLL_UP or ""
            hyprbarsCfg.on_scroll_down = scroll and TITLE_BAR_SCROLL_DOWN or ""
        end
        hl.config({
            plugin = {
                hyprbars = hyprbarsCfg,
            },
        })

        -- hyprbars-button is not a config key in Lua mode — addConfigKeyword
        -- is Legacy-only. Upstream hyprbars registers hl.plugin.hyprbars.add_button
        -- via addLuaFunction(). Each call appends one button; the closure
        -- inside the plugin's globals tracks them.
        --
        -- Button actions are shell commands the plugin runs through the
        -- `exec` dispatcher, written the way the TITLE_BAR_* commands above
        -- describe. The dispatchers come from
        -- src/config/lua/bindings/LuaBindingsDispatchers.cpp's `hl.dsp` tree.
        --
        -- add_button appends and the plugin cannot be asked what it already
        -- holds, so running this twice in one Lua state adds a second set of
        -- the same buttons. The mark goes on the plugin's own table, which is
        -- what makes its life match the buttons': a config reload empties the
        -- plugin's list and then starts a new Lua state, which takes the mark
        -- with it, and loading or unloading the plugin ends in a reload too.
        -- So the mark only stops a second set while one Lua state is running.
        --
        -- A table that will not take the mark reads as unmarked every time, so
        -- the buttons are added again rather than skipped. Two of each is
        -- untidy; none at all leaves a window with no way to close it.
        local buttonsAdded = false
        pcall(function() buttonsAdded = hl.plugin.hyprbars.__ms_buttons == true end)
        -- The buttons have a switch of their own in Settings, saved beside
        -- the other title bar values ("1"/"0", absent = on). The plugin
        -- empties its list before every reload, so adding none here is what
        -- takes them off the bars. Double-click, middle-click and the scroll
        -- steps set above belong to the bar, not to a button, so they stay.
        local buttonsOn = readCustomValue("titlebars.buttons") ~= "0"
        if hyprbarsActive() and tbOn and buttonsOn and not buttonsAdded then
            pcall(function() hl.plugin.hyprbars.__ms_buttons = true end)
            local btnSize, btnBg, btnFg, btnHover = titleBarButton(mode)
            -- Only a plugin built with buttons_pop_in draws its own hover
            -- color, and an older build is not handed a field it does not
            -- know. A nil leaves the field out of each table below.
            if not keyAvailable("plugin:hyprbars:buttons_pop_in") then btnHover = nil end
            hl.plugin.hyprbars.add_button({
                bg_color = btnBg,
                fg_color = btnFg,
                hover_color = btnHover,
                size     = btnSize,
                icon     = "󰖭",
                action   = TITLE_BAR_CLOSE,
            })
            hl.plugin.hyprbars.add_button({
                bg_color = btnBg,
                fg_color = btnFg,
                hover_color = btnHover,
                size     = btnSize,
                icon     = "󰖯",
                action   = TITLE_BAR_MAXIMIZE,
            })
            hl.plugin.hyprbars.add_button({
                bg_color = btnBg,
                fg_color = btnFg,
                hover_color = btnHover,
                size     = btnSize,
                icon     = "󰖰",
                action   = TITLE_BAR_MINIMIZE,
            })
        end
    end
end

-- Apply synchronously inside the reload chain — by the time config.reloaded
-- fires, the plugin's PLUGIN_INIT has completed addConfigValueV2 +
-- addLuaFunction, so the keys are in m_configValues and add_button is
-- callable. Applying synchronously (no timer) means the V2 IValues are
-- updated before PLUGIN_INIT returns from the runtime `hyprctl plugin load`
-- call, before the renderer's next frame. Without this, hyprbars's
-- onNewWindow loop in PLUGIN_INIT creates bars at default styling and the
-- first frame shows the un-styled state until our async timer caught up
-- (visible as a flash of plain-white-text bars with no buttons).
--
-- One handler only — initial startup already fires config.reloaded inside
-- the post-handlePluginLoads recursive reload chain, so subscribing to
-- hyprland.start as well would cause add_button to push duplicates
-- (hyprbars only clears the button list on preReload between reloads).
hl.on("config.reloaded", applyPluginConfig)

-- Hyprland 0.55 scrolloverview load-race workaround lives in
-- custom/execs.lua, which runs scripts/scrolloverview-power-cycle.sh
-- on hyprland.start. The bash script polls hyprctl layers until a
-- Quickshell namespace appears, then unconditionally unloads + reloads
-- the plugin so its input hook re-inserts after Quickshell's surface.
--
-- A previous Lua-only version of this gate (hl.on("layer.opened") +
-- marker file) had a fast-path bug: it skipped the cycle when
-- hl.plugin.scrolloverview.overview was already registered, but the
-- wedge can be present even with the plugin fully loaded (the race is
-- between Quickshell's surface and the plugin's input hook, not the
-- PLUGIN_INIT completion). Unconditional cycling at startup is the
-- safer shape — the cost is a ~300ms plugin-absent window, the
-- benefit is a guaranteed wedge-clear regardless of timing.
