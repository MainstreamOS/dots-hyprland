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

-- How the bar is painted, saved beside the on/off flag by the same Settings
-- page and read on the same reload.
local function readTitleBarFile(name)
    local f = io.open(HOME .. "/.config/hypr/custom/" .. name, "r")
    if not f then return nil end
    local v = f:read("*l")
    f:close()
    if v == nil or v == "" then return nil end
    return v
end

-- hyprbars takes a single bar_color carrying its own alpha, so the colour and
-- the opacity are composed here rather than set as two keys.
--
-- Returns nil for anything it cannot read as a colour, and the caller then
-- leaves the key alone: a machine that has never set one, or a theme written
-- before this existed, keeps whatever the plugin chooses for itself. Better a
-- bar that looks as it always did than every window wearing a colour nobody
-- asked for.
local function titleBarColor()
    local hex = readTitleBarFile("titlebars.color")
    if not hex then return nil end
    hex = hex:gsub("^#", "")
    if not hex:match("^%x%x%x%x%x%x$") then return nil end
    local o = tonumber(readTitleBarFile("titlebars.opacity") or "1") or 1
    if o < 0 then o = 0 elseif o > 1 then o = 1 end
    return string.format("rgba(%s%02x)", hex, math.floor(o * 255 + 0.5))
end

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

local function applyPluginConfig()
    -- scrolloverview block — probe one key first. During a hyprbars toggle
    -- the file watcher + handlePluginLoads chain transiently re-parses
    -- before scrolloverview's V2 keys are addressable in m_configValues
    -- (specific cause is opaque to us — possibly the reset() loop at
    -- ConfigManager.cpp:454-456 runs before plugin re-registration in the
    -- recursive reload). Skip-on-miss avoids accumulating runtime errors.
    if keyAvailable("plugin:scrolloverview:scale") then
        hl.config({
            plugin = {
                scrolloverview = {
                    gesture_distance = 300,
                    scale = 0.50,
                    workspace_gap = 100,
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
                },
            },
        })
    end

    -- hyprbars config + buttons — also probed before apply.
    if hyprbarsActive() and keyAvailable("plugin:hyprbars:bar_height") then
        local tbOn = titleBarsEnabled()
        -- Built first so the colour can be left out entirely. Setting the key
        -- to nil would not do that: assigning nil to a table field is how you
        -- remove it, and the field was never there to remove.
        local hyprbarsCfg = {
            enabled = tbOn,
            bar_text_font = "Google Sans Flex Medium, Rubik, Geist, AR One Sans, Reddit Sans, Inter, Roboto, Ubuntu, Noto Sans, sans-serif",
            bar_title_enabled = false,
            bar_height = tbOn and 30 or 0,
            bar_padding = 10,
            bar_button_padding = 5,
            bar_precedence_over_border = true,
            bar_part_of_window = true,
        }
        local barColor = titleBarColor()
        if barColor then
            hyprbarsCfg.bar_color = barColor
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
        -- Button actions are SHELL commands run via the legacy `exec`
        -- dispatcher (barDeco.cpp:277). In Lua mode `hyprctl dispatch X`
        -- wraps X as `return hl.dispatch(X)` — so X must be a valid Lua
        -- dispatcher callable, not a hyprlang token like "killactive".
        -- See HyprCtl.cpp:1108. The dispatchers come from
        -- src/config/lua/bindings/LuaBindingsDispatchers.cpp's `hl.dsp` tree.
        --
        -- movetoworkspacesilent has no direct equivalent in hl.dsp; only
        -- two buttons until upstream adds it (or a Lua-side wrapper).
        if hyprbarsActive() and tbOn then
            -- Action strings are shell commands run via the legacy `exec`
            -- dispatcher (barDeco.cpp:277). Bare `()` in shell triggers a
            -- subshell, so the Lua expression after `hyprctl dispatch` must
            -- be single-quoted to survive shell parsing intact.
            hl.plugin.hyprbars.add_button({
                bg_color = "rgba(49454e55)",
                fg_color = "rgb(ffffff)",
                size     = 13,
                icon     = "󰖭",
                action   = "hyprctl dispatch 'hl.dsp.window.close()'",
            })
            hl.plugin.hyprbars.add_button({
                bg_color = "rgba(49454e55)",
                fg_color = "rgb(ffffff)",
                size     = 13,
                icon     = "󰖯",
                action   = [[hyprctl dispatch 'hl.dsp.window.fullscreen({mode = "maximized"})']],
            })
            -- Toggle between special and the currently focused workspace.
            --
            -- IIFE inspects the active window's workspace via the Lua API:
            --   * On a special workspace (.workspace.special == true) →
            --     pull back to the active monitor's currently-visible
            --     workspace WITH focus follow, so the user sees the window
            --     reappear where they're looking.
            --   * On a regular workspace → send to special silently
            --     (follow=false, same effect as legacy
            --     `movetoworkspacesilent special`).
            -- Returns an hl.dsp.window.move dispatcher userdata so the
            -- outer hl.dispatch(...) wrap is satisfied.
            hl.plugin.hyprbars.add_button({
                bg_color = "rgba(49454e55)",
                fg_color = "rgb(ffffff)",
                size     = 13,
                icon     = "󰖰",
                action   = [[hyprctl dispatch '(function() local w = hl.get_active_window(); if w and w.workspace and w.workspace.special then local m = hl.get_active_monitor(); local t = m and m.active_workspace; if t then return hl.dsp.window.move({workspace = tostring(t.id), follow = true}) end end; return hl.dsp.window.move({workspace = "special", follow = false}) end)()']],
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
