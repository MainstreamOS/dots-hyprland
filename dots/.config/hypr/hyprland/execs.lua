-- put former exec-once commands inside the func and former exec commands outside
hl.on("hyprland.start", function ()

    -- Session env + hyprland-session.target must be up BEFORE any Qt app
    -- launches (the portal is Requisite= on it; Qt init stalls on a portal
    -- that cannot start), so qs is chained after them in one exec_cmd —
    -- separate exec_cmd calls have no ordering guarantee. --no-block matters:
    -- a plain start waits for the WHOLE transaction, every service the
    -- session pulls in, and qs would not spawn until the slowest had started.
    -- The target itself activates immediately; only the wanted units keep
    -- starting.
    hl.exec_cmd(table.concat({
        -- A crash can leave these targets active, and starting an active target skips
        -- what it wants, so the ones an earlier session left are stopped first.
        "(\"$HOME/.config/hypr/hyprland/scripts/stop_stale_session.sh\" --login || true)",
        "dbus-update-activation-environment --all",
        "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP",
        "systemctl --user start --no-block hyprland-session.target",
        -- Apps wait, bounded, for the shell's tray, as Discord shows no icon if it
        -- starts without one. Kept in the chain so they never start before the stop.
        "{ (gdbus wait --session --timeout 10 org.kde.StatusNotifierWatcher; systemctl --user start --no-block hyprland-autostart.target) & }",
        "(systemctl --user try-restart xdg-desktop-portal-hyprland.service || true)",
        -- An update can leave the shell's own files for after it has finished
        -- (finish-deferred.sh in the dotfiles clone). When nothing got to them
        -- before the session ended, they go in here, before the shell reads them,
        -- bounded so the shell is never held back for long. This login is what
        -- the Update page's "log out and back in" note asks for, so it goes too,
        -- unless some of those files are still waiting.
        "(d=\"$HOME/.cache/dots-hyprland\"; if [ -s \"$d/.update-deferred\" ] && [ -f \"$d/sdata/subcmd-exp-update/finish-deferred.sh\" ]; then timeout -k 5 60 bash \"$d/sdata/subcmd-exp-update/finish-deferred.sh\" --login >/dev/null 2>&1; fi; [ -s \"$d/.update-deferred\" ] || rm -f \"${XDG_STATE_HOME:-$HOME/.local/state}/mainstream/relogin-needed\"; true)",
        "qs -n -c $qsConfig",
    }, " && "))

    -- Bar, wallpaper
    hl.exec_cmd("$HOME/.config/hypr/hyprland/scripts/start_geoclue_agent.sh")
    hl.exec_cmd("$HOME/.config/hypr/custom/scripts/__restore_video_wallpaper.sh")
    -- The layout picked on the login screen leads this session's list, kept
    -- in Settings' own list and handed to localed, so the desktop types in
    -- what the password was typed in.
    hl.exec_cmd("$HOME/.config/quickshell/ii/scripts/keyboard/login-layout.sh")

    -- Core components (authentication, lock screen, notification daemon)
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
 hl.exec_cmd("sh -c 'command -v spice-vdagent >/dev/null && systemd-detect-virt -q && exec spice-vdagent'")
    hl.exec_cmd("hypridle")

    -- Audio
    hl.exec_cmd("easyeffects --hide-window --service-mode")

    -- Clipboard: history
    --hl.exec_cmd("wl-paste --watch cliphist store")
    hl.exec_cmd("wl-paste --type text --watch bash -c 'cliphist store && qs -c $qsConfig ipc call cliphistService update'")
    hl.exec_cmd("wl-paste --type image --watch bash -c 'cliphist store && qs -c $qsConfig ipc call cliphistService update'")

    -- Cursor: follow the theme and size picked in Settings, falling back to the
    -- shipped ones when that choice names a theme this machine hasn't got.
    hl.exec_cmd("$HOME/.config/quickshell/ii/scripts/cursor/apply-cursor.sh")

    -- GTK/Qt interface fonts follow the shell's font choice (config.json).
    hl.exec_cmd("$HOME/.config/quickshell/ii/scripts/themes/apply-gtk-font.sh")

    -- Gaming Mode: strip any autologin User= from /etc/sddm.conf so normal
    -- boots/logouts reach the SDDM password greeter (no-op on a fresh desktop).
    -- Redundant with the sddm.service ExecStartPre (gaming-mode-arm-check), the
    -- authoritative boot-time reset; this just closes the gap if the user logs
    -- straight out of a gaming-exit session without an intervening reboot.
    hl.exec_cmd("sudo -n /usr/bin/gaming-mode-switch reset 2>/dev/null || true")

    -- Gaming Mode: one-time tip on the first return from a gaming session, pointing
    -- at Steam's "Automatically Set Resolution" toggle (defaults on, renders soft, and
    -- has no config lever to flip for the user). No-op until armed and never repeats.
    hl.exec_cmd("/usr/bin/gaming-mode --tips")
end)

hl.on("hyprland.shutdown", function()
    hl.exec_cmd("systemctl --user stop hyprland-session.target")
end)
