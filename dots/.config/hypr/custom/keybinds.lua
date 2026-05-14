-- ╭────────────────────────────────────────────────────────────────────╮
-- │  Fork keybinds                                                      │
-- │  Loaded AFTER hyprland/keybinds.lua (upstream baseline), so any     │
-- │  hl.unbind / hl.bind in here overrides upstream's defaults.         │
-- │                                                                     │
-- │  Keep hyprland/keybinds.lua matching upstream verbatim so future    │
-- │  pulls merge cleanly. ALL fork-specific keys live in this file.     │
-- │                                                                     │
-- │  Description format: "Category: Action".                            │
-- │  The cheatsheet groups by the prefix before the colon, in the      │
-- │  order categories first appear here. Section order below matches    │
-- │  the cheatsheet picture.                                            │
-- ╰────────────────────────────────────────────────────────────────────╯

require("hyprland.variables")
require("custom.variables")

local qsScripts   = "$HOME/.config/quickshell/$qsConfig/scripts"
local hyprScripts = "$HOME/.config/hypr/hyprland/scripts"
local qsIpcCall   = "qs -c $qsConfig ipc call"
local qsIsAlive   = qsIpcCall .. " TEST_ALIVE"

-- ── Drop upstream binds we re-map ─────────────────────────────────────
-- Each key here does something different in our layout. unbind first so
-- the original action doesn't fire alongside ours.
hl.unbind("SUPER + Tab")              -- upstream: overview         → cheatsheet
hl.unbind("SUPER + K")                -- upstream: OSK              → Monocle prev
hl.unbind("SUPER + G")                -- upstream: overlay          → Gamescope toggle
hl.unbind("SUPER + J")                -- upstream: bar              → Monocle next
hl.unbind("SUPER + M")                -- upstream: media controls   → Master focus
hl.unbind("SUPER + O")                -- upstream: sidebarLeft      → Scrolling overview
hl.unbind("SUPER + Slash")            -- upstream: cheatsheet       → Master remove
hl.unbind("CTRL + SUPER + T")         -- upstream: wallpaper        → SUPER+W
hl.unbind("CTRL + SUPER + ALT + T")   -- upstream: random wallpaper → SUPER+ALT+W
hl.unbind("Print")                    -- replaced: file + clipboard pipeline
hl.unbind("CTRL + Print")             -- replaced
-- Upstream's App: category — we rebuild it as "Apps:" below to match
-- the cheatsheet section header, so drop their versions first.
hl.unbind("SUPER + Return")           -- upstream: App: Terminal
hl.unbind("SUPER + T")                -- upstream: App: Terminal alt
hl.unbind("CTRL + ALT + T")           -- upstream: App: Terminal alt
hl.unbind("SUPER + E")                -- upstream: App: File manager
hl.unbind("SUPER + W")                -- upstream: App: Browser (we use SUPER+B)
hl.unbind("SUPER + C")                -- upstream: App: Code editor
hl.unbind("CTRL + SUPER + SHIFT + ALT + W") -- upstream: App: Office software
hl.unbind("SUPER + X")                -- upstream: App: Text editor
hl.unbind("CTRL + SUPER + V")         -- upstream: App: Volume mixer
hl.unbind("SUPER + I")                -- upstream: App: Settings app
hl.unbind("CTRL + SHIFT + Escape")    -- upstream: App: Task manager
-- Upstream tags Lock / Suspend / Shutdown as "Misc:" — re-label as
-- "Session:" so they show up in the section the cheatsheet expects.
hl.unbind("SUPER + L")                              -- upstream: Misc: Lock
hl.unbind("SUPER + SHIFT + L")                      -- upstream: Misc: Suspend system
hl.unbind("CTRL + SHIFT + ALT + SUPER + Delete")    -- upstream: Misc: Shutdown
-- Upstream's "Media" section labels everything "Misc:" rather than
-- "Media:". Drop those so our Media: re-binds below own the cheatsheet
-- entry. The action is identical — only the description differs.
hl.unbind("SUPER + SHIFT + N")                      -- upstream: Misc: Next track
hl.unbind("SUPER + SHIFT + B")                      -- upstream: Misc: Previous track
hl.unbind("SUPER + SHIFT + P")                      -- upstream: Misc: Play/pause media
hl.unbind("XF86AudioNext")
hl.unbind("XF86AudioPrev")
hl.unbind("XF86AudioPlay")
hl.unbind("XF86AudioPause")
hl.unbind("SUPER + SHIFT + ALT + mouse:275")
hl.unbind("SUPER + SHIFT + ALT + mouse:276")
hl.unbind("SUPER + SHIFT + M")                      -- upstream: Misc: Toggle mute
hl.unbind("SUPER + ALT + M")                        -- upstream: Misc: Toggle mic
hl.unbind("XF86AudioMute")
hl.unbind("ALT + XF86AudioMute")
hl.unbind("XF86AudioMicMute")
-- Upstream tags Zoom as Misc: too — we want it under Screen:.
hl.unbind("SUPER + Minus")                          -- upstream: Misc: Zoom out
hl.unbind("SUPER + Equal")                          -- upstream: Misc: Zoom in
hl.unbind("SUPER + code:82")
hl.unbind("SUPER + code:86")

-- ── Shell ─────────────────────────────────────────────────────────────
-- Fork overhaul: overview→f10, cheatsheet→Tab, OSK→f11, overlay→f12,
-- bar→H, wallpaper→W. Frees J/K/M/Slash/Space for the layout dispatchers
-- in the Master/Scrolling/Monocle sections below.
hl.bind("SUPER + f10",   hl.dsp.global("quickshell:overviewWorkspacesToggle"), { description = "Shell: Toggle overview" })
hl.bind("SUPER + Tab",   hl.dsp.global("quickshell:cheatsheetToggle"),         { description = "Shell: Toggle cheatsheet" })
hl.bind("SUPER + f11",   hl.dsp.global("quickshell:oskToggle"),                { description = "Shell: Toggle on-screen keyboard" })
hl.bind("SUPER + f12",   hl.dsp.global("quickshell:overlayToggle"),            { description = "Shell: Toggle overlay" })
hl.bind("SUPER + H",     hl.dsp.global("quickshell:barToggle"),                { description = "Shell: Toggle bar" })
hl.bind("SUPER + W",     hl.dsp.global("quickshell:wallpaperSelectorToggle"),  { description = "Shell: Toggle wallpaper selector" })
hl.bind("SUPER + ALT + W", hl.dsp.global("quickshell:wallpaperSelectorRandom"),{ description = "Shell: Select random wallpaper" })
hl.bind("SUPER + W",     hl.dsp.exec_cmd(qsIsAlive .. " || " .. qsScripts .. "/colors/switchwall.sh"))
hl.bind("SUPER + SHIFT + M", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_SINK@ toggle"),
    { locked = true, description = "Shell: Toggle mute" })
hl.bind("SUPER + ALT + M",   hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_SOURCE@ toggle"),
    { locked = true, description = "Shell: Toggle mic" })
hl.bind("XF86AudioMute",       hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_SINK@ toggle"),   { locked = true })
hl.bind("ALT + XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_SOURCE@ toggle"), { locked = true })
hl.bind("XF86AudioMicMute",    hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_SOURCE@ toggle"), { locked = true })
-- (Session: Lock/Sleep/Shutdown live in their own section below.)

-- ── Media ─────────────────────────────────────────────────────────────
local mediaNextCommand = "playerctl next || playerctl position `bc <<< \"100 * $(playerctl metadata mpris:length) / 1000000 / 100\"`"
hl.bind("SUPER + SHIFT + N", hl.dsp.exec_cmd(mediaNextCommand),
    { locked = true, description = "Media: Next track" })
hl.bind("SUPER + SHIFT + B", hl.dsp.exec_cmd("playerctl previous"),
    { locked = true, description = "Media: Previous track" })
hl.bind("SUPER + SHIFT + P", hl.dsp.exec_cmd("playerctl play-pause"),
    { locked = true, description = "Media: Play/pause media" })
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd(mediaNextCommand),       { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("SUPER + SHIFT + ALT + mouse:275", hl.dsp.exec_cmd("playerctl previous"))
hl.bind("SUPER + SHIFT + ALT + mouse:276", hl.dsp.exec_cmd(mediaNextCommand))

-- ── Workspace ─────────────────────────────────────────────────────────
-- Numeric workspace switching by keyboard number row + keypad.
for i = 1, 10 do
    local numberkey = { 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }
    hl.bind("SUPER + code:" .. numberkey[i], hl.dsp.focus({ workspace = i }))
end
for i = 1, 10 do
    local numpadkey = { 87, 88, 89, 83, 84, 85, 79, 80, 81, 90 }
    hl.bind("SUPER + code:" .. numpadkey[i], hl.dsp.focus({ workspace = i }))
end
-- Special workspace (scratchpad)
hl.bind("SUPER + S", hl.dsp.workspace.toggle_special("special"),
    { description = "Workspace: Toggle scratchpad" })
hl.bind("SUPER + mouse:275", hl.dsp.workspace.toggle_special("special"))
-- Cycle workspaces / monitors with CTRL+SUPER (+ALT for monitor scope)
for i = 1, 4 do
    local key       = { "CTRL + SUPER + ", "CTRL + SUPER + ALT + " }
    local keycombos = { key[1] .. "Right", key[1] .. "Left", key[2] .. "Right", key[2] .. "Left" }
    local prefix    = { "r+", "r-", "m+", "m-" }
    hl.bind(keycombos[i], hl.dsp.focus({ workspace = prefix[i] .. "1" }))
end
for i = 1, 4 do
    local key       = { "SUPER + Page_Down", "SUPER + Page_Up" }
    local keycombos = { key[1], key[2], "CTRL + " .. key[1], "CTRL + " .. key[2] }
    local prefix    = { "r+", "r-", "r+", "r-" }
    hl.bind(keycombos[i], hl.dsp.focus({ workspace = prefix[i] .. "1" }))
end
for i = 1, 4 do
    local key       = { "SUPER + mouse_up", "SUPER + mouse_down" }
    local keycombos = { key[1], key[2], "CTRL + " .. key[1], "CTRL + " .. key[2] }
    local prefix    = { "+", "-", "r+", "r-" }
    hl.bind(keycombos[i], hl.dsp.focus({ workspace = prefix[i] .. "1" }))
end
for i = 1, 4 do
    local key    = { "BracketLeft", "BracketRight", "Up", "Down" }
    local prefix = { "-1", "+1", "r-5", "r+5" }
    hl.bind("CTRL + SUPER + " .. key[i], hl.dsp.focus({ workspace = prefix[i] }))
end

-- ── Apps ──────────────────────────────────────────────────────────────
-- Fork overhaul: W→wallpaper selector (above), B→browser (here).
hl.bind("SUPER + Return", hl.dsp.exec_cmd(terminal),       { description = "Apps: Terminal" })
hl.bind("SUPER + T",      hl.dsp.exec_cmd(terminal))
hl.bind("CTRL + ALT + T", hl.dsp.exec_cmd(terminal))
hl.bind("SUPER + E",      hl.dsp.exec_cmd(fileManager),    { description = "Apps: File manager" })
hl.bind("SUPER + B",      hl.dsp.exec_cmd(browser),        { description = "Apps: Browser" })
hl.bind("SUPER + C",      hl.dsp.exec_cmd(codeEditor),     { description = "Apps: Code editor" })
hl.bind("CTRL + SUPER + SHIFT + ALT + W", hl.dsp.exec_cmd(officeSoftware),
    { description = "Apps: Office software" })
hl.bind("SUPER + X",      hl.dsp.exec_cmd(textEditor),     { description = "Apps: Text editor" })
hl.bind("CTRL + SUPER + V", hl.dsp.exec_cmd(volumeMixer),  { description = "Apps: Volume mixer" })
hl.bind("SUPER + I",      hl.dsp.exec_cmd(settingsApp),    { description = "Apps: Settings app" })
hl.bind("CTRL + SHIFT + Escape", hl.dsp.exec_cmd(taskManager),
    { description = "Apps: Task manager" })

-- ── Master Layout ─────────────────────────────────────────────────────
hl.bind("SUPER + Return", hl.dsp.layout("swapwithmaster"),
    { description = "Master Layout: Swap master window" })
hl.bind("SUPER + M",      hl.dsp.layout("focusmaster"),
    { description = "Master Layout: Focus master window" })
hl.bind("SUPER + comma",  hl.dsp.layout("addmaster"),
    { description = "Master Layout: Add master window" })
hl.bind("SUPER + Slash",  hl.dsp.layout("removemaster"),
    { description = "Master Layout: Remove master window" })
hl.bind("SUPER + Space",  hl.dsp.layout("orientationnext"),
    { description = "Master Layout: Swap master layout orientation" })

-- ── Scrolling Layout ──────────────────────────────────────────────────
-- The scrolloverview:overview dispatcher's colon is unparseable through
-- hl.dispatch's Lua wrap, so we go through the plugin's
-- addLuaFunction-exposed wrapper instead. The runtime guard avoids a
-- parse-time error if the plugin's Lua function isn't yet registered
-- (load is async).
hl.bind("SUPER + O", function()
    if hl.plugin and hl.plugin.scrolloverview and hl.plugin.scrolloverview.overview then
        hl.plugin.scrolloverview.overview("toggle")
    end
end, { description = "Scrolling Layout: Toggle Scrolling overview" })

-- ── Monocle Layout ────────────────────────────────────────────────────
hl.bind("SUPER + J", hl.dsp.layout("cyclenext"), { description = "Monocle Layout: Next window" })
hl.bind("SUPER + K", hl.dsp.layout("cycleprev"), { description = "Monocle Layout: Previous window" })

-- ── Screen ────────────────────────────────────────────────────────────
-- Cursor zoom — keypad bindings get no description so the cheatsheet
-- shows the readable Minus/Equal entries only.
local function zoomfunction(value)
    local zoomvalue = hl.get_config("cursor:zoom_factor")
    if (zoomvalue + value) > 3.0 then
        hl.config({ cursor = { zoom_factor = 3.0 } })
    elseif (zoomvalue + value) < 1.0 then
        hl.config({ cursor = { zoom_factor = 1.0 } })
    else
        hl.config({ cursor = { zoom_factor = zoomvalue + value } })
    end
end
hl.bind("SUPER + Minus", function() zoomfunction(-0.3) end,
    { repeating = true, description = "Screen: Zoom out" })
hl.bind("SUPER + Equal", function() zoomfunction(0.3) end,
    { repeating = true, description = "Screen: Zoom in" })
hl.bind("SUPER + code:82", function() zoomfunction(-0.3) end, { repeating = true })
hl.bind("SUPER + code:86", function() zoomfunction(0.3)  end, { repeating = true })

-- ── Gaming ────────────────────────────────────────────────────────────
hl.bind("SUPER + G",
    hl.dsp.exec_cmd("setsid -f " .. hyprScripts .. "/toggle_gamescope.sh"),
    { description = "Gaming: Toggle Steam Gamescope Mode" })

-- ── Utilities ─────────────────────────────────────────────────────────
-- Custom screenshot pipeline: Print → file + clipboard, Ctrl+Print →
-- file-only, Shift+Print → file + clipboard + Satty annotator.
hl.bind("Print", hl.dsp.exec_cmd(
    "mkdir -p ~/Pictures/Screenshots && grim - | tee ~/Pictures/Screenshots/Screenshot_\"$(date '+%Y-%m-%d_%H.%M.%S')\".png | wl-copy"
), { locked = true, description = "Utilities: Screenshot >> clipboard & file" })
hl.bind("CTRL + Print", hl.dsp.exec_cmd(
    "mkdir -p $(xdg-user-dir PICTURES)/Screenshots && grim $(xdg-user-dir PICTURES)/Screenshots/Screenshot_\"$(date '+%Y-%m-%d_%H.%M.%S')\".png"
), { locked = true, non_consuming = true, description = "Utilities: Screenshot >> file" })
hl.bind("SHIFT + Print", hl.dsp.exec_cmd(
    "mkdir -p ~/Pictures/Screenshots && SCREENSHOT=~/Pictures/Screenshots/Screenshot_\"$(date '+%Y-%m-%d_%H.%M.%S')\".png && grim - | tee \"$SCREENSHOT\" | wl-copy && SATTY_SIZE=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | \"\\((.width/.scale/2|floor))x\\((.height/.scale/2|floor))\"') && satty --filename \"$SCREENSHOT\" --resize \"$SATTY_SIZE\""
), { locked = true, description = "Utilities: Screenshot >> clipboard & file & Satty" })

-- ── Virtual machines ──────────────────────────────────────────────────
-- Upstream defines a "virtual-machine" submap toggled by SUPER+ALT+F1.
-- The submap-define binding itself doesn't carry a description, so the
-- cheatsheet has nothing to surface. Add a description-only bind on the
-- same key combo so the section gets an entry. The actual toggle still
-- runs from upstream's submap definition.
hl.bind("SUPER + ALT + F1", function() end,
    { description = "Virtual machines: Disable keybinds" })

-- ── Session ───────────────────────────────────────────────────────────
hl.bind("SUPER + L", hl.dsp.exec_cmd("loginctl lock-session"),
    { description = "Session: Lock" })
hl.bind("SUPER + SHIFT + L", hl.dsp.exec_cmd("systemctl suspend || loginctl suspend"),
    { locked = true, description = "Session: Sleep" })
hl.bind("CTRL + SHIFT + ALT + SUPER + Delete",
    hl.dsp.exec_cmd("systemctl poweroff || loginctl poweroff"),
    { description = "Session: Shutdown" })

-- ── User ──────────────────────────────────────────────────────────────
hl.bind("CTRL + SUPER + Slash",
    hl.dsp.exec_cmd("xdg-open ~/.config/illogical-impulse/config.json"),
    { description = "User: Edit shell config" })
hl.bind("CTRL + SUPER + ALT + Slash",
    hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"),
    { description = "User: Edit extra keybinds" })

-- ── Cursed / hidden ───────────────────────────────────────────────────
-- No description → not surfaced in the cheatsheet.
hl.bind("CTRL + SUPER + Backslash", hl.dsp.window.resize({ x = 640, y = 480 }))

-- Testing notifications (hidden).
hl.bind("SUPER + ALT + F11", hl.dsp.exec_cmd(
    "bash -c 'RANDOM_IMAGE=$(find ~/Pictures -type f | shuf -n 1); ACTION=$(notify-send \"Test notification with body image\" \"This notification should contain your user account <b>image</b> and <a href=\\\"https://discord.com/app\\\">Discord</a> <b>icon</b>. Oh and here is a random image in your Pictures folder: <img src=\\\"$RANDOM_IMAGE\\\" alt=\\\"Testing image\\\"/>\" -a \"Hyprland\" -p -h \"string:image-path:/var/lib/AccountsService/icons/$USER\" -t 6000 -i \"discord\" -A \"openImage=Profile image\" -A \"action2=Open the random image\" -A \"action3=Useless button\"); [[ $ACTION == *openImage ]] && xdg-open \"/var/lib/AccountsService/icons/$USER\"; [[ $ACTION == *action2 ]] && xdg-open \"$RANDOM_IMAGE\"'"))
hl.bind("SUPER + ALT + F12", hl.dsp.exec_cmd(
    "bash -c 'RANDOM_IMAGE=$(find ~/Pictures -type f | shuf -n 1); ACTION=$(notify-send \"Test notification\" \"This notification should contain a random image in your <b>Pictures</b> folder and <a href=\\\"https://discord.com/app\\\">Discord</a> <b>icon</b>.\n<i>Flick right to dismiss!</i>\" -a \"Discord (fake)\" -p -h \"string:image-path:$RANDOM_IMAGE\" -t 6000 -i \"discord\" -A \"openImage=Profile image\" -A \"action2=Useless button\"); [[ $ACTION == *openImage ]] && xdg-open \"/var/lib/AccountsService/icons/$USER\"'"))
hl.bind("SUPER + ALT + Equal", hl.dsp.exec_cmd(
    "notify-send 'Urgent notification' 'Ah hell no' -u critical -a 'Hyprland keybind'"))
