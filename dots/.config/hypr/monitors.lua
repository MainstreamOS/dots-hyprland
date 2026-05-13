-- Monitor configuration. Quickshell Settings → Display rewrites this
-- file with explicit hl.monitor({...}) blocks the first time the user
-- changes anything; until then, the loop below auto-picks a scale per
-- monitor so the desktop looks right out of the box.
--
-- Heuristic targets the same effective ~92 PPI you get from a 4K 32"
-- at 1.5x. Hyprland's Lua bindings (HL.Monitor.physical_size) don't
-- expose EDID-derived physical dimensions, so we can't compute true
-- PPI — instead we infer "typical diagonal for this resolution" from
-- the resolution bucket, which gets the right answer for the common
-- desktop monitors and ultrawides. Unusual form factors (4K 27"
-- monitors, 1080p 32" TVs, HiDPI laptops) will need a one-time tweak
-- via Settings → Display.
--
-- Scales snap to Hyprland's clean-fraction ladder (1, 1.25, 1.5, 2)
-- to avoid the integer-rounding artifacts of arbitrary fractions.
local function pickScale(w, h)
    local px = w * h
    if px <= 1920 * 1080 then return 1.0      -- 1080p assume ~24" → ~92 native PPI
    elseif px <= 2560 * 1440 then return 1.25 -- 1440p assume ~27" → ~109 PPI
    elseif px <= 3440 * 1440 then return 1.25 -- ultrawide assume ~34" → ~110 PPI
    elseif px <= 3840 * 2160 then return 1.5  -- 4K assume ~32" → ~138 PPI (target)
    elseif px <= 5120 * 2880 then return 2.0  -- 5K assume ~27" → ~218 PPI
    else return 2.0                            -- 8K+ default; tune via Settings
    end
end

for _, m in ipairs(hl.get_monitors() or {}) do
    hl.monitor({
        output   = m.name,
        mode     = "preferred",
        position = "auto",
        scale    = tostring(pickScale(m.width, m.height)),
    })
end
