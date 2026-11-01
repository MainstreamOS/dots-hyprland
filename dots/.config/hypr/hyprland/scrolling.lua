-- How wide new windows are in the scrolling layout. Hyprland gives every new
-- column the one width in scrolling:column_width, so with thirds two windows
-- would leave a third of the screen empty. Choosing thirds here keeps the screen
-- filled instead: one window fills it, two take half each, three take a third
-- each, and every window after that is a third wide and scrolls on from there.
--
-- Settings > Layouts writes the choice to custom/scrolling.columns as how many
-- windows fit across. Two is what Hyprland does by itself, and 1.5 only changes the
-- width: nothing splits evenly at two-thirds, so nothing here runs for either.
local Scrolling = {}

local function readCustomValue(name)
    local f = io.open(os.getenv("HOME") .. "/.config/hypr/custom/" .. name, "r")
    if not f then return nil end
    local v = f:read("*l")
    f:close()
    return v
end

local across = tonumber(readCustomValue("scrolling.columns") or "")
if across ~= 1.5 and across ~= 3 then across = 2 end
-- 0.667 as the width keys' preset has it, so they step on from it rather than to it.
local width = across == 1.5 and 0.667 or 1 / across

local config = { focus_fit_method = readCustomValue("scrolling.center") == "1" and 0 or 1 }
if across ~= 2 then config.column_width = width end
hl.config({ scrolling = config })

-- Windows stacked in a column share a position along the tape, so counting the
-- positions counts the columns. Nil when the answer can't be trusted right now.
local function columnsOn(workspace)
    local direction = hl.get_config("scrolling:direction")
    local vertical = direction == "up" or direction == "down"
    local seen, count = {}, 0
    for _, w in ipairs(hl.get_workspace_windows(workspace)) do
        if w.fullscreen ~= 0 then return nil end
        if not w.floating then
            local at = vertical and w.at.y or w.at.x
            if not seen[at] then
                seen[at] = true
                count = count + 1
            end
        end
    end
    return count
end

-- Column counts by workspace. A workspace seen for the first time is only noted,
-- so a config reload leaves widths resized by hand alone.
local counts = {}

function Scrolling.fit(force)
    if across <= 2 and not force then return end
    local monitor = hl.get_active_monitor()
    local workspace = hl.get_active_workspace()
    -- Layout messages go to the focused monitor's workspace through its focused
    -- window, so another workspace waits until it is the one in front.
    if not monitor or not workspace or monitor.active_special_workspace then return end
    if workspace.tiled_layout ~= "scrolling" then return end
    local focused = hl.get_active_window()
    if not focused or focused.floating or not focused.workspace or focused.workspace.id ~= workspace.id then return end
    local count = columnsOn(workspace)
    if not count then return end
    local previous = counts[workspace.id]
    counts[workspace.id] = count
    if not force and (previous == nil or previous == count) then return end
    if count <= across then
        hl.dispatch(hl.dsp.layout("fit all"))
    elseif force or (previous and previous < across) then
        -- Past the limit a new window is already the right width from column_width.
        hl.dispatch(hl.dsp.layout("colresize all " .. width))
    end
end

-- A closing window has left the layout only once this event is over, so each of
-- these looks a moment later, and a burst of them looks once.
local pending = false
function Scrolling.fitSoon()
    if pending then return end
    pending = true
    hl.timer(function()
        pending = false
        Scrolling.fit()
    end, { timeout = 1, type = "oneshot" })
end

if across > 2 then
    for _, event in ipairs({ "window.open", "window.close", "window.move_to_workspace", "window.active", "workspace.active" }) do
        hl.on(event, Scrolling.fitSoon)
    end
end

-- Settings calls this after a new choice, which should show straight away.
function MainstreamScrollingRefit()
    Scrolling.fit(true)
end

return Scrolling
