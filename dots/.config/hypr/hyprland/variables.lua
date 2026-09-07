-- Default variables
-- Copy these to ~/.config/hypr/custom/variables.lua to make changes in a dotfiles-update-friendly manner

-- The folder within ~/.config/quickshell containing the config
hl.env("qsConfig", "ii")

-- Apps
-- PULL REQUESTS ADDING MORE WILL NOT BE ACCEPTED, CONFIG FOR YOURSELF
--
-- Settings > Manage writes the app chosen for a role into one file per
-- role under custom/, read here on every reload so a key opens the same app a
-- double click does. Each chain below stays the fallback for a role nobody has
-- picked: the first of those installed is what runs.
local HOME = os.getenv("HOME") or ""

local function chosenApp(role, fallback)
    local f = io.open(HOME .. "/.config/hypr/custom/apps." .. role, "r")
    if not f then return fallback end
    -- First line names the app for the Settings page, second is what to run.
    f:read("*l")
    local command = f:read("*l")
    f:close()
    if command == nil or command == "" then return fallback end
    return command
end
terminal = chosenApp("terminal", "~/.config/hypr/hyprland/scripts/launch_first_available.sh 'kitty -1' 'foot' 'alacritty' 'wezterm' 'konsole' 'kgx' 'uxterm' 'xterm'")
fileManager = chosenApp("fileManager", "~/.config/hypr/hyprland/scripts/launch_first_available.sh 'nautilus --new-window' 'dolphin' 'nemo' 'thunar' 'kitty -1 fish -c yazi'")
browser = chosenApp("browser", "~/.config/hypr/hyprland/scripts/launch_first_available.sh 'chromium' 'zen-browser' 'firefox' 'brave' 'microsoft-edge-stable' 'opera' 'librewolf'")
codeEditor = chosenApp("codeEditor", "~/.config/hypr/hyprland/scripts/launch_first_available.sh 'windsurf' 'antigravity' 'code' 'codium' 'cursor' 'zed' 'zedit' 'zeditor' 'kate' 'gnome-text-editor' 'emacs' 'command -v nvim && kitty -1 nvim' 'command -v micro && kitty -1 micro'")
officeSoftware = "~/.config/hypr/hyprland/scripts/launch_first_available.sh 'wps' 'onlyoffice-desktopeditors' 'libreoffice'"
textEditor = chosenApp("textEditor", "~/.config/hypr/hyprland/scripts/launch_first_available.sh 'kate' 'gnome-text-editor' 'emacs'")
volumeMixer = "~/.config/hypr/hyprland/scripts/launch_first_available.sh 'pavucontrol-qt' 'pavucontrol'"
settingsApp = "XDG_CURRENT_DESKTOP=gnome ~/.config/hypr/hyprland/scripts/launch_first_available.sh 'qs -p ~/.config/quickshell/$qsConfig/settings.qml' 'systemsettings' 'gnome-control-center' 'better-control'"
taskManager = "~/.config/hypr/hyprland/scripts/launch_first_available.sh 'gnome-system-monitor' 'plasma-systemmonitor --page-name Processes' 'command -v btop && kitty -1 fish -c btop'"

workspaceGroupSize = 10
