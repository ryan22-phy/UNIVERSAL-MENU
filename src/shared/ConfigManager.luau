-- Config validation is independent of Roblox services and can be tested in Luau CLI.
return function(_import)
    local ConfigManager = {}
    ConfigManager.__index = ConfigManager
    local schema = {}
    local function define(group, name, default, min, max, choices)
        schema[group .. "." .. name] = { Default = default, Min = min, Max = max, Choices = choices }
    end
    define("Aim", "Enabled", false)
    define("Aim", "FOV", 120, 20, 400)
    define("Aim", "Smoothness", 12, 1, 40)
    define("Aim", "MaxDistance", 1000, 10, 5000)
    for key, value in pairs({ VisibilityCheck=true, TeamCheck=true, HeadPriority=true,
        Fallback=true, TargetLock=true, ShowFOV=true }) do define("Aim", key, value) end
    define("Aim", "FallbackPart", "HumanoidRootPart", nil, nil, { "UpperTorso", "Torso", "HumanoidRootPart" })
    define("Aim", "SwitchDelay", 0.2, 0, 2)
    define("Aim", "Mode", "Hold", nil, nil, { "Hold", "Toggle" })
    define("Aim", "Key", "MouseButton2")
    define("Aim", "Priority", "Angle", nil, nil, { "Angle", "Distance" })
    define("Aim", "Prediction", 0, 0, 0.5)
    for key, value in pairs({ Enabled=false, Players=true, NPCs=true, Items=true,
        Boxes=true, Names=true, Health=true, Distance=true, Lines=false,
        ThroughWalls=false, Skeleton=false, Highlight=true, HeadMarker=false, TargetIndicator=true,
        TeamIdentification=false, ColorByTeam=false, ShowDead=false, DroppedItems=true, Loot=true,
        Weapons=true, Tools=true, Collectibles=true, Objectives=true, TestObjects=true }) do define("ESP", key, value) end
    define("ESP", "MaxDistance", 1500, 10, 5000)
    define("ESP", "MaxElements", 64, 1, 128)
    define("ESP", "RefreshRate", 20, 5, 60)
    for name, color in pairs({ PlayerColor="268BFF", NPCColor="67C9FF", ItemColor="F0C15C", TargetColor="FFFFFF" }) do
        define("ESP", name, color)
    end
    define("Flight", "Enabled", false)
    define("Flight", "Speed", 40, 1, 120)
    define("Flight", "VerticalSpeed", 30, 1, 100)
    define("Flight", "Acceleration", 8, 1, 25)
    define("Flight", "Boost", 1.5, 1, 2)
    define("Flight", "Key", "F")
    define("Speed", "Enabled", false)
    define("Speed", "WalkSpeed", 24, 1, 100)
    define("Speed", "SprintSpeed", 36, 1, 100)
    define("Speed", "Multiplier", 1, 0.25, 2)
    define("Speed", "Acceleration", 8, 1, 25)
    define("Speed", "SprintKey", "LeftShift")
    define("Player", "ServerGodmode", false)
    define("Settings", "MenuKey", "LeftControl")
    define("Settings", "Scale", 1, 0.65, 1.3)
    define("Settings", "Performance", "Balanced", nil, nil, { "Low", "Balanced", "High" })
    define("Settings", "Theme", "Blue", nil, nil, { "Blue", "Cyan" })
    define("Settings", "Adapter", "Auto", nil, nil, { "Auto", "GenericRobloxAdapter", "CustomGameAdapter" })
    local schemaSize = 0
    for _ in pairs(schema) do schemaSize += 1 end
    local presets = {
        Low = { ["ESP.MaxElements"]=24, ["ESP.RefreshRate"]=10, ["ESP.Skeleton"]=false, ["ESP.Lines"]=false, ["ESP.HeadMarker"]=false },
        Balanced = { ["ESP.MaxElements"]=64, ["ESP.RefreshRate"]=20, ["ESP.Skeleton"]=false, ["ESP.Lines"]=false, ["ESP.HeadMarker"]=false },
        High = { ["ESP.MaxElements"]=96, ["ESP.RefreshRate"]=30, ["ESP.Skeleton"]=true, ["ESP.Lines"]=false, ["ESP.HeadMarker"]=true },
    }

    local keyNames = {}
    local enumAvailable, enumItems = pcall(function() return Enum.KeyCode:GetEnumItems() end)
    if enumAvailable then
        for _, item in ipairs(enumItems) do
            if not item.Name:match("^Button") and not item.Name:match("^Thumbstick") and not item.Name:match("^DPad") then
                keyNames[item.Name] = true
            end
        end
    else
        -- CLI fallback covers the documented keyboard binds used by pure tests.
        for name in ("LeftShift RightShift LeftAlt RightAlt LeftControl RightControl Space Tab CapsLock Backspace Insert Delete Home End PageUp PageDown Up Down Left Right Zero One Two Three Four Five Six Seven Eight Nine"):gmatch("%S+") do
            keyNames[name] = true
        end
        for byte=65,90 do keyNames[string.char(byte)] = true end
        for index=1,12 do keyNames["F"..index] = true end
    end

    local function validate(path, value)
        local rule = schema[path]
        if not rule then return false, "Chave desconhecida: " .. tostring(path) end
        if type(value) ~= type(rule.Default) then return false, "Tipo inválido: " .. path end
        if type(value) == "number" then
            if value ~= value or math.abs(value) == math.huge then return false, "Número não finito: " .. path end
            if value < rule.Min or value > rule.Max then return false, "Fora dos limites: " .. path end
            if (path == "ESP.MaxElements" or path == "ESP.RefreshRate") and value % 1 ~= 0 then
                return false, "Use um número inteiro: " .. path
            end
        elseif type(value) == "string" then
            if path:match("^ESP%..*Color$") and (#value ~= 6 or not value:match("^[%x]+$")) then
                return false, "Use RGB hexadecimal com seis dígitos: " .. path
            end
            if #value == 0 or #value > 32 or not value:match("^[%w_]+$") then return false, "Texto inválido: " .. path end
            if rule.Choices and not table.find(rule.Choices, value) then return false, "Opção inválida: " .. path end
            if path:match("Key$") and (value == "Unknown" or value == "Escape" or value == "Return") then
                return false, "Atalho reservado: " .. path
            end
            if path:match("Key$") then
                local mouse = value == "MouseButton1" or value == "MouseButton2" or value == "MouseButton3"
                if not keyNames[value] and not (path == "Aim.Key" and mouse) then return false, "Tecla inválida: " .. path end
                if path ~= "Settings.MenuKey" and (value == "LeftControl" or value == "RightControl") then
                    return false, "CTRL está reservado ao menu"
                end
            end
            if path == "Settings.MenuKey" and value ~= "LeftControl" then return false, "O menu usa CTRL" end
        end
        return true
    end

    local function validateBinds(values)
        local seen = {}
        for _, path in ipairs({"Aim.Key", "Flight.Key", "Speed.SprintKey"}) do
            local value = values[path]
            if seen[value] then return false, "Conflito entre atalhos: " .. seen[value] .. " / " .. path end
            seen[value] = path
        end
        return true
    end

    function ConfigManager:_notify(path, value)
        for _, listener in pairs(self._listeners) do
            local called, err = pcall(listener, path, value)
            if not called then warn("VW config listener: " .. tostring(err)) end
        end
    end

    function ConfigManager.new()
        local self = setmetatable({ _values={}, _listeners={}, _nextId=0, _destroyed=false }, ConfigManager)
        for path, rule in pairs(schema) do self._values[path] = rule.Default end
        return self
    end

    function ConfigManager:Get(path) return self._values[path] end
    function ConfigManager:Schema() return schema end
    function ConfigManager:Snapshot() return table.clone(self._values) end
    function ConfigManager:Subscribe(callback)
        self._nextId += 1
        local id = self._nextId
        self._listeners[id] = callback
        return function() self._listeners[id] = nil end
    end

    function ConfigManager:Set(path, value)
        if self._destroyed then return false, "Configuração descarregada" end
        local ok, reason = validate(path, value)
        if not ok then return false, reason end
        if path:match("Key$") then
            local candidate = self:Snapshot(); candidate[path] = value
            local bindsOk, bindsReason = validateBinds(candidate)
            if not bindsOk then return false, bindsReason end
        end
        if self._values[path] == value then return true end
        self._values[path] = value
        self:_notify(path, value)
        return true
    end

    -- Validate the whole profile before changing any state.
    function ConfigManager:Import(values)
        if self._destroyed then return false, "Configuração descarregada" end
        if type(values) ~= "table" or getmetatable(values) ~= nil then return false, "Perfil deve ser um objeto JSON" end
        local count = 0
        local candidate = self:Snapshot()
        for path, value in pairs(values) do
            if type(path) ~= "string" then return false, "Chave inválida" end
            local ok, reason = validate(path, value)
            if not ok then return false, reason end
            count += 1
            if count > schemaSize then return false, "Perfil excedeu o limite" end
            candidate[path] = value
        end
        local bindsOk, bindsReason = validateBinds(candidate)
        if not bindsOk then return false, bindsReason end
        local oldValues = self._values
        self._values = candidate
        for path, value in pairs(values) do
            if oldValues[path] ~= value then self:_notify(path, value) end
        end
        return true
    end

    function ConfigManager:ApplyPreset(name)
        if type(name) ~= "string" or not presets[name] then return false, "Preset inválido" end
        local values = table.clone(presets[name])
        values["Settings.Performance"] = name
        return self:Import(values)
    end

    function ConfigManager:Reset()
        -- Disable effects before restoring parameter defaults.
        local defaults = {}
        for path, rule in pairs(schema) do
            defaults[path] = rule.Default
            if path:match("Enabled$") or path == "Player.ServerGodmode" then self:Set(path, rule.Default) end
        end
        return self:Import(defaults)
    end

    function ConfigManager:Destroy()
        self._destroyed = true
        table.clear(self._listeners)
    end
    return ConfigManager
end
