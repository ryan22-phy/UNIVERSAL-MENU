return function(_import)
    local Diagnostics = {}
    Diagnostics.__index = Diagnostics
    function Diagnostics.new()
        return setmetatable({ Values={}, Events={}, Limit=80 }, Diagnostics)
    end
    function Diagnostics:Set(key, value) self.Values[key] = value end
    function Diagnostics:Log(module, status, detail, parameters)
        local record = { Module=module, Status=status, Detail=tostring(detail),
            Parameters=parameters, Time=os.clock() }
        table.insert(self.Events, record)
        if #self.Events > self.Limit then table.remove(self.Events, 1) end
        if status == "ERROR" then warn("VW/" .. module .. ": " .. tostring(detail)) end
    end
    function Diagnostics:Snapshot()
        return { Values=table.clone(self.Values), Events=table.clone(self.Events) }
    end
    function Diagnostics:Destroy() table.clear(self.Values); table.clear(self.Events) end
    return Diagnostics
end
