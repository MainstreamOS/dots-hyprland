-- put former exec-once commands inside the func and former exec commands outside
hl.on("hyprland.start", function ()

    -- Session env + hyprland-session.target must be up BEFORE any Qt app
    -- launches (the portal is Requisite= on it; Qt init stalls on a portal
    -- that cannot start), so qs is chained after them in one exec_cmd —
    -- separate exec_cmd calls have no ordering guarantee. --no-block matters:
    -- a plain start waits for the WHOLE transaction, which via
    -- xdg-desktop-autostart.target includes Discord and friends — qs would
    -- not spawn until every autostart app finished launching. The target
    -- itself activates immediately; only the wanted units keep starting.
    hl.exec_cmd("dbus-update-activation-environment --all && dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP && systemctl --user start --no-block hyprland-session.target && (systemctl --user try-restart xdg-desktop-portal-hyprland.service || true) && qs -n -c $qsConfig")

    -- Bar, wallpaper
    hl.exec_cmd("$HOME/.config/hypr/hyprland/scripts/start_geoclue_agent.sh")
    hl.exec_cmd("$HOME/.config/hypr/custom/scripts/__restore_video_wallpaper.sh")

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

    -- Cursor
    hl.exec_cmd("hyprctl setcursor Bibata-Modern-Classic 24")

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
