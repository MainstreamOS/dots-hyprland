-- Workspace names are display labels in 0.57; only numbered workspaces have IDs.
local M = {}

function M.normalizeSelector(address)
    if address == nil or address == "" then return nil end
    address = tostring(address)
    if address == "special:special" then return "special" end
    if tonumber(address) or address == "special" or address:match("^special:") or address:match("^name:") then
        return address
    end
    return "name:" .. address
end

function M.selector(workspace)
    if not workspace then return nil end
    if workspace.id and workspace.id > 0 then return tostring(workspace.id) end
    if workspace.addressable_name and workspace.addressable_name ~= "" then
        if workspace.special or (workspace.special == nil and workspace.addressable_name:match("^special:")) then
            return M.normalizeSelector(workspace.addressable_name)
        end
        return "name:" .. workspace.addressable_name
    end
    -- Compatibility with the pre-0.57 Lua objects.
    if workspace.id == -99 then return "special" end
    return M.normalizeSelector(workspace.name)
end

function M.same(a, b)
    local address = M.selector(a)
    return address ~= nil and address == M.selector(b)
end

function M.isScratchpad(workspace)
    return M.selector(workspace) == "special"
end

return M
