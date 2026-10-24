return function(_import)
	local SpeedController = {}
	SpeedController.__index = SpeedController
	local keyCodes = {}
	for _, item in ipairs(Enum.KeyCode:GetEnumItems()) do keyCodes[item.Name] = item end

	function SpeedController.new(ctx)
		return setmetatable({ctx = ctx, enabled = false, destroyed = false, lastSampleAt = 0, suspectedUntil = 0, reportElapsed = 0, generation = 0, requestElapsed = 0}, SpeedController)
	end

	function SpeedController:Init() return self end

	function SpeedController:_restore()
		if self.humanoid then self.generation += 1; self.lastRequest = nil end
		if self.humanoid and self.humanoid.Parent then self.humanoid.WalkSpeed = self.baseline end
		self.humanoid, self.baseline, self.lastWritten, self.lastPosition = nil, nil, nil, nil
		self.lastSampleAt, self.suspectedUntil, self.reportElapsed = 0, 0, 0
	end

	function SpeedController:_capture()
		local character = self.ctx.Player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then self:_restore(); return false end
		if humanoid ~= self.humanoid then
			self.generation += 1
			self.lastRequest = nil
			self:_restore()
			self.humanoid, self.baseline = humanoid, humanoid.WalkSpeed
			self.current = humanoid.WalkSpeed
		end
		return true
	end

	function SpeedController:_values()
		local config = self.ctx.Config
		local policy = self.ctx.Bridge.Latest and self.ctx.Bridge.Latest.Policy or {}
		local limit = policy.MaxWalkSpeed or 80
		local multiplier = config:Get("Speed.Multiplier")
		local walk, sprint = config:Get("Speed.WalkSpeed") * multiplier, config:Get("Speed.SprintSpeed") * multiplier
		return math.min(walk, limit), math.min(sprint, limit), walk, sprint
	end

	function SpeedController:_request(enabled)
		if not self.ctx.Bridge.Available then return end
		local walk, sprint = self:_values()
		local signature = tostring(enabled) .. ":" .. tostring(walk) .. ":" .. tostring(sprint)
		if signature == self.lastRequest then return end
		self.lastRequest = signature
		self.generation += 1
		local generation, character = self.generation, self.ctx.Player.Character
		self.ctx.Bridge:Request("Speed", {Enabled = enabled, WalkSpeed = walk, SprintSpeed = sprint, Multiplier = 1}, function(response)
			if self.destroyed or self.generation ~= generation or self.ctx.Player.Character ~= character then return end
			if not response.Ok then
				self.ctx.Diagnostics:Log("Speed", "DENIED", response.Reason)
				if enabled then
					self:Disable()
					self.ctx.Config:Set("Speed.Enabled", false)
					self.ctx.Diagnostics:Set("SpeedStatus", "SERVER RESTRICTION")
					self.ctx.Diagnostics:Set("SpeedRestriction", response.Reason)
				end
			end
		end)
	end

	function SpeedController:Enable()
		if self.destroyed or self.enabled or not self.ctx.IsAuthorized() then return false end
		local captured = self:_capture()
		self.enabled = true
		self.ctx.Diagnostics:Set("SpeedStatus", if captured then "MODULE READY" else "CHARACTER NOT FOUND")
		if captured then self:_request(true) end
		return true
	end

	function SpeedController:Disable()
		local wasEnabled = self.enabled
		self.enabled = false
		self.generation += 1
		self:_restore()
		if wasEnabled then self:_request(false) end
		self.lastRequest = nil
		self.ctx.Diagnostics:Set("SpeedStatus", "MODULE DISABLED")
		self.ctx.Diagnostics:Set("RequestedSpeed", 0)
		self.ctx.Diagnostics:Set("AppliedSpeed", 0)
		self.ctx.Diagnostics:Set("EffectiveSpeed", 0)
		self.ctx.Diagnostics:Set("SpeedCorrection", "NOT_ACTIVE")
	end

	function SpeedController:UpdateConfig(path)
		if self.enabled and (path == nil or path == "*" or string.sub(path, 1, 6) == "Speed.") then self.configDirty = true end
	end

	function SpeedController:Step(dt)
		if self.destroyed or not self.enabled then return end
		if not self.ctx.IsAuthorized() then self:Disable(); self.ctx.Diagnostics:Set("SpeedStatus", "SERVER RESTRICTION"); return end
		if not self:_capture() then self.ctx.Diagnostics:Set("SpeedStatus", "CHARACTER NOT FOUND"); return end
		self.requestElapsed += dt
		if not self.ctx.Bridge.Available then self.lastRequest = nil
		elseif self.requestElapsed >= 0.3 and (self.configDirty or self.lastRequest == nil) then
			self.requestElapsed, self.configDirty = 0, false
			self:_request(true)
		end
		if not self.enabled then return end -- A synchronous bridge rejection may release character ownership.
		local humanoid = self.humanoid
		local now = os.clock()
		if self.lastWritten and math.abs(humanoid.WalkSpeed - self.lastWritten) > 2 then self.suspectedUntil = now + 2 end
		local input = self.ctx.Services.UserInputService
		local sprintKey = keyCodes[self.ctx.Config:Get("Speed.SprintKey")] or Enum.KeyCode.LeftShift
		local sprinting = not self.ctx.InputCaptured and not input:GetFocusedTextBox() and input:IsKeyDown(sprintKey)
		local walk, sprint, requestedWalk, requestedSprint = self:_values()
		local target = if sprinting then sprint else walk
		local requested = if sprinting then requestedSprint else requestedWalk
		local alpha = 1 - math.exp(-self.ctx.Config:Get("Speed.Acceleration") * math.clamp(dt, 0, 0.1))
		self.current += (target - self.current) * alpha
		humanoid.WalkSpeed = self.current
		self.lastWritten = self.current
		self.ctx.Diagnostics:Set("RequestedSpeed", math.round(requested * 10) / 10)
		self.ctx.Diagnostics:Set("AppliedSpeed", math.round(humanoid.WalkSpeed * 10) / 10)
		self.ctx.Diagnostics:Set("SpeedMode", if sprinting then "SPRINT" else "WALK")
		self.ctx.Diagnostics:Set("SpeedStatus", if requested > target then "SERVER RESTRICTION" else "MODULE READY")
		self.reportElapsed += dt
		if self.reportElapsed < 0.2 then return end
		self.reportElapsed = 0
		local root = humanoid.Parent and humanoid.Parent:FindFirstChild("HumanoidRootPart")
		local effective = 0
		if root and root:IsA("BasePart") then
			local velocity = root.AssemblyLinearVelocity
			effective = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
			if self.lastPosition and self.lastSampleAt > 0 then
				local displacement = root.Position - self.lastPosition
				local measured = Vector3.new(displacement.X, 0, displacement.Z).Magnitude / math.max(now - self.lastSampleAt, 0.001)
				if measured > math.max(target * 3, 100) and math.abs(measured - effective) > 60 then self.suspectedUntil = now + 2 end
			end
			self.lastPosition, self.lastSampleAt = root.Position, now
		end
		self.ctx.Diagnostics:Set("EffectiveSpeed", math.round(effective * 10) / 10)
		local correction = self.ctx.Bridge.Latest and self.ctx.Bridge.Latest.ConfirmedCorrection
		local correctionAt = self.ctx.Bridge.LastCorrectionAt or 0
		local confirmed = self.ctx.Bridge.Available and type(correction) == "table" and correctionAt > 0 and now - correctionAt < 3
		self.ctx.Diagnostics:Set("SpeedCorrection", if confirmed then "SERVER_REPORTED" elseif now < self.suspectedUntil then "HEURISTIC_ONLY:SUSPECTED_LOCAL" else "HEURISTIC_ONLY:NO_LOCAL_SIGNAL")
	end

	function SpeedController:Destroy()
		if self.destroyed then return end
		self:Disable()
		self.destroyed = true
	end

	return SpeedController
end
