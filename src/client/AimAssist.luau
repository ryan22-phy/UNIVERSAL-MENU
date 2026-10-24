-- Native, camera-only assistance for targets already authorized by EntityRegistry.
-- The controller owns the render loop and calls Step after the camera update.
return function(_import)
    local AimAssist = {}
    AimAssist.__index = AimAssist

    local DEFAULTS = {
        FOV = 120, Smoothness = 12, MaxDistance = 1000,
        VisibilityCheck = true, TeamCheck = true, HeadPriority = true,
        Fallback = true, FallbackPart = "HumanoidRootPart", TargetLock = true, SwitchDelay = 0.2,
        Mode = "Hold", Key = "MouseButton2", Priority = "Angle",
        Prediction = 0, ShowFOV = true,
    }
    local MOUSE_BINDINGS = {
        MouseButton1 = Enum.UserInputType.MouseButton1,
        MouseButton2 = Enum.UserInputType.MouseButton2,
        MouseButton3 = Enum.UserInputType.MouseButton3,
    }

    local function finite(value)
        return type(value) == "number" and value == value and math.abs(value) < math.huge
    end

    local function number(value, default, minimum, maximum)
        return finite(value) and math.clamp(value, minimum, maximum) or default
    end

    local function vectorFinite(value)
        return finite(value.X) and finite(value.Y) and finite(value.Z)
    end

    local function inputMatches(input, name, key)
        local mouseType = MOUSE_BINDINGS[name]
        if mouseType then return input.UserInputType == mouseType end
        return key ~= nil and input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == key
    end

    function AimAssist.new(ctx)
        local self = setmetatable({
            _ctx = ctx, _initialized = false, _destroyed = false, _enabled = false,
            _held = false, _toggled = false, _down = false, _connections = {},
            _elapsed = 0, _nextSwitchAt = 0, _lastReport = -1,
            _targetKey = nil, _cfg = {}, _trackingLosses = 0,
            _activationAt = nil, _acquisitionMs = nil, _angularError = nil,
            _samples = {}, _sampleIndex = 0, _sampleSum = 0, _sampleSquares = 0,
        }, AimAssist)
        self._raycast = RaycastParams.new()
        self._raycast.FilterType = Enum.RaycastFilterType.Exclude
        self._raycast.IgnoreWater = true
        self:UpdateConfig()
        return self
    end

    function AimAssist:_clearTarget(delaySwitch)
        self._targetKey = nil
        self._targetName = nil
        self._targetDistance = nil
        self._angularError = nil
        self._targetPart = nil
        self._ctx.SelectedTarget, self._ctx.SelectedTargetPart = nil, nil
        table.clear(self._samples)
        self._sampleIndex, self._sampleSum, self._sampleSquares = 0, 0, 0
        if delaySwitch then
            self._nextSwitchAt = self._elapsed + self._cfg.SwitchDelay
        else
            self._nextSwitchAt = 0
        end
        if self._indicator then self._indicator.Visible = false end
    end

    function AimAssist:_clearActivation()
        self._held, self._toggled, self._down = false, false, false
        self._activationAt, self._acquisitionMs = nil, nil
        self:_clearTarget(false)
    end

    function AimAssist:Init()
        if self._initialized or self._destroyed then return end
        self._initialized = true
        local root = Instance.new("Frame")
        root.Name = "VWAimOverlay"
        root.Size = UDim2.fromScale(1, 1)
        root.BackgroundTransparency = 1
        root.BorderSizePixel = 0
        root.Active = false
        root.Visible = false
        root.Parent = self._ctx.Gui
        self._root = root

        local circle = Instance.new("Frame")
        circle.Name = "FOV"
        circle.AnchorPoint = Vector2.new(0.5, 0.5)
        circle.BackgroundTransparency = 1
        circle.BorderSizePixel = 0
        circle.ZIndex = 2
        circle.Parent = root
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = circle
        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(57, 169, 255)
        stroke.Thickness = 1
        stroke.Transparency = 0.3
        stroke.Parent = circle
        self._circle = circle

        local indicator = Instance.new("Frame")
        indicator.Name = "Target"
        indicator.AnchorPoint = Vector2.new(0.5, 0.5)
        indicator.Size = UDim2.fromOffset(10, 10)
        indicator.BackgroundTransparency = 1
        indicator.BorderSizePixel = 0
        indicator.Visible = false
        indicator.ZIndex = 3
        indicator.Parent = root
        local targetCorner = Instance.new("UICorner")
        targetCorner.CornerRadius = UDim.new(1, 0)
        targetCorner.Parent = indicator
        local targetStroke = Instance.new("UIStroke")
        targetStroke.Color = Color3.fromRGB(134, 213, 255)
        targetStroke.Thickness = 2
        targetStroke.Parent = indicator
        self._indicator = indicator

        local inputService = self._ctx.Services.UserInputService
        table.insert(self._connections, inputService.InputBegan:Connect(function(input, processed)
            if processed or self._ctx.InputCaptured or not self._enabled or not self._ctx.IsAuthorized() then return end
            if inputService:GetFocusedTextBox() or not inputMatches(input, self._cfg.Key, self._bindingKey) then return end
            if self._down then return end
            self._down = true
            if self._cfg.Mode == "Toggle" then
                self._toggled = not self._toggled
                if self._toggled then
                    self._activationAt, self._acquisitionMs = os.clock(), nil
                else
                    self._activationAt, self._acquisitionMs = nil, nil
                    self:_clearTarget(false)
                end
            else
                self._held = true
                self._activationAt, self._acquisitionMs = os.clock(), nil
            end
        end))
        table.insert(self._connections, inputService.InputEnded:Connect(function(input)
            if not inputMatches(input, self._cfg.Key, self._bindingKey) then return end
            self._down, self._held = false, false
            if self._cfg.Mode == "Hold" then
                self._activationAt, self._acquisitionMs = nil, nil
                self:_clearTarget(false)
            end
        end))
        table.insert(self._connections, inputService.WindowFocusReleased:Connect(function()
            self:_clearActivation()
        end))
    end

    function AimAssist:Enable()
        if self._destroyed or self._enabled or not self._ctx.IsAuthorized() then return end
        self:Init()
        self._enabled = true
        self:_clearActivation()
        self._root.Visible = true
        self._ctx.Diagnostics:Log("AimAssist", "enabled", "Camera assistance enabled for authorized lab entities")
    end

    function AimAssist:Disable()
        local wasEnabled = self._enabled
        self._enabled = false
        self:_clearActivation()
        if self._root then self._root.Visible = false end
        self._ctx.Diagnostics:Set("Aim.Active", false)
        self._ctx.Diagnostics:Set("Aim.Target", "—")
        self._ctx.Diagnostics:Set("Aim.Candidates", 0)
        self._ctx.Diagnostics:Set("Aim.AngularErrorDeg", "—")
        self._ctx.Diagnostics:Set("Aim.AcquisitionMs", "—")
        self._ctx.Diagnostics:Set("Aim.TrackingLosses", self._trackingLosses)
        self._ctx.Diagnostics:Set("Aim.TargetPart", "—")
        self._ctx.Diagnostics:Set("Aim.StabilityDeg", "—")
        self._ctx.Diagnostics:Set("Aim.StabilitySamples", 0)
        if wasEnabled then self._ctx.Diagnostics:Log("AimAssist", "disabled", "Activation and target lock cleared") end
    end

    function AimAssist:UpdateConfig()
        local previous = self._cfg or {}
        local config = {}
        for key, default in pairs(DEFAULTS) do
            local value = self._ctx.Config:Get("Aim." .. key)
            config[key] = value == nil and default or value
        end
        config.FOV = number(config.FOV, 120, 1, 2000)
        config.Smoothness = number(config.Smoothness, 12, 0, 100)
        config.MaxDistance = number(config.MaxDistance, 1000, 1, 100000)
        config.SwitchDelay = number(config.SwitchDelay, 0.2, 0, 10)
        config.Prediction = number(config.Prediction, 0, 0, 2)
        config.Mode = config.Mode == "Toggle" and "Toggle" or "Hold"
        config.Priority = config.Priority == "Distance" and "Distance" or "Angle"
        if not table.find({"UpperTorso","Torso","HumanoidRootPart"},config.FallbackPart) then config.FallbackPart="HumanoidRootPart" end
        config.Key = type(config.Key) == "string" and config.Key or "MouseButton2"
        self._bindingKey = nil
        if not MOUSE_BINDINGS[config.Key] then
            local ok, key = pcall(function() return Enum.KeyCode[config.Key] end)
            if ok and key ~= nil and key ~= Enum.KeyCode.Unknown then self._bindingKey = key
            else config.Key = "MouseButton2" end
        end
        for _, key in ipairs({ "VisibilityCheck", "TeamCheck", "HeadPriority", "Fallback", "TargetLock", "ShowFOV" }) do
            if type(config[key]) ~= "boolean" then config[key] = DEFAULTS[key] end
        end
        self._cfg = config
        local changed = false
        for key, value in pairs(config) do
            if key ~= "ShowFOV" and key ~= "Smoothness" and previous[key] ~= value then changed = true; break end
        end
        if changed then self:_clearActivation() end
    end

    function AimAssist:_candidate(entity, camera, center)
        if entity.Category ~= "Player" and entity.Category ~= "NPC" then return nil end
        local root, model, player = entity.Root, entity.Model, entity.Player
        local workspace = self._ctx.Services.Workspace
        if not root or not root:IsA("BasePart") or not root:IsDescendantOf(workspace) then return nil end
        if model and (not model.Parent or not root:IsDescendantOf(model)) then return nil end
        if not entity.Instance or not entity.Instance.Parent then return nil end
        if player == self._ctx.Player or model == self._ctx.Player.Character then return nil end
        if not entity.Humanoid or not finite(entity.Humanoid.Health) or entity.Humanoid.Health <= 0 then return nil end
        if self._cfg.TeamCheck then
            if self._ctx.Adapters then
                if self._ctx.Adapters:SameTeam(self._ctx.Player,player,model) then return nil end
            elseif player and not player.Neutral and not self._ctx.Player.Neutral
                and player.Team ~= nil and player.Team == self._ctx.Player.Team then return nil end
        end
        local part
        if self._ctx.Adapters then
            part=self._ctx.Adapters:ResolveAimPart(entity,self._cfg)
        else
            local head = model and model:FindFirstChild("Head")
            if (self._cfg.HeadPriority or not self._cfg.Fallback) and head and head:IsA("BasePart") and head.Parent and head:IsDescendantOf(model) then part=head
            elseif self._cfg.Fallback then
                part=model and model:FindFirstChild(self._cfg.FallbackPart)
            end
        end
        if not part or not part:IsA("BasePart") or not part.Parent or not part:IsDescendantOf(model) then return nil end
        if not vectorFinite(part.Position) then return nil end
        local distance = (root.Position - camera.CFrame.Position).Magnitude
        if not finite(distance) or distance > self._cfg.MaxDistance then return nil end
        local position = part.Position
        if self._cfg.Prediction > 0 and vectorFinite(part.AssemblyLinearVelocity) then
            position = position + part.AssemblyLinearVelocity * self._cfg.Prediction
        end
        local projected, onScreen = camera:WorldToViewportPoint(position)
        if not onScreen or projected.Z <= 0 or not vectorFinite(projected) then return nil end
        local pixels = (Vector2.new(projected.X, projected.Y) - center).Magnitude
        if pixels > self._cfg.FOV then return nil end
        if self._cfg.VisibilityCheck then
            -- Test the current target body, not its predicted position in empty space.
            local origin = camera.CFrame.Position
            local hit = workspace:Raycast(origin, part.Position - origin, self._raycast)
            if hit and hit.Instance ~= root and hit.Instance ~= part
                and not (model and hit.Instance:IsDescendantOf(model)) then return nil end
        end
        return {
            Key = entity.Instance, Entity = entity, Position = position, Part = part,
            Screen = projected, Distance = distance,
            Score = self._cfg.Priority == "Distance" and distance or pixels,
        }
    end

    function AimAssist:_report(active, count, duration)
        if self._elapsed - self._lastReport < 0.25 then return end
        self._lastReport = self._elapsed
        local diagnostics = self._ctx.Diagnostics
        diagnostics:Set("Aim.Active", active)
        diagnostics:Set("Aim.Target", self._targetName or "—")
        diagnostics:Set("Aim.Distance", self._targetDistance or 0)
        diagnostics:Set("Aim.Candidates", count)
        diagnostics:Set("Aim.StepMs", math.floor(duration * 100000) / 100)
        diagnostics:Set("Aim.AngularErrorDeg", self._angularError or "—")
        diagnostics:Set("Aim.AcquisitionMs", self._acquisitionMs or "—")
        diagnostics:Set("Aim.TrackingLosses", self._trackingLosses)
        diagnostics:Set("Aim.TargetPart", self._targetPart or "—")
        local countSamples=#self._samples
        local variance=countSamples>0 and math.max(0,self._sampleSquares/countSamples-(self._sampleSum/countSamples)^2) or 0
        diagnostics:Set("Aim.StabilityDeg",countSamples>0 and math.sqrt(variance) or "—")
        diagnostics:Set("Aim.StabilitySamples",countSamples)
    end

    function AimAssist:Step(dt)
        if self._destroyed or not self._enabled then return end
        if not self._ctx.IsAuthorized() then
            local active = self._cfg.Mode == "Toggle" and self._toggled or self._cfg.Mode == "Hold" and self._held
            if active and self._targetKey then self._trackingLosses += 1 end
            self:Disable()
            return
        end
        if self._ctx.InputCaptured or self._ctx.Services.UserInputService:GetFocusedTextBox() then self:_clearActivation() end
        if not finite(dt) or dt <= 0 then return end
        local started = os.clock()
        self._elapsed += dt
        local camera = self._ctx.Services.Workspace.CurrentCamera
        if not camera or camera.ViewportSize.X <= 0 or camera.ViewportSize.Y <= 0 then
            self:_clearTarget(false)
            self._root.Visible = false
            self._ctx.Diagnostics:Set("Aim.CameraStatus", "CAMERA NOT FOUND")
            self:_report(false,0,os.clock()-started)
            return
        end
        self._ctx.Diagnostics:Set("Aim.CameraStatus", "CURRENT_CAMERA")
        self._root.Visible = true
        local center = camera.ViewportSize * 0.5
        self._circle.Position = UDim2.fromOffset(center.X, center.Y)
        self._circle.Size = UDim2.fromOffset(self._cfg.FOV * 2, self._cfg.FOV * 2)
        self._circle.Visible = self._cfg.ShowFOV
        local active = self._cfg.Mode == "Toggle" and self._toggled or self._cfg.Mode == "Hold" and self._held
        if not active then
            self:_clearTarget(false)
            self:_report(false, 0, os.clock() - started)
            return
        end
        local filter = { camera }
        if self._ctx.Player.Character then table.insert(filter, self._ctx.Player.Character) end
        self._raycast.FilterDescendantsInstances = filter
        local best, locked, count = nil, nil, 0
        -- List revalidates authorization; never retain a registry record across frames.
        for _, entity in ipairs(self._ctx.Entities:List()) do
            local candidate = self:_candidate(entity, camera, center)
            if candidate then
                count += 1
                if candidate.Key == self._targetKey then locked = candidate end
                if not best or candidate.Score < best.Score then best = candidate end
            end
        end
        if self._targetKey and not locked then
            -- Count entity/visibility invalidations while tracking, never voluntary releases.
            self._trackingLosses += 1
            self:_clearTarget(true)
        end
        local selected
        if self._cfg.TargetLock and locked then selected = locked
        elseif self._elapsed < self._nextSwitchAt then selected = locked
        else selected = best end
        if not selected then
            self._indicator.Visible = false
            self:_report(true, count, os.clock() - started)
            return
        end
        if selected.Key ~= self._targetKey then
            self._targetKey = selected.Key
            self._nextSwitchAt = self._elapsed + self._cfg.SwitchDelay
            table.clear(self._samples);self._sampleIndex,self._sampleSum,self._sampleSquares=0,0,0
        end
        self._ctx.SelectedTarget, self._ctx.SelectedTargetPart=selected.Key,selected.Part
        self._targetPart=selected.Part.Name or (selected.Part==selected.Entity.Root and self._cfg.FallbackPart or "Head")
        if self._acquisitionMs == nil and self._activationAt ~= nil then
            -- Approximate input-to-first-target latency, including frame scheduling.
            self._acquisitionMs = math.max(0, (os.clock() - self._activationAt) * 1000)
        end
        self._targetName = selected.Entity.Name or selected.Entity.Instance.Name or "Target"
        self._targetDistance = selected.Distance
        self._indicator.Position = UDim2.fromOffset(selected.Screen.X, selected.Screen.Y)
        self._indicator.Visible = true
        local origin = camera.CFrame.Position
        if (selected.Position - origin).Magnitude > 0.001 then
            local desired = CFrame.lookAt(origin, selected.Position)
            local alpha = self._cfg.Smoothness <= 0 and 1 or 1 - math.exp(-self._cfg.Smoothness * math.min(dt, 0.25))
            camera.CFrame = camera.CFrame:Lerp(desired, alpha)
            -- Orientation error after interpolation, not a hit/accuracy guarantee.
            local direction = (selected.Position - camera.CFrame.Position).Unit
            local look = camera.CFrame.LookVector
            local dot = look.X * direction.X + look.Y * direction.Y + look.Z * direction.Z
            self._angularError = finite(dot) and math.deg(math.acos(math.clamp(dot, -1, 1))) or nil
            if self._angularError then
                self._sampleIndex=self._sampleIndex%60+1
                local old=self._samples[self._sampleIndex] or 0
                self._sampleSum+=self._angularError-old
                self._sampleSquares+=self._angularError*self._angularError-old*old
                self._samples[self._sampleIndex]=self._angularError
            end
        end
        self:_report(true, count, os.clock() - started)
    end

    function AimAssist:Destroy()
        if self._destroyed then return end
        self:Disable()
        self._destroyed = true
        for _, connection in ipairs(self._connections) do connection:Disconnect() end
        table.clear(self._connections)
        if self._root then self._root:Destroy() end
        self._root, self._circle, self._indicator = nil, nil, nil
    end

    return AimAssist
end
