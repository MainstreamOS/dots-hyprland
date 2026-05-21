-- Custom auto-start commands
-- https://wiki.hypr.land/Configuring/Keywords/#executing

hl.on("hyprland.start", function()
    -- Input method
    -- hl.exec_cmd("fcitx5")

    hl.exec_cmd("$HOME/.config/hypr/custom/scripts/bluetooth-autoconnect.sh")

    -- Hyprland 0.55 scrolloverview load-race workaround — see the script
    -- header for the full story. Logs to ~/.local/state/scrolloverview-power-cycle.log.
    hl.exec_cmd("$HOME/.config/hypr/custom/scripts/scrolloverview-power-cycle.sh")

    -- Userspace window-state restore. Self-gates on
    -- Config.options.session.restoreEnabled — no effect when off.
    -- Waiting on Hyprland to implement xdg-session-management-v1 upstream;
    -- this is a stopgap.
    hl.exec_cmd("$HOME/.config/quickshell/ii/scripts/session/restore.sh")
end)

hl.on("hyprland.shutdown", function()
    -- Capture the current window set so restore.sh can replay it next start.
    -- Same config gate; no effect when restore is disabled.
    hl.exec_cmd("$HOME/.config/quickshell/ii/scripts/session/snapshot.sh")
end)
