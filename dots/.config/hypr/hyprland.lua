-- Entry point. Sources files in `hyprland` and `custom` folders.
-- Put your own stuff in `custom/` so updates don't clobber it.

-- Helper: best-effort require (matches hyprlang's `# hyprlang noerror true`).
-- Lets custom/* be absent or have a typo without nuking the whole config.
local function tryRequire(mod)
    local ok, err = pcall(require, mod)
    if not ok then
        -- Only complain if the failure was something other than file-not-found
        if not err:match("module .- not found") then
            print("[hyprland.lua] " .. mod .. " errored: " .. err)
        end
    end
end

-- Default-load toggles. Set any of these to true in custom/variables.lua
-- BEFORE this entry runs (it doesn't, see below) — or just edit this file.
-- Mirrors the hyprlang `$dontLoadDefault*` variables.
dontLoadDefaultExecs = false
dontLoadDefaultGeneral = false
dontLoadDefaultRules = false
dontLoadDefaultColors = false
dontLoadDefaultKeybinds = false

-- Variables FIRST so terminal/browser/etc. are in scope when keybinds load.
require("hyprland.variables")
tryRequire("custom.variables")

-- Environment
require("hyprland.env")
tryRequire("custom.env")

-- Defaults (gated by dontLoadDefault*; flag must be set in custom/variables.lua to skip)
if not dontLoadDefaultExecs    then require("hyprland.execs") end
if not dontLoadDefaultGeneral  then require("hyprland.general") end
if not dontLoadDefaultRules    then require("hyprland.rules") end
if not dontLoadDefaultColors   then require("hyprland.colors") end
if not dontLoadDefaultKeybinds then require("hyprland.keybinds") end

-- Custom overrides (sourced AFTER defaults so they win)
tryRequire("custom.execs")
tryRequire("custom.general")
tryRequire("custom.rules")
tryRequire("custom.keybinds")

-- Optional sub-files written by Quickshell Settings (LayoutsConfig, DisplayConfig).
-- workspaces.lua sits commented out by default — uncommented by LayoutsConfig
-- when the user picks "Per Workspace" in Settings → Layouts; recommented when
-- they switch back to a global layout. Without the `-- ` prefix shipped here,
-- the perWsCheckProc grep in LayoutsConfig would always match on a fresh
-- install and the panel would open with "Per Workspace" highlighted instead
-- of "Dwindle".
-- tryRequire("workspaces")
tryRequire("monitors")

-- Shell overrides (Quickshell-managed runtime knobs: GameMode, AntiFlashbang, etc.)
tryRequire("hyprland.shellOverrides.main")
