-- Native overlays only. Highlight follows Boxes; labels and tracers use ScreenGui.
-- Model bounds are projected at a configurable rate, never by a private frame loop.
return function(_import)
    local ESPManager = {}
    ESPManager.__index = ESPManager

    local DEFAULTS = {
        Players = true, NPCs = true, Items = true, Boxes = true,
        Names = true, Health = true, Distance = true, Lines = false,
        ThroughWalls = false, MaxDistance = 1500, MaxElements = 64, RefreshRate = 20,
    }
    local SIGNS = { -1, 1 }

    local function finite(value)
        return type(value) == "number" and value == value and math.abs(value) < math.huge
    end

    local function number(value, default, minimum, maximum)
        return finite(value) and math.clamp(value, minimum, maximum) or default
    end

    local function colorFor(category)
        if category == "Item" then return Color3.fromRGB(240, 193, 92) end
        if category == "NPC" then return Color3.fromRGB(134, 213, 255) end
        return Color3.fromRGB(57, 169, 255)
    end

    local function label(parent)
        local result = Instance.new("TextLabel")
        result.BackgroundTransparency = 1
        result.BorderSizePixel = 0
        result.Font = Enum.Font.Gotham
        result.TextSize = 12
        result.TextColor3 = Color3.fromRGB(233, 244, 255)
        result.TextStrokeTransparency = 0.35
        result.RichText = false
        result.ZIndex = 5
        result.Parent = parent
        return result
    end

    function ESPManager.new(ctx)
        local self = setmetatable({
            _ctx = ctx, _initialized = false, _destroyed = false,
            _enabled = false, _entries = {}, _accumulator = 0,
            _cfg = {},
        }, ESPManager)
        self._raycast = RaycastParams.new()
        self._raycast.FilterType = Enum.RaycastFilterType.Exclude
        self._raycast.IgnoreWater = true
        self:UpdateConfig()
        return self
    end

    function ESPManager:Init()
        if self._initialized or self._destroyed then return end
        self._initialized = true
        local root = Instance.new("Frame")
        root.Name = "VWEntityOverlays"
        root.Size = UDim2.fromScale(1, 1)
        root.BackgroundTransparency = 1
        root.BorderSizePixel = 0
        root.ClipsDescendants = true
        root.Active = false
        root.Visible = false
        root.Parent = self._ctx.Gui
        self._root = root
    end

    function ESPManager:_remove(key)
        local entry = self._entries[key]
        if not entry then return end
        entry.Frame:Destroy()
        entry.Tracer:Destroy()
        entry.Highlight:Destroy()
        self._entries[key] = nil
    end

    function ESPManager:_clear()
        for key in pairs(self._entries) do self:_remove(key) end
    end

    function ESPManager:Enable()
        if self._destroyed or self._enabled or not self._ctx.IsAuthorized() then return end
        self:Init()
        self._enabled = true
        self._root.Visible = true
        self._accumulator = math.huge
        self._ctx.Diagnostics:Log("ESPManager", "enabled", "Native overlays enabled for authorized entities")
    end

    function ESPManager:Disable()
        local wasEnabled = self._enabled
        self._enabled = false
        self:_clear()
        if self._root then self._root.Visible = false end
        self._ctx.Diagnostics:Set("ESP.Rendered", 0)
        self._ctx.Diagnostics:Set("ESP.Tracked", 0)
        if wasEnabled then self._ctx.Diagnostics:Log("ESPManager", "disabled", "All owned overlays destroyed") end
    end

    function ESPManager:UpdateConfig()
        local previous = self._cfg or {}
        local config = {}
        for key, default in pairs(DEFAULTS) do
            local value = self._ctx.Config:Get("ESP." .. key)
            config[key] = value == nil and default or value
            if type(default) == "boolean" and type(config[key]) ~= "boolean" then config[key] = default end
        end
        config.MaxDistance = number(config.MaxDistance, 1500, 1, 100000)
        config.MaxElements = math.floor(number(config.MaxElements, 64, 0, 255))
        config.RefreshRate = number(config.RefreshRate, 20, 1, 60)
        self._cfg = config
        local changed = false
        for key, value in pairs(config) do
            if previous[key] ~= value then changed = true; break end
        end
        if changed then
            self._accumulator = math.huge
            -- Category/visibility changes remove old overlays before the next update.
            self:_clear()
        end
    end

    function ESPManager:_eligible(entity, camera)
        local category = entity.Category
        if category == "Player" then
            if not self._cfg.Players or entity.Player == self._ctx.Player then return nil end
        elseif category == "NPC" then
            if not self._cfg.NPCs then return nil end
        elseif category == "Item" then
            if not self._cfg.Items then return nil end
        else return nil end
        local root = entity.Root
        if not entity.Instance or not entity.Instance.Parent or not root or not root:IsA("BasePart") then return nil end
        if not root:IsDescendantOf(self._ctx.Services.Workspace) then return nil end
        if entity.Model and (not entity.Model.Parent or not root:IsDescendantOf(entity.Model)) then return nil end
        if entity.Humanoid and entity.Humanoid.Health <= 0 then return nil end
        local distance = (root.Position - camera.CFrame.Position).Magnitude
        if not finite(distance) or distance > self._cfg.MaxDistance then return nil end
        return distance
    end

    function ESPManager:_bounds(entity, camera)
        local frame, size
        if entity.Model and entity.Model:IsA("Model") then
            frame, size = entity.Model:GetBoundingBox()
        else
            frame, size = entity.Root.CFrame, entity.Root.Size
        end
        local half = size * 0.5
        local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
        for _, x in ipairs(SIGNS) do
            for _, y in ipairs(SIGNS) do
                for _, z in ipairs(SIGNS) do
                    local projected = camera:WorldToViewportPoint(frame * Vector3.new(half.X * x, half.Y * y, half.Z * z))
                    -- Hiding near-plane intersections prevents inverted, enormous boxes.
                    if not finite(projected.X) or not finite(projected.Y) or not finite(projected.Z) or projected.Z <= 0.05 then return nil end
                    minX, minY = math.min(minX, projected.X), math.min(minY, projected.Y)
                    maxX, maxY = math.max(maxX, projected.X), math.max(maxY, projected.Y)
                end
            end
        end
        local viewport = camera.ViewportSize
        if maxX < 0 or maxY < 0 or minX > viewport.X or minY > viewport.Y then return nil end
        local width, height = maxX - minX, maxY - minY
        if width < 1 or height < 1 or width > viewport.X * 4 or height > viewport.Y * 4 then return nil end
        return minX, minY, width, height
    end

    function ESPManager:_visible(entity, camera)
        if self._cfg.ThroughWalls then return true end
        local origin = camera.CFrame.Position
        local hit = self._ctx.Services.Workspace:Raycast(origin, entity.Root.Position - origin, self._raycast)
        return hit == nil or hit.Instance == entity.Root or hit.Instance == entity.Instance
            or (entity.Model ~= nil and hit.Instance:IsDescendantOf(entity.Model))
    end

    function ESPManager:_create(entity)
        local frame = Instance.new("Frame")
        frame.Name = "Entity"
        frame.BackgroundTransparency = 1
        frame.BorderSizePixel = 0
        frame.Parent = self._root
        local box = Instance.new("Frame")
        box.Name = "Bounds"
        box.Size = UDim2.fromScale(1, 1)
        box.BackgroundTransparency = 1
        box.BorderSizePixel = 0
        box.ZIndex = 3
        box.Parent = frame
        local stroke = Instance.new("UIStroke")
        stroke.Thickness = 1
        stroke.Parent = box
        local nameLabel = label(frame)
        nameLabel.Name = "Name"
        nameLabel.AnchorPoint = Vector2.new(0.5, 1)
        nameLabel.Position = UDim2.new(0.5, 0, 0, -3)
        local details = label(frame)
        details.Name = "Details"
        details.AnchorPoint = Vector2.new(0.5, 0)
        details.Position = UDim2.new(0.5, 0, 1, 3)
        local health = Instance.new("Frame")
        health.Name = "Health"
        health.Position = UDim2.fromOffset(-6, 0)
        health.Size = UDim2.new(0, 3, 1, 0)
        health.BackgroundColor3 = Color3.fromRGB(15, 24, 38)
        health.BorderSizePixel = 0
        health.ZIndex = 3
        health.Parent = frame
        local healthFill = Instance.new("Frame")
        healthFill.AnchorPoint = Vector2.new(0, 1)
        healthFill.Position = UDim2.fromScale(0, 1)
        healthFill.BorderSizePixel = 0
        healthFill.ZIndex = 4
        healthFill.Parent = health
        local tracer = Instance.new("Frame")
        tracer.Name = "Tracer"
        tracer.AnchorPoint = Vector2.new(0.5, 0.5)
        tracer.BorderSizePixel = 0
        tracer.BackgroundTransparency = 0.25
        tracer.ZIndex = 2
        tracer.Parent = self._root
        local highlight = Instance.new("Highlight")
        highlight.Name = "VWLabHighlight"
        highlight.Adornee = entity.Model or entity.Instance
        highlight.FillTransparency = 0.9
        highlight.OutlineTransparency = 0.2
        highlight.Enabled = false
        highlight.Parent = entity.Model or entity.Instance
        local entry = { Frame = frame, Box = box, Stroke = stroke, Name = nameLabel,
            Details = details, Health = health, HealthFill = healthFill, Tracer = tracer, Highlight = highlight }
        self._entries[entity.Instance] = entry
        return entry
    end

    function ESPManager:_render(entity, distance, camera, x, y, width, height)
        local entry = self._entries[entity.Instance] or self:_create(entity)
        local color = colorFor(entity.Category)
        local config = self._cfg
        entry.Frame.Position = UDim2.fromOffset(x, y)
        entry.Frame.Size = UDim2.fromOffset(width, height)
        entry.Frame.Visible = true
        entry.Box.Visible = config.Boxes
        entry.Stroke.Color = color
        entry.Name.Visible = config.Names
        entry.Name.Text = entity.Name or entity.Instance.Name or "Entity"
        entry.Name.Size = UDim2.fromOffset(math.max(140, width), 18)
        local text = {}
        local humanoid = entity.Humanoid
        local healthValid = humanoid and finite(humanoid.Health) and finite(humanoid.MaxHealth) and humanoid.MaxHealth > 0
        if config.Health and healthValid then table.insert(text, string.format("%d HP", math.max(0, math.floor(humanoid.Health + 0.5)))) end
        if config.Distance then table.insert(text, string.format("%d studs", math.floor(distance + 0.5))) end
        entry.Details.Text = table.concat(text, "  ·  ")
        entry.Details.Size = UDim2.fromOffset(math.max(160, width), 18)
        entry.Details.Visible = #text > 0
        entry.Health.Visible = config.Health and healthValid or false
        if healthValid then
            local ratio = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
            entry.HealthFill.Size = UDim2.fromScale(1, ratio)
            entry.HealthFill.BackgroundColor3 = ratio > 0.35 and Color3.fromRGB(86, 224, 159) or Color3.fromRGB(255, 147, 91)
        end
        entry.Highlight.Adornee = entity.Model or entity.Instance
        entry.Highlight.Enabled = config.Boxes
        entry.Highlight.FillColor = color
        entry.Highlight.OutlineColor = color
        entry.Highlight.DepthMode = config.ThroughWalls and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
        entry.Tracer.Visible = config.Lines
        if config.Lines then
            local origin = Vector2.new(camera.ViewportSize.X * 0.5, camera.ViewportSize.Y)
            local target = Vector2.new(x + width * 0.5, y + height)
            local delta = target - origin
            local midpoint = origin + delta * 0.5
            entry.Tracer.Position = UDim2.fromOffset(midpoint.X, midpoint.Y)
            entry.Tracer.Size = UDim2.fromOffset(delta.Magnitude, 1)
            entry.Tracer.Rotation = math.deg(math.atan2(delta.Y, delta.X))
            entry.Tracer.BackgroundColor3 = color
        end
    end

    function ESPManager:Step(dt)
        if self._destroyed or not self._enabled then return end
        if not self._ctx.IsAuthorized() then self:Disable(); return end
        if not finite(dt) or dt <= 0 then return end
        self._accumulator += dt
        local refresh = self._accumulator >= 1 / self._cfg.RefreshRate
        if not refresh and next(self._entries) == nil then return end
        local started = os.clock()
        local camera = self._ctx.Services.Workspace.CurrentCamera
        if not camera or camera.ViewportSize.X <= 0 or camera.ViewportSize.Y <= 0 then
            self:_clear()
            self._ctx.Diagnostics:Set("ESP.Rendered", 0)
            return
        end
        local entities = self._ctx.Entities:List()
        if not refresh then
            -- Authorization/death/removal cleanup is immediate, independently of render rate.
            local allowed = {}
            for _, entity in ipairs(entities) do
                if self._entries[entity.Instance] and self:_eligible(entity, camera) then allowed[entity.Instance] = true end
            end
            local remaining = 0
            for key in pairs(self._entries) do
                if allowed[key] then remaining += 1 else self:_remove(key) end
            end
            self._ctx.Diagnostics:Set("ESP.Rendered", remaining)
            return
        end
        self._accumulator = 0
        local filter = { camera }
        if self._ctx.Player.Character then table.insert(filter, self._ctx.Player.Character) end
        self._raycast.FilterDescendantsInstances = filter
        local candidates = {}
        for _, entity in ipairs(entities) do
            local distance = self:_eligible(entity, camera)
            if distance then table.insert(candidates, { Entity = entity, Distance = distance }) end
        end
        table.sort(candidates, function(a, b) return a.Distance < b.Distance end)
        local retained, rendered = {}, 0
        -- Bound projection/raycast work as well as the number of allocated overlays.
        for index = 1, math.min(#candidates, self._cfg.MaxElements) do
            local candidate = candidates[index]
            local entity = candidate.Entity
            local x, y, width, height = self:_bounds(entity, camera)
            if x and self:_visible(entity, camera) then
                self:_render(entity, candidate.Distance, camera, x, y, width, height)
                retained[entity.Instance] = true
                rendered += 1
            end
        end
        for key in pairs(self._entries) do
            if not retained[key] then self:_remove(key) end
        end
        self._ctx.Diagnostics:Set("ESP.Rendered", rendered)
        self._ctx.Diagnostics:Set("ESP.Tracked", #candidates)
        self._ctx.Diagnostics:Set("ESP.UpdateMs", math.floor((os.clock() - started) * 100000) / 100)
    end

    function ESPManager:Destroy()
        if self._destroyed then return end
        self:Disable()
        self._destroyed = true
        if self._root then self._root:Destroy() end
        self._root = nil
    end

    return ESPManager
end
