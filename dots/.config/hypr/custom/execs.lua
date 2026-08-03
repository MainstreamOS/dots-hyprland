-- Custom auto-start commands
-- https://wiki.hypr.land/Configuring/Keywords/#executing

hl.on("hyprland.start", function()
    -- Input method
    -- hl.exec_cmd("fcitx5")

    hl.exec_cmd("$HOME/.config/hypr/custom/scripts/bluetooth-autoconnect.sh")

    -- Hyprland 0.55 scrolloverview load-race workaround — see the script
    -- header for the full story. Logs to ~/.local/state/scrolloverview-power-cycle.log.
    hl.exec_cmd("$HOME/.config/hypr/custom/scripts/scrolloverview-power-cycle.sh")

    -- Window-state restore, then the capturer that keeps the saved session
    -- current. Both self-gate on Config.options.session.restoreEnabled — no
    -- effect when off.
    --
    -- Capture runs all session long rather than at shutdown: hyprland.shutdown
    -- fires on the compositor's exit event, which only the `exit` dispatcher
    -- emits. A logout, loginctl, or a crash delivers SIGTERM or worse and
    -- never reaches it, so a shutdown hook would sit there looking like a
    -- safety net while restoring a session days out of date.
    hl.exec_cmd("$HOME/.config/quickshell/ii/scripts/session/restore.sh")
    hl.exec_cmd("$HOME/.config/quickshell/ii/scripts/session/watch.sh")
end)
