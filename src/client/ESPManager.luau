-- Native, authorized overlays. The controller owns scheduling; entries own their instances.
return function(_import)
    local ESPManager = {}
    ESPManager.__index = ESPManager

    local DEFAULTS = {
        Players = true, NPCs = true, Items = true, Boxes = true, Highlight = true,
        Skeleton = false, HeadMarker = false, TargetIndicator = true,
        Names = true, Health = true, Distance = true, Lines = false,
        TeamIdentification = false, ColorByTeam = false, ShowDead = false,
        DroppedItems = true, Loot = true, Weapons = true, Tools = true,
        Collectibles = true, Objectives = true, TestObjects = true,
        PlayerColor = "268BFF", NPCColor = "67C9FF", ItemColor = "F0C15C", TargetColor = "FFFFFF",
        ThroughWalls = false, MaxDistance = 1500, MaxElements = 64, RefreshRate = 20,
    }
    local ITEM_TYPES = { DroppedItems=true, Loot=true, Weapons=true, Tools=true,
        Collectibles=true, Objectives=true, TestObjects=true }
    local SIGNS = { -1, 1 }
    -- Standard anatomical links only; no guesses for custom rigs.
    local RIG_LINKS = {
        R6 = {
            {"Head", "Torso"}, {"Torso", "Left Arm"}, {"Torso", "Right Arm"},
            {"Torso", "Left Leg"}, {"Torso", "Right Leg"},
        },
        R15 = {
            {"Head", "UpperTorso"}, {"UpperTorso", "LowerTorso"},
            {"UpperTorso", "LeftUpperArm"}, {"LeftUpperArm", "LeftLowerArm"}, {"LeftLowerArm", "LeftHand"},
            {"UpperTorso", "RightUpperArm"}, {"RightUpperArm", "RightLowerArm"}, {"RightLowerArm", "RightHand"},
            {"LowerTorso", "LeftUpperLeg"}, {"LeftUpperLeg", "LeftLowerLeg"}, {"LeftLowerLeg", "LeftFoot"},
            {"LowerTorso", "RightUpperLeg"}, {"RightUpperLeg", "RightLowerLeg"}, {"RightLowerLeg", "RightFoot"},
        },
    }
    -- Disabled Highlights still occupy native slots; cap owned instances, not just enabled ones.
    local MAX_HIGHLIGHTS = 31

    local function finite(value)
        return type(value) == "number" and value == value and math.abs(value) < math.huge
    end

    local function number(value, default, minimum, maximum)
        return finite(value) and math.clamp(value, minimum, maximum) or default
    end

    local function parseColor(value, fallback)
        local hex = type(value) == "string" and value:gsub("^#", "") or ""
        if #hex ~= 6 or not hex:match("^%x+$") then hex = fallback end
        return Color3.fromRGB(tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16))
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

    local function validPart(entity, part)
        if not part or not part.Parent or not part:IsA("BasePart") then return false end
        return not entity.Model or part:IsDescendantOf(entity.Model)
    end

    local function standardRig(value)
        local text = tostring(value)
        if text == "R15" or text == "Enum.HumanoidRigType.R15" then return "R15" end
        if text == "R6" or text == "Enum.HumanoidRigType.R6" then return "R6" end
        return nil
    end

    local function point(camera, position)
        local projected = camera:WorldToViewportPoint(position)
        if not finite(projected.X) or not finite(projected.Y) or not finite(projected.Z) or projected.Z <= 0.05 then return nil end
        return projected
    end

    -- Clip endpoints before computing the position and rotation of a native Frame.
    local function clipLine(a, b, viewport)
        local dx, dy = b.X - a.X, b.Y - a.Y
        local lower, upper = 0, 1
        local function edge(p, q)
            if p == 0 then return q >= 0 end
            local ratio = q / p
            if p < 0 then
                if ratio > upper then return false end
                lower = math.max(lower, ratio)
            else
                if ratio < lower then return false end
                upper = math.min(upper, ratio)
            end
            return true
        end
        if not edge(-dx, a.X) or not edge(dx, viewport.X - a.X)
            or not edge(-dy, a.Y) or not edge(dy, viewport.Y - a.Y) then return nil end
        return a.X + lower * dx, a.Y + lower * dy, a.X + upper * dx, a.Y + upper * dy
    end

    local function drawLine(frame, a, b, viewport, color)
        local x1, y1, x2, y2 = clipLine(a, b, viewport)
        if not x1 then frame.Visible = false; return end
        local dx, dy = x2 - x1, y2 - y1
        local length = math.sqrt(dx * dx + dy * dy)
        frame.Visible = length >= 0.5
        frame.Position = UDim2.fromOffset((x1 + x2) * 0.5, (y1 + y2) * 0.5)
        frame.Size = UDim2.fromOffset(length, 1)
        frame.Rotation = math.deg(math.atan2(dy, dx))
        frame.BackgroundColor3 = color
    end

    function ESPManager.new(ctx)
        local self = setmetatable({
            _ctx = ctx, _initialized = false, _destroyed = false,
            _enabled = false, _entries = {}, _accumulator = 0, _cfg = {},
            _objectCount = 0, _highlightCount = 0, _unsupportedLogged = false,
        }, ESPManager)
        self._raycast = RaycastParams.new()
        self._raycast.FilterType = Enum.RaycastFilterType.Exclude
        self._raycast.IgnoreWater = true
        self:UpdateConfig()
        self._ctx.Diagnostics:Set("ESP.Status", "DISABLED")
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
        self._objectCount += 1
        self._ctx.Diagnostics:Set("ESP.VisualObjects", self._objectCount)
    end

    function ESPManager:_own(entry, instance)
        table.insert(entry.Owned, instance)
        self._objectCount += 1
        return instance
    end

    function ESPManager:_remove(key)
        local entry = self._entries[key]
        if not entry then return end
        for index = #entry.Owned, 1, -1 do entry.Owned[index]:Destroy() end
        self._objectCount -= #entry.Owned
        if entry.Highlight then self._highlightCount -= 1 end
        self._entries[key] = nil
    end

    function ESPManager:_clear()
        for key in pairs(self._entries) do self:_remove(key) end
    end

    function ESPManager:_hide(entry)
        entry.Frame.Visible = false
        entry.Tracer.Visible = false
        entry.HeadMarker.Visible = false
        entry.TargetIndicator.Visible = false
        if entry.Highlight then entry.Highlight.Enabled = false end
        for _, line in pairs(entry.Skeleton) do line.Visible = false end
    end

    function ESPManager:_metrics(rendered, tracked, started)
        local diagnostics = self._ctx.Diagnostics
        diagnostics:Set("ESP.Rendered", rendered)
        diagnostics:Set("ESP.Tracked", tracked)
        diagnostics:Set("ESP.VisualObjects", self._objectCount)
        if started then diagnostics:Set("ESP.UpdateMs", math.floor((os.clock() - started) * 100000) / 100) end
    end

    function ESPManager:Enable()
        if self._destroyed or self._enabled or not self._ctx.IsAuthorized() then return end
        self:Init()
        self._enabled = true
        self._root.Visible = true
        self._accumulator = math.huge
        self._ctx.Diagnostics:Set("ESP.Status", "ACTIVE")
        self._ctx.Diagnostics:Log("ESPManager", "enabled", "Native overlays enabled for authorized entities")
    end

    function ESPManager:Disable()
        local wasEnabled = self._enabled
        self._enabled = false
        self:_clear()
        if self._root then self._root:Destroy(); self._objectCount -= 1 end
        self._root = nil
        self._initialized = false
        self:_metrics(0, 0)
        self._ctx.Diagnostics:Set("ESP.Status", "DISABLED")
        self._ctx.Diagnostics:Set("ESP.UpdateMs", 0)
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
        self._colors = {
            Player = parseColor(config.PlayerColor, DEFAULTS.PlayerColor),
            NPC = parseColor(config.NPCColor, DEFAULTS.NPCColor),
            Item = parseColor(config.ItemColor, DEFAULTS.ItemColor),
            Target = parseColor(config.TargetColor, DEFAULTS.TargetColor),
        }
        self._cfg = config
        for key, value in pairs(config) do
            if previous[key] ~= value then self._accumulator = math.huge; break end
        end
        -- Reconfigure cached objects at the next refresh, without rebuilding their instances.
    end

    function ESPManager:_eligible(entity, camera)
        local category = entity.Category
        if category == "Player" then
            if not self._cfg.Players or entity.Player == self._ctx.Player then return nil end
        elseif category == "NPC" then
            if not self._cfg.NPCs then return nil end
        elseif category == "Item" then
            if not self._cfg.Items then return nil end
            local subtype = entity.Subcategory
            if ITEM_TYPES[subtype] and not self._cfg[subtype] then return nil end
        else return nil end
        local root = entity.Root
        if not entity.Instance or not entity.Instance.Parent or not validPart(entity, root) then return nil end
        if not root:IsDescendantOf(self._ctx.Services.Workspace) then return nil end
        if entity.Model and not entity.Model.Parent then return nil end
        if entity.Humanoid and (not finite(entity.Humanoid.Health) or (entity.Humanoid.Health <= 0 and not self._cfg.ShowDead)) then return nil end
        if not camera then return 0 end
        local distance = (root.Position - camera.CFrame.Position).Magnitude
        if not finite(distance) or distance > self._cfg.MaxDistance then return nil end
        return distance
    end

    function ESPManager:_bounds(entity, camera)
        local frame, size
        if entity.Model and entity.Model:IsA("Model") then
            local ok
            ok, frame, size = pcall(entity.Model.GetBoundingBox, entity.Model)
            if not ok then return nil end
        else
            frame, size = entity.Root.CFrame, entity.Root.Size
        end
        if not frame or not size or not finite(size.X) or not finite(size.Y) or not finite(size.Z) then return nil end
        local half = size * 0.5
        local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
        for _, x in ipairs(SIGNS) do
            for _, y in ipairs(SIGNS) do
                for _, z in ipairs(SIGNS) do
                    local projected = point(camera, frame * Vector3.new(half.X * x, half.Y * y, half.Z * z))
                    if not projected then return nil end
                    minX, minY = math.min(minX, projected.X), math.min(minY, projected.Y)
                    maxX, maxY = math.max(maxX, projected.X), math.max(maxY, projected.Y)
                end
            end
        end
        local viewport = camera.ViewportSize
        if maxX < 0 or maxY < 0 or minX > viewport.X or minY > viewport.Y then return nil end
        if maxX - minX > viewport.X * 4 or maxY - minY > viewport.Y * 4 then return nil end
        minX, minY = math.clamp(minX, 0, viewport.X), math.clamp(minY, 0, viewport.Y)
        maxX, maxY = math.clamp(maxX, 0, viewport.X), math.clamp(maxY, 0, viewport.Y)
        local width, height = maxX - minX, maxY - minY
        if width < 1 or height < 1 then return nil end
        return minX, minY, width, height
    end

    function ESPManager:_visible(entity, camera)
        if self._cfg.ThroughWalls then return true end
        local origin = camera.CFrame.Position
        local hit = self._ctx.Services.Workspace:Raycast(origin, entity.Root.Position - origin, self._raycast)
        return hit == nil or hit.Instance == entity.Root or hit.Instance == entity.Instance
            or (entity.Model ~= nil and hit.Instance:IsDescendantOf(entity.Model))
    end

    function ESPManager:_team(entity)
        local adapters = self._ctx.Adapters
        if adapters and type(adapters.TeamIdentity) == "function" then
            local ok, key, color, teamLabel = pcall(adapters.TeamIdentity, adapters, entity.Player, entity.Model or entity.Instance)
            if ok and key ~= nil then return color, teamLabel or tostring(key) end
        end
        local player = entity.Player
        if player and not player.Neutral then
            local color = player.TeamColor and player.TeamColor.Color or nil
            local teamLabel = player.Team and player.Team.Name or entity.TeamLabel
            return color or entity.TeamColor, teamLabel
        end
        if not player then return entity.TeamColor, entity.TeamLabel end
        return nil, nil
    end

    function ESPManager:_line(entry, name)
        local line = self:_own(entry, Instance.new("Frame"))
        line.Name = name
        line.AnchorPoint = Vector2.new(0.5, 0.5)
        line.BorderSizePixel = 0
        line.BackgroundTransparency = 0.15
        line.ZIndex = 2
        line.Visible = false
        line.Parent = self._root
        return line
    end

    function ESPManager:_create(entity)
        local entry = { Owned = {}, Skeleton = {}, Parts = {} }
        local frame = self:_own(entry, Instance.new("Frame"))
        frame.Name = "Entity"
        frame.BackgroundTransparency = 1
        frame.BorderSizePixel = 0
        frame.Parent = self._root
        local box = self:_own(entry, Instance.new("Frame"))
        box.Name = "Bounds"
        box.Size = UDim2.fromScale(1, 1)
        box.BackgroundTransparency = 1
        box.BorderSizePixel = 0
        box.ZIndex = 3
        box.Parent = frame
        local stroke = self:_own(entry, Instance.new("UIStroke"))
        stroke.Thickness = 1
        stroke.Parent = box
        local nameLabel = self:_own(entry, label(frame))
        nameLabel.Name = "Name"
        nameLabel.AnchorPoint = Vector2.new(0.5, 1)
        nameLabel.Position = UDim2.new(0.5, 0, 0, -3)
        local details = self:_own(entry, label(frame))
        details.Name = "Details"
        details.AnchorPoint = Vector2.new(0.5, 0)
        details.Position = UDim2.new(0.5, 0, 1, 3)
        local health = self:_own(entry, Instance.new("Frame"))
        health.Name = "Health"
        health.Position = UDim2.fromOffset(-6, 0)
        health.Size = UDim2.new(0, 3, 1, 0)
        health.BackgroundColor3 = Color3.fromRGB(15, 24, 38)
        health.BorderSizePixel = 0
        health.ZIndex = 3
        health.Parent = frame
        local healthFill = self:_own(entry, Instance.new("Frame"))
        healthFill.AnchorPoint = Vector2.new(0, 1)
        healthFill.Position = UDim2.fromScale(0, 1)
        healthFill.BorderSizePixel = 0
        healthFill.ZIndex = 4
        healthFill.Parent = health
        entry.Tracer = self:_line(entry, "Tracer")
        local headMarker = self:_own(entry, label(self._root))
        headMarker.Name = "HeadMarker"
        headMarker.AnchorPoint = Vector2.new(0.5, 0.5)
        headMarker.Size = UDim2.fromOffset(18, 18)
        headMarker.Text = "○"
        headMarker.TextSize = 20
        headMarker.Visible = false
        local targetIndicator = self:_own(entry, label(frame))
        targetIndicator.Name = "TargetIndicator"
        targetIndicator.AnchorPoint = Vector2.new(0.5, 1)
        targetIndicator.Position = UDim2.new(0.5, 0, 0, -22)
        targetIndicator.Size = UDim2.fromOffset(160, 18)
        targetIndicator.Text = "▼ TARGET"
        targetIndicator.Visible = false
        entry.Frame, entry.Box, entry.Stroke = frame, box, stroke
        entry.Name, entry.Details = nameLabel, details
        entry.Health, entry.HealthFill = health, healthFill
        entry.HeadMarker, entry.TargetIndicator = headMarker, targetIndicator
        self._entries[entity.Instance] = entry
        return entry
    end

    function ESPManager:_highlight(entry, entity, color)
        if self._cfg.Highlight and not entry.Highlight and self._highlightCount < MAX_HIGHLIGHTS then
            local highlight = self:_own(entry, Instance.new("Highlight"))
            highlight.Name = "VWLabHighlight"
            highlight.FillTransparency = 0.9
            highlight.OutlineTransparency = 0.2
            highlight.Parent = entity.Model or entity.Instance
            entry.Highlight = highlight
            self._highlightCount += 1
        end
        local highlight = entry.Highlight
        if not highlight then return end
        highlight.Adornee = entity.Model or entity.Root
        highlight.Enabled = self._cfg.Highlight
        highlight.FillColor = color
        highlight.OutlineColor = color
        highlight.DepthMode = self._cfg.ThroughWalls and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
    end

    function ESPManager:_part(entry, entity, name)
        local part = entry.Parts[name]
        if not validPart(entity, part) then
            part = entity.Model and entity.Model:FindFirstChild(name)
            entry.Parts[name] = part
        end
        return validPart(entity, part) and part or nil
    end

    function ESPManager:_skeleton(entry, entity, camera, color)
        for _, line in pairs(entry.Skeleton) do line.Visible = false end
        if not self._cfg.Skeleton or entity.Category == "Item" then return end
        local rigName = standardRig(entity.Rig) or standardRig(entity.Humanoid and entity.Humanoid.RigType)
        local links = RIG_LINKS[rigName]
        if not links then
            if not self._unsupportedLogged then
                self._unsupportedLogged = true
                self._ctx.Diagnostics:Log("ESPManager", "unsupported-rig", "Skeleton skipped: only standard R6/R15 part layouts are supported")
            end
            return
        end
        for index, link in ipairs(links) do
            local first, second = self:_part(entry, entity, link[1]), self:_part(entry, entity, link[2])
            if first and second then
                local a, b = point(camera, first.Position), point(camera, second.Position)
                if a and b then
                    if not entry.Skeleton[index] then entry.Skeleton[index] = self:_line(entry, "Skeleton" .. index) end
                    drawLine(entry.Skeleton[index], a, b, camera.ViewportSize, color)
                end
            end
        end
    end

    function ESPManager:_render(entity, distance, camera, x, y, width, height)
        local entry = self._entries[entity.Instance] or self:_create(entity)
        local config = self._cfg
        local selected = self._ctx.SelectedTarget == entity.Instance
        local teamColor, teamLabel
        if config.ColorByTeam or config.TeamIdentification then teamColor, teamLabel = self:_team(entity) end
        local color = (config.ColorByTeam and teamColor) or self._colors[entity.Category]
        entry.Frame.Position = UDim2.fromOffset(x, y)
        entry.Frame.Size = UDim2.fromOffset(width, height)
        entry.Frame.Visible = true
        entry.Box.Visible = config.Boxes
        entry.Stroke.Color = color
        entry.Name.Visible = config.Names
        entry.Name.Text = entity.Name or entity.Instance.Name or "Entity"
        entry.Name.TextColor3 = color
        entry.Name.Size = UDim2.fromOffset(math.max(140, width), 18)
        local text = {}
        if entity.Category == "Item" then
            local subcategory = ITEM_TYPES[entity.Subcategory] and entity.Subcategory or "Unknown category"
            local className = entity.Instance.ClassName
            local itemType = type(className) == "string" and className ~= "" and className or "Unknown type"
            table.insert(text, "Item: " .. subcategory .. " (" .. itemType .. ")")
        end
        local humanoid = entity.Humanoid
        local healthValid = humanoid and finite(humanoid.Health) and finite(humanoid.MaxHealth) and humanoid.MaxHealth > 0
        if config.Health and healthValid then table.insert(text, string.format("%d HP", math.max(0, math.floor(humanoid.Health + 0.5)))) end
        if config.Distance then table.insert(text, string.format("%d studs", math.floor(distance + 0.5))) end
        if config.TeamIdentification and teamLabel then table.insert(text, tostring(teamLabel)) end
        entry.Details.Text = table.concat(text, "  ·  ")
        entry.Details.TextColor3 = color
        entry.Details.Size = UDim2.fromOffset(math.max(entity.Category == "Item" and 280 or 160, width), 18)
        entry.Details.Visible = #text > 0
        entry.Health.Visible = config.Health and healthValid or false
        if healthValid then
            local ratio = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
            entry.HealthFill.Size = UDim2.fromScale(1, ratio)
            entry.HealthFill.BackgroundColor3 = ratio > 0.35 and Color3.fromRGB(86, 224, 159) or Color3.fromRGB(255, 147, 91)
        end
        self:_highlight(entry, entity, color)
        entry.Tracer.Visible = config.Lines
        if config.Lines then
            drawLine(entry.Tracer, Vector2.new(camera.ViewportSize.X * 0.5, camera.ViewportSize.Y),
                Vector2.new(x + width * 0.5, y + height), camera.ViewportSize, color)
        end
        entry.HeadMarker.Visible = false
        local head = entity.Head
        if config.HeadMarker and not validPart(entity, head) then head = self:_part(entry, entity, "Head") end
        if config.HeadMarker and validPart(entity, head) then
            local projected = point(camera, head.Position)
            if projected and projected.X >= 0 and projected.X <= camera.ViewportSize.X
                and projected.Y >= 0 and projected.Y <= camera.ViewportSize.Y then
                entry.HeadMarker.Visible = true
                entry.HeadMarker.Position = UDim2.fromOffset(projected.X, projected.Y)
                entry.HeadMarker.TextColor3 = color
            end
        end
        entry.TargetIndicator.Visible = config.TargetIndicator and selected
        entry.TargetIndicator.TextColor3 = self._colors.Target
        self:_skeleton(entry, entity, camera, color)
    end

    function ESPManager:Step(dt)
        if self._destroyed or not self._enabled then return end
        if not self._ctx.IsAuthorized() then self:Disable(); return end
        if not finite(dt) or dt <= 0 then return end
        self._accumulator += dt
        local started = os.clock()
        local camera = self._ctx.Services.Workspace.CurrentCamera
        local cameraValid = camera and camera.CFrame and camera.ViewportSize
            and finite(camera.ViewportSize.X) and finite(camera.ViewportSize.Y)
            and camera.ViewportSize.X > 0 and camera.ViewportSize.Y > 0
        local entities = self._ctx.Entities:List()
        local allowed, candidates = {}, {}
        for _, entity in ipairs(entities) do
            local distance = self:_eligible(entity, cameraValid and camera or nil)
            if distance then
                allowed[entity.Instance] = true
                table.insert(candidates, { Entity = entity, Distance = distance })
            end
        end
        -- Registry permission, removal and death pruning run between throttled visual refreshes.
        for key in pairs(self._entries) do if not allowed[key] then self:_remove(key) end end
        if not cameraValid then
            for _, entry in pairs(self._entries) do self:_hide(entry) end
            self._accumulator = math.huge
            self._ctx.Diagnostics:Set("ESP.Status", "CAMERA NOT FOUND")
            self:_metrics(0, #candidates, started)
            return
        end
        self._ctx.Diagnostics:Set("ESP.Status", "ACTIVE")
        if self._accumulator < 1 / self._cfg.RefreshRate then
            local rendered = 0
            for _, entry in pairs(self._entries) do if entry.Frame.Visible then rendered += 1 end end
            self:_metrics(rendered, #candidates, started)
            return
        end
        self._accumulator = 0
        local filter = { camera }
        if self._ctx.Player.Character then table.insert(filter, self._ctx.Player.Character) end
        self._raycast.FilterDescendantsInstances = filter
        table.sort(candidates, function(a, b) return a.Distance < b.Distance end)
        local retained, visible = {}, {}
        -- The registry is bounded at 512. Only on-screen entities consume overlay/raycast slots.
        for _, candidate in ipairs(candidates) do
            if #visible >= self._cfg.MaxElements then break end
            local entity = candidate.Entity
            local x, y, width, height = self:_bounds(entity, camera)
            if x and self:_visible(entity, camera) then
                candidate.Bounds = { x, y, width, height }
                table.insert(visible, candidate)
                retained[entity.Instance] = true
            end
        end
        for key in pairs(self._entries) do if not retained[key] then self:_remove(key) end end
        for _, candidate in ipairs(visible) do
            self:_render(candidate.Entity, candidate.Distance, camera, table.unpack(candidate.Bounds))
        end
        self:_metrics(#visible, #candidates, started)
    end

    function ESPManager:Destroy()
        if self._destroyed then return end
        self:Disable()
        self._destroyed = true
        self._ctx.Diagnostics:Set("ESP.Status", "DESTROYED")
    end

    return ESPManager
end
