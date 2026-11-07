-- Explicit rules belong to the user. Dynamic keep-alive only writes defaults.
local writeRule = hl.workspace_rule
local explicit = {}
local activeDefaults = {}
local hasFilter = false

hl.workspace_rule = function(rule, ...)
    if type(rule) == "table" and rule.persistent ~= nil then
        local selector = tostring(rule.workspace)
        local id = selector:match("^%d+$") and tonumber(selector)
        if id then
            explicit[id] = true
            activeDefaults[id] = nil
        elseif not hasFilter and selector:find("[", 1, true) then
            -- A selector can overlap numbered workspaces and may depend on live
            -- state. Release our defaults before Hyprland adds the user's rule.
            hasFilter = true
            for workspace in pairs(activeDefaults) do
                writeRule({ workspace = tostring(workspace), persistent = false })
            end
            activeDefaults = {}
        end
    end
    return writeRule(rule, ...)
end

return {
    setDefault = function(id, persistent)
        if not hasFilter and not explicit[id] and (persistent or activeDefaults[id]) then
            writeRule({ workspace = tostring(id), persistent = persistent })
            activeDefaults[id] = persistent or nil
        end
    end,
}
