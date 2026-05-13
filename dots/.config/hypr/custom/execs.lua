-- Custom auto-start commands
-- https://wiki.hypr.land/Configuring/Keywords/#executing

hl.on("hyprland.start", function()
    -- Input method
    -- hl.exec_cmd("fcitx5")

    hl.exec_cmd("$HOME/.config/hypr/custom/scripts/bluetooth-autoconnect.sh")

    -- Hyprland 0.55 scrolloverview load-race workaround — see the script
    -- header for the full story. Logs to ~/.local/state/scrolloverview-power-cycle.log.
    hl.exec_cmd("$HOME/.config/hypr/custom/scripts/scrolloverview-power-cycle.sh")
end)
