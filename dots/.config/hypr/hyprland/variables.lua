-- Default variables
-- Copy these to ~/.config/hypr/custom/variables.lua to make changes in a dotfiles-update-friendly manner

-- The folder within ~/.config/quickshell containing the config
hl.env("qsConfig", "ii")

-- Apps
-- PULL REQUESTS ADDING MORE WILL NOT BE ACCEPTED, CONFIG FOR YOURSELF
--
-- Settings > Manage writes app choices under custom/ for these shortcuts.
-- The browser shortcut reads the current default for web links at launch time.
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
browser = "~/.config/quickshell/$qsConfig/scripts/apps/default-apps.sh launch-browser"
    .. " || ~/.config/hypr/hyprland/scripts/launch_first_available.sh"
    .. " 'chromium' 'zen-browser' 'firefox' 'brave' 'brave-browser' 'google-chrome-stable'"
    .. " 'microsoft-edge-stable' 'opera' 'vivaldi' 'librewolf'"
codeEditor = chosenApp("codeEditor", "~/.config/hypr/hyprland/scripts/launch_first_available.sh 'windsurf' 'antigravity' 'code' 'codium' 'cursor' 'zed' 'zedit' 'zeditor' 'kate' 'gnome-text-editor' 'emacs' 'command -v nvim && kitty -1 nvim' 'command -v micro && kitty -1 micro'")
officeSoftware = "~/.config/hypr/hyprland/scripts/launch_first_available.sh 'wps' 'onlyoffice-desktopeditors' 'libreoffice'"
textEditor = chosenApp("textEditor", "~/.config/hypr/hyprland/scripts/launch_first_available.sh 'kate' 'gnome-text-editor' 'emacs'")
volumeMixer = "~/.config/hypr/hyprland/scripts/launch_first_available.sh 'pavucontrol-qt' 'pavucontrol'"
settingsApp = "XDG_CURRENT_DESKTOP=gnome ~/.config/hypr/hyprland/scripts/launch_first_available.sh '~/.config/quickshell/$qsConfig/scripts/settings/open-settings.sh' 'systemsettings' 'gnome-control-center' 'better-control'"
taskManager = "~/.config/hypr/hyprland/scripts/launch_first_available.sh 'gnome-system-monitor' 'plasma-systemmonitor --page-name Processes' 'command -v btop && kitty -1 fish -c btop'"

workspaceGroupSize = 10
