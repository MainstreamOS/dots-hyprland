-- Hyprland config for the SDDM greeter's own compositor instance.
-- Separate from the user session's config, which lives in ~/.config/hypr.
--
-- Installed to /var/lib/sddm/.config/hypr/hyprland.lua by
-- scripts/setup-sddm-pixie.sh on a fresh setup, and refreshed there by
-- sdata/update/updatems-system on every update. archiso ships its own copy of
-- the same content for the ISO install path.
--
-- Lua rather than .conf: Hyprland 0.56.1 shows a deprecation notice on any
-- .conf config, and the greeter is the first thing anyone sees. Support for
-- the format goes away entirely in 0.57.

-- SDDM and the user session run separate Hyprland instances. Recover the last
-- logged-in user's saved Num Lock state before the greeter configures input.
local function persistedNumlockState()
    local state = io.open("/var/lib/sddm/state.conf", "r")
    if not state then
        return nil
    end

    local username
    for line in state:lines() do
        username = line:match("^User%s*=%s*(.-)%s*$")
        if username and username ~= "" then
            break
        end
    end
    state:close()
    if not username then
        return nil
    end

    local passwd = io.open("/etc/passwd", "r")
    if not passwd then
        return nil
    end

    local home
    for line in passwd:lines() do
        local user, userHome = line:match("^([^:]+):[^:]*:[^:]*:[^:]*:[^:]*:([^:]+):")
        if user == username then
            home = userHome
            break
        end
    end
    passwd:close()
    if not home then
        return nil
    end

    local saved = io.open(home .. "/.local/state/mainstream/numlock", "r")
    if not saved then
        return nil
    end
    local value = saved:read("*l")
    saved:close()

    if value == "1" then
        return true
    elseif value == "0" then
        return false
    end
    return nil
end

local function inheritedNumlockState()
    local persisted = persistedNumlockState()
    if persisted ~= nil then
        return persisted
    end

    local reader = io.popen([[
for path in /sys/class/leds/*::numlock/brightness; do
    [ -r "$path" ] && cat "$path"
done
]])
    if not reader then
        return true
    end

    local found = false
    local enabled = false
    for value in reader:lines() do
        found = true
        if value:match("^%s*1%s*$") then
            enabled = true
        end
    end
    reader:close()

    if not found then
        return true
    end
    return enabled
end

-- The layout the machine types in, read at greeter start rather than written
-- in when the file is installed. The password box is the one place a wrong
-- layout locks somebody out, and a copy pasted in at install time is lost the
-- moment anything refreshes this file — which is exactly what an update does.
-- Read from systemd-localed's keyboard config, then the console keymap.
local function systemKeyboardLayout()
    local conf = io.open("/etc/X11/xorg.conf.d/00-keyboard.conf", "r")
    if conf then
        local layout, variant
        for line in conf:lines() do
            layout = layout or line:match('Option%s+"XkbLayout"%s+"([^"]*)"')
            variant = variant or line:match('Option%s+"XkbVariant"%s+"([^"]*)"')
        end
        conf:close()
        -- localed writes XKB names here, so this is the trustworthy source. A
        -- comma-separated pair is allowed: that is how more than one layout is
        -- spelled.
        if layout and layout:match("^[%a,]+$") then
            return layout, variant or ""
        end
    end

    local vconsole = io.open("/etc/vconsole.conf", "r")
    if vconsole then
        local keymap
        for line in vconsole:lines() do
            keymap = keymap or line:match("^KEYMAP=(.-)%s*$")
        end
        vconsole:close()
        if keymap then
            keymap = keymap:gsub('"', "")
            -- Console keymaps are not XKB layout names: they carry a variant
            -- after a dash and a hardware number at the end (fr-latin1, jp106).
            -- Trim both, then insist on a plain name, because a layout XKB does
            -- not know is worse at the password box than falling back.
            keymap = keymap:match("^([^-]+)") or keymap
            keymap = keymap:gsub("%d+$", "")
            if keymap:match("^%a%a+$") then
                return keymap, ""
            end
        end
    end

    return nil, nil
end

local kbLayout, kbVariant = systemKeyboardLayout()

hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "1",
})

if kbLayout then
    hl.config({
        input = {
            kb_layout = kbLayout,
            kb_variant = kbVariant,
        },
    })
end

hl.config({
    input = {
        numlock_by_default = inheritedNumlockState(),
    },
    misc = {
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        force_default_wallpaper  = 0,
        disable_watchdog_warning = true,
    },
    animations = {
        enabled = false,
    },
})

hl.window_rule({ match = { class = "^(sddm-greeter-qt6)$" }, fullscreen = true })
