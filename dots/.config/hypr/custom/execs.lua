-- Custom auto-start commands
-- https://wiki.hypr.land/Configuring/Keywords/#executing

hl.on("hyprland.start", function()
    -- Input method
    -- hl.exec_cmd("fcitx5")

    hl.exec_cmd("$HOME/.config/hypr/custom/scripts/bluetooth-autoconnect.sh")
end)

-- The scrolloverview load-race workaround used to live here as an exec-once
-- of scrolloverview-power-cycle.sh. It now lives in custom/general.lua,
-- triggered by hl.on("layer.opened") filtered by Quickshell namespace —
-- same cycle (hyprctl plugin unload/load) but a deterministic trigger
-- instead of bash polling.
