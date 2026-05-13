-- Custom general overrides + plugin loading.
-- Settings → Interface panel rewrites scrolloverview keys and the hyprbars
-- plugin-load line in here via Python regex; keep the shape stable.

local HOME = os.getenv("HOME") or ""

-- scrolloverview plugin. The .so lives in ~/.local/share/hyprland/plugins/ —
-- installed by sdata/subcmd-install/3.files.sh or pre-shipped via /etc/skel
-- from archiso. Active by default — the niri-style overview is wired to
-- Super+O and the bar's top-left hot corner.
local scrolloverviewSo = HOME .. "/.local/share/hyprland/plugins/scrolloverview.so"
hl.plugin.load(scrolloverviewSo)

-- hyprbars plugin. Same install path. Commented out by default — the
-- Title Bars toggle in Settings → Interface → Decorations toggles the
-- `-- ` prefix on this exact line via TitleBars.qml's self-healing path.
-- hl.plugin.load("$HOME/.local/share/hyprland/plugins/hyprbars.so")

-- Plugin config blocks. These keys are registered by the plugins themselves,
-- so on first parse they may warn as unknown; Hyprland reloads automatically
-- once plugins finish loading, and the second parse applies them cleanly.
hl.config({
    plugin = {
        hyprbars = {
            bar_text_font = "Google Sans Flex Medium, Rubik, Geist, AR One Sans, Reddit Sans, Inter, Roboto, Ubuntu, Noto Sans, sans-serif",
            ["col.text"] = "rgba(00000000)",
            bar_height = 30,
            bar_padding = 10,
            bar_button_padding = 5,
            bar_precedence_over_border = true,
            bar_part_of_window = true,

            -- hyprbars-button accepts list-of-strings, comma-separated parts
            ["hyprbars-button"] = "rgba(49454e55), 13, 󰖭, hyprctl dispatch killactive, rgb(ffffff)",
        },
        scrolloverview = {
            gesture_distance = 300,  -- max for the gesture
            scale = 0.5,             -- preferred overview scale
            workspace_gap = 100,
            wallpaper = 2,           -- 0: global only, 1: per-workspace only, 2: both
            -- Path to the wallpaper image rendered as the overview backdrop.
            -- Defaults to the bundled end-4 default wallpaper. switchwall.sh
            -- rewrites this line on every wallpaper change.
            wallpaper_path = HOME .. "/.config/quickshell/ii/assets/images/default_wallpaper.png",
            blur = true,             -- blur only the main overview wallpaper

            shadow = {
                enabled = true,
                range = 50,
                render_power = 3,
                color = "rgba(1a1a1aee)",
            },
        },
    },
})

-- Hyprland 0.55 scrolloverview load-race workaround.
-- Plugin loading is async (hl.plugin.load just queues; the actual load runs
-- via PluginSystem::updateConfigPlugins().then(...)). PLUGIN_INIT can land
-- mid-layer-shell-setup and wedge Quickshell's dock pointer dispatch.
-- Unloading + reloading via hyprctl AFTER quickshell registers its layers
-- clears the wedge for the rest of the session.
--
-- This replaces the old custom/scripts/scrolloverview-power-cycle.sh polling
-- loop — same cycle (unload, load), driven by layer.opened instead of bash
-- polling. The script is kept for emergency manual cycling.
local cycled = false
hl.on("layer.opened", function(ls)
    if cycled or ls == nil then return end
    local ns = ls.namespace or ""
    if not (ns:match("^quickshell") or ns:match("^qs[-_]") or ns:match("^ii[-_]")) then
        return
    end
    cycled = true
    -- Brief settle so a second layer registering in the same tick still
    -- lands before we yank the plugin.
    hl.timer(function()
        hl.exec_cmd('hyprctl plugin unload "' .. scrolloverviewSo .. '"')
        hl.timer(function()
            hl.exec_cmd('hyprctl plugin load "' .. scrolloverviewSo .. '"')
        end, { timeout = 100, type = "oneshot" })
    end, { timeout = 200, type = "oneshot" })
end)
