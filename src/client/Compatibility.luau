return function(_import)
    local Compatibility = {}
    function Compatibility.Probe(ctx)
        local result = { ScreenGui=false, Highlight=false, BillboardGui=false,
            LinearVelocity=false, AlignOrientation=false, Raycast=false,
            Drawing=false, gethui=false, getgenv=false, loadstring=false,
            HttpGet=false, request=false }
        -- Native classes are actually constructed, then immediately destroyed.
        for _, name in ipairs({ "ScreenGui", "Highlight", "BillboardGui", "LinearVelocity", "AlignOrientation" }) do
            local ok, object = pcall(Instance.new, name)
            result[name] = ok
            if ok then object:Destroy()
            else ctx.Diagnostics:Log("Compatibility","UNAVAILABLE",name..": "..tostring(object)) end
        end
        local env = _G
        local ok, candidate = pcall(function()
            if type(getgenv) == "function" then return getgenv() end
            return nil
        end)
        if ok and type(candidate) == "table" then env = candidate; result.getgenv = true
        elseif not ok then ctx.Diagnostics:Log("Compatibility","FALLBACK","getgenv: "..tostring(candidate)) end
        result.Drawing = type(env.Drawing) == "table"
        result.gethui = type(env.gethui) == "function"
        result.loadstring = type(loadstring) == "function" or type(env.loadstring) == "function"
        result.request = type(env.request) == "function" or type(env.http_request) == "function"
        local httpOK,httpMethod=pcall(function() return game.HttpGet end)
        result.HttpGet = httpOK and type(httpMethod)=="function"
        local raycastOK,raycastError=pcall(function() return ctx.Services.Workspace:Raycast(Vector3.zero, Vector3.new(0, 0.001, 0)) end)
        result.Raycast=raycastOK
        if not raycastOK then ctx.Diagnostics:Log("Compatibility","UNAVAILABLE","Raycast: "..tostring(raycastError)) end
        result.Note = "Presença não comprova compatibilidade Xeno; HTTP real só é testado pelo loader/check de versão."
        for name, value in pairs(result) do ctx.Diagnostics:Set("API." .. name, value) end
        return result
    end
    return Compatibility
end
