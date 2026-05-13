-- Custom general overrides + plugin loading.
-- Settings → Interface panel rewrites the hyprbars plugin-load line in here
-- via Python regex; keep the shape stable. The Lua config manager cannot
-- read or write plugin config values for plugins still on the V1 plugin
-- API (HyprlandAPI::addConfigValue, addConfigKeyword, getConfigValue) —
-- those calls are hard-gated to CONFIG_LEGACY in Hyprland 0.55
-- (src/plugins/PluginAPI.cpp:179). Plugins must be ported to
-- addConfigValueV2 before their config keys become settable from Lua.
--
-- Status of our plugins:
--   * scrolloverview — V1, NOT yet ported. Runs on compiled defaults.
--   * hyprbars       — V2-ported in MainstreamOS/hyprland-plugins fork.
--     Settable from Lua via hl.config({ plugin = { hyprbars = { ... } } })
--     once the load directive is uncommented.

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
local scrolloverviewSo = HOME .. "/.local/share/hyprland/plugins/scrolloverview.so"
hl.plugin.load(scrolloverviewSo)

-- hyprbars plugin. Same install path. Commented out by default — the
-- Title Bars toggle in Settings → Interface → Decorations toggles the
-- `-- ` prefix on this exact line via TitleBars.qml's self-healing path.
hl.plugin.load(HOME .. "/.local/share/hyprland/plugins/hyprbars.so")

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
                    -- switchwall.sh rewrites this line on every wallpaper change.
                    wallpaper_path = "/home/itsjustdroid/.config/mainstream/themes/pink-sunrise/wallpaper.png",
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
        hl.config({
            plugin = {
                hyprbars = {
                    bar_text_font = "Google Sans Flex Medium, Rubik, Geist, AR One Sans, Reddit Sans, Inter, Roboto, Ubuntu, Noto Sans, sans-serif",
                    bar_title_enabled = false,
                    bar_height = 30,
                    bar_padding = 10,
                    bar_button_padding = 5,
                    bar_precedence_over_border = true,
                    bar_part_of_window = true,
                },
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
        if hl.plugin and hl.plugin.hyprbars and hl.plugin.hyprbars.add_button then
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

-- Hyprland 0.55 scrolloverview load-race workaround.
-- Plugin loading is async (hl.plugin.load just queues; the actual load runs
-- via PluginSystem::updateConfigPlugins().then(...)). PLUGIN_INIT can land
-- mid-layer-shell-setup and wedge Quickshell's dock pointer dispatch.
-- Unloading + reloading via hyprctl AFTER quickshell registers its layers
-- clears the wedge for the rest of the session.
--
-- Idempotency: the previous implementation used a Lua-local `cycled` flag
-- that reset on every config reload. Every time Quickshell reloads
-- (Ctrl+Super+R, or layer rebuild from a monitor event), its layer
-- surfaces re-register and layer.opened fires again — so the cycle ran
-- repeatedly, and a race in the unload+load window could leave the plugin
-- stuck unloaded. The marker file below sits in Hyprland's own runtime
-- dir (auto-cleaned when Hyprland exits) so the cycle runs at most ONCE
-- per Hyprland session, no matter how many times Quickshell reloads.
--
-- Plus a fast-path: if the plugin's Lua function is already registered
-- by the time we observe the first qualifying layer.opened, PLUGIN_INIT
-- ran to completion without the wedge → no cycle needed at all. Skip
-- the disruptive unload+load entirely.
local function _cycleMarkerPath()
    local his = os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or "default"
    local rt = os.getenv("XDG_RUNTIME_DIR") or "/tmp"
    return rt .. "/hypr/" .. his .. "/.scrolloverview-cycled"
end

local function _markerExists(path)
    local f = io.open(path, "r")
    if not f then return false end
    f:close()
    return true
end

local function _writeMarker(path)
    local f = io.open(path, "w")
    if f then f:close() end
end

hl.on("layer.opened", function(ls)
    if ls == nil then return end
    local ns = ls.namespace or ""
    if not (ns:match("^quickshell") or ns:match("^qs[-_]") or ns:match("^ii[-_]")) then
        return
    end

    local marker = _cycleMarkerPath()
    if _markerExists(marker) then return end

    -- Fast path: plugin's Lua function is already registered → init ran
    -- cleanly. Mark cycled so subsequent layer events don't re-check.
    if hl.plugin and hl.plugin.scrolloverview and hl.plugin.scrolloverview.overview then
        _writeMarker(marker)
        return
    end

    -- Plugin is wedged or PLUGIN_INIT hasn't completed — run the cycle.
    _writeMarker(marker)

    -- Brief settle so a second layer registering in the same tick still
    -- lands before we yank the plugin.
    hl.timer(function()
        hl.exec_cmd('hyprctl plugin unload "' .. scrolloverviewSo .. '"')
        hl.timer(function()
            hl.exec_cmd('hyprctl plugin load "' .. scrolloverviewSo .. '"')
        end, { timeout = 100, type = "oneshot" })
    end, { timeout = 200, type = "oneshot" })
end)
