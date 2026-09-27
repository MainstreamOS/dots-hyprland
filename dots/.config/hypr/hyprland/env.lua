local home_dir = os.getenv("HOME")

-- Wayland
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
-- GTK 4.24 hangs a background-effect object on every window but only fills in
-- a blur region when the app asks for backdrop blur itself, and Hyprland reads
-- an empty region as "never blur this window". Without the protocol, GTK 4
-- windows are blurred by the same rules as every other window.
hl.env("GDK_WAYLAND_DISABLE", "ext_background_effect_manager_v1")

-- Applications
-- Deduplicate, keeping the first occurrence. This file runs again on every
-- config reload, so prepending unconditionally would leave another copy of
-- the list behind each time. Lookups are first-match-wins, so dropping the
-- later duplicates changes nothing except how much work an application does
-- when it searches these directories.
local xdg_data_dirs_old = os.getenv("XDG_DATA_DIRS") or ""
local xdg_data_dirs_seen = {}
local xdg_data_dirs = {}
for dir in (home_dir .. "/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share:" .. xdg_data_dirs_old):gmatch("[^:]+") do
    if not xdg_data_dirs_seen[dir] then
        xdg_data_dirs_seen[dir] = true
        xdg_data_dirs[#xdg_data_dirs + 1] = dir
    end
end
hl.env("XDG_DATA_DIRS", table.concat(xdg_data_dirs, ":"))

-- VMware's virtual GPU (vmwgfx, which VirtualBox's VMSVGA adapter uses too)
-- hands over app buffers as surfaces Hyprland cannot release, so Hyprland
-- turns away every window an app draws on the GPU and the desktop stays
-- black. Where mainstream-system's fix for that is loaded into this Hyprland,
-- apps keep drawing on the GPU; anywhere it is missing, drawing in software
-- keeps the session usable. The fix is looked for in this process's own
-- memory map, since anything in the environment would also reach a Hyprland
-- started from inside the session, which does not get the library. It is
-- checked at every start rather than written at install, so a VM moved to
-- other graphics follows it. A LIBGL_ALWAYS_SOFTWARE of 0 in custom/env.lua
-- undoes it.
local function drmDriverPresent(name)
    for i = 0, 7 do
        local uevent = io.open("/sys/class/drm/card" .. i .. "/device/uevent", "r")
        if uevent then
            local text = uevent:read("a") or ""
            uevent:close()
            if text:find("DRIVER=" .. name .. "\n", 1, true) then
                return true
            end
        end
    end
    return false
end
local function vmwgfxCloseLoaded()
    local maps = io.open("/proc/self/maps", "r")
    if not maps then
        return false
    end
    local text = maps:read("a") or ""
    maps:close()
    return text:find("/libmainstream-vmwgfx-close.so", 1, true) ~= nil
end
if drmDriverPresent("vmwgfx") and not vmwgfxCloseLoaded() then
    hl.env("LIBGL_ALWAYS_SOFTWARE", "1")
end

-- Themes
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")

-- Virtual environment
hl.env("ILLOGICAL_IMPULSE_VIRTUAL_ENV", home_dir .. "/.local/state/quickshell/.venv")
