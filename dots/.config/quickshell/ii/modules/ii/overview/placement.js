.pragma library

function quote(text) {
    return '"' + text.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n").replace(/\r/g, "\\r") + '"';
}

// Use the compositor's column operations, not a window swap (a side drop makes a column,
// top/bottom inserts into its stack), in one eval so focus cannot change midway.
function script(address, workspace, anchor, direction, x, y) {
    return `(function()
        local selector = ${quote("address:" + address)}
        local w = hl.get_window(selector)
        if not w or not w.mapped then return end
        local previous = hl.get_active_window()
        local previousWorkspace = hl.get_active_workspace(w.monitor.id)
        local cursor = hl.get_cursor_pos()
        local originalWidth = w.layout and w.layout.column and w.layout.column.width
        local destination = ${typeof workspace === "number" ? workspace : quote(workspace)}
        local a = hl.get_window(${quote("address:" + anchor)})
        local side = ${quote(direction)}
        local function focus(window)
            hl.dispatch(hl.dsp.focus({window = "address:" .. window.address}))
        end
        local function message(text)
            hl.dispatch(hl.dsp.layout(text))
        end
        local function column(window)
            return window.layout and window.layout.column and window.layout.column.index
        end
        local function restore()
            if previousWorkspace and w.workspace.id ~= previousWorkspace.id then
                hl.dispatch(hl.dsp.focus({workspace = previousWorkspace.id}))
                if previous and previous.mapped and previous.workspace.id == previousWorkspace.id then focus(previous) end
            elseif previous and previous.mapped and previous.workspace.id ~= w.workspace.id then
                focus(previous)
            end
            if cursor then hl.dispatch(hl.dsp.cursor.move({x = cursor.x, y = cursor.y})) end
        end
        focus(w)
        if hl.get_active_window() ~= w then
            print("overview-placement-focus-pending")
            return
        end
        if (type(destination) == "number" and w.workspace.id ~= destination)
            or (type(destination) == "string" and w.workspace.name ~= destination) then
            hl.dispatch(hl.dsp.window.move({workspace = destination, follow = false, window = selector}))
        end
        if w.floating then
            hl.dispatch(hl.dsp.window.move({x = ${Math.round(x)}, y = ${Math.round(y)}, window = selector}))
        elseif a and a.mapped and a ~= w and a.workspace.id == w.workspace.id then
            if a.layout and a.layout.name == "scrolling" and column(w) ~= nil then
                local stacking = side == "u" or side == "d"
                local sameColumn = column(w) == column(a)
                focus(w)
                if not stacking or not sameColumn then
                    if w.layout.column.windows and #w.layout.column.windows > 1 then message("promote") end
                    -- Bring the single-window column immediately beside its anchor.
                    local before = not stacking and side == "l"
                    for i = 1, 256 do
                        local wi, ai = column(w), column(a)
                        if wi == nil or ai == nil then break end
                        if (before and wi + 1 == ai) or (not before and wi == ai + 1) then break end
                        message(wi < ai and "swapcol r" or "swapcol l")
                    end
                    if stacking then
                        focus(a)
                        if a.fullscreen ~= 0 then
                            hl.dispatch(hl.dsp.window.fullscreen_state({internal = 0, client = 0, window = "address:" .. a.address}))
                            message("colresize 1")
                        end
                        message("consume")
                        focus(w)
                    elseif originalWidth then
                        message("colresize " .. tostring(originalWidth))
                    end
                end
                if stacking and column(w) == column(a) then
                    for i = 1, 256 do
                        local wi, ai = w.layout.index_in_column, a.layout.index_in_column
                        if (side == "u" and wi + 1 == ai) or (side == "d" and wi == ai + 1) then break end
                        hl.dispatch(hl.dsp.window.move({direction = wi < ai and "d" or "u", window = selector}))
                    end
                end
            elseif a.layout and a.layout.name == "monocle" then
                hl.dispatch(hl.dsp.window.swap({window = selector, target = "address:" .. a.address}))
            elseif a.layout and a.layout.name == "dwindle" then
                -- Reinsert beside the chosen leaf, rather than swapping its
                -- place in the tree. One eval keeps the temporary float offscreen.
                local useActive = hl.get_config("dwindle:use_active_for_splits")
                hl.config({dwindle = {use_active_for_splits = true}})
                hl.dispatch(hl.dsp.window.float({action = "set", window = selector}))
                focus(a)
                message("preselect " .. side)
                hl.dispatch(hl.dsp.window.float({action = "unset", window = selector}))
                message("preselect none")
                hl.config({dwindle = {use_active_for_splits = useActive}})
            else
                hl.dispatch(hl.dsp.window.swap({window = selector, target = "address:" .. a.address}))
            end
        elseif originalWidth and column(w) ~= nil then
            focus(w)
            message("colresize " .. tostring(originalWidth))
        end
        restore()
    end)()`;
}

// Focusing a scrolling window can recenter its column. Apply the preview's
// screen position after focus so entering a workspace keeps the shown view.
function activateScript(address, x, preservePointer = false) {
    return `(function()
        local w = hl.get_window(${quote("address:" + address)})
        if not w or not w.mapped then return end
        ${preservePointer ? `-- Suppress the focus warp instead of moving the pointer back: moving
        -- it synthesizes mouse input and can focus a different window again.
        local noWarps = hl.get_config("cursor:no_warps")
        hl.config({cursor = {no_warps = true}})
        local ok, err = pcall(hl.dispatch, hl.dsp.focus({window = "address:" .. w.address}))
        hl.config({cursor = {no_warps = noWarps}})
        if not ok then error(err) end` : 'hl.dispatch(hl.dsp.focus({window = "address:" .. w.address}))'}
        if hl.get_active_window() ~= w then
            print("overview-placement-focus-pending")
            return
        end
        ${Number.isFinite(x) ? `if w.layout and w.layout.name == "scrolling" then
            local delta = ${Math.round(x)} - w.at.x
            if math.abs(delta) > 1 then hl.dispatch(hl.dsp.layout("move " .. tostring(delta))) end
        end` : ""}
    end)()`;
}
