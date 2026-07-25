local home_dir = os.getenv("HOME")

-- Wayland
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

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

-- Themes
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")

-- Virtual environment
hl.env("ILLOGICAL_IMPULSE_VIRTUAL_ENV", home_dir .. "/.local/state/quickshell/.venv")
