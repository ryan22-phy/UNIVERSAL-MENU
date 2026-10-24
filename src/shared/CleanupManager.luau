--!strict
return function(_import)
    local CleanupManager = {}
    CleanupManager.__index = CleanupManager

    function CleanupManager.new()
        return setmetatable({ _items = {}, _destroyed = false }, CleanupManager)
    end

    local function release(item)
        local kind = typeof(item)
        if kind == "RBXScriptConnection" then item:Disconnect()
        elseif kind == "Instance" then item:Destroy()
        elseif type(item) == "function" then item()
        elseif type(item) == "table" and type(item.Destroy) == "function" then item:Destroy()
        end
    end

    function CleanupManager:Add(item)
        if self._destroyed then
            local ok, err = pcall(release, item)
            if not ok then warn("VW cleanup: " .. tostring(err)) end
        else table.insert(self._items, item) end
        return item
    end

    function CleanupManager:Destroy()
        if self._destroyed then return end
        self._destroyed = true
        for i = #self._items, 1, -1 do
            local ok, err = pcall(release, self._items[i])
            if not ok then warn("VW cleanup: " .. tostring(err)) end
        end
        table.clear(self._items)
    end

    return CleanupManager
end
