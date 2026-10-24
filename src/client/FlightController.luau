return function(_import)
	local FlightController = {}
	FlightController.__index = FlightController
	local keyCodes = {}
	for _, item in ipairs(Enum.KeyCode:GetEnumItems()) do keyCodes[item.Name] = item end

	local function keyCode(name)
		return keyCodes[name] or Enum.KeyCode.F
	end

	function FlightController.new(ctx)
		return setmetatable({ctx = ctx, enabled = false, destroyed = false, connections = {}, velocity = Vector3.zero, generation = 0, requestElapsed = 0}, FlightController)
	end

	function FlightController:Init()
		table.insert(self.connections, self.ctx.Services.UserInputService.InputBegan:Connect(function(input, processed)
			if self.destroyed or processed or self.ctx.InputCaptured or self.ctx.Services.UserInputService:GetFocusedTextBox() then return end
			if input.KeyCode == keyCode(self.ctx.Config:Get("Flight.Key")) then
				self.ctx.Config:Set("Flight.Enabled", not self.ctx.Config:Get("Flight.Enabled"))
			end
		end))
		return self
	end

	function FlightController:_releaseCharacter()
		if self.humanoid or self.root then self.generation += 1; self.lastRequest = nil end
		if self.linear and self.linear.Parent and self.root and self.root.Parent and not self.root.Anchored then self.root.AssemblyLinearVelocity = Vector3.zero end
		if self.linear then self.linear:Destroy(); self.linear = nil end
		if self.orientation then self.orientation:Destroy(); self.orientation = nil end
		if self.attachment then self.attachment:Destroy(); self.attachment = nil end
		if self.humanoid and self.humanoid.Parent and self.autoRotate ~= nil then self.humanoid.AutoRotate = self.autoRotate end
		self.humanoid, self.root, self.autoRotate = nil, nil, nil
		self.velocity = Vector3.zero
	end

	function FlightController:_attach()
		local character = self.ctx.Player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") or root.Anchored then self:_releaseCharacter(); return false end
		if root == self.root and self.linear and self.linear.Parent and self.orientation and self.orientation.Parent and self.attachment and self.attachment.Parent then return true end
		self.generation += 1
		self.lastRequest = nil
		self:_releaseCharacter()
		self.humanoid, self.root, self.autoRotate = humanoid, root, humanoid.AutoRotate
		humanoid.AutoRotate = false
		self.attachment = Instance.new("Attachment")
		self.attachment.Name = "VWFlightAttachment"
		self.attachment.Parent = root
		self.linear = Instance.new("LinearVelocity")
		self.linear.Name = "VWFlightVelocity"
		self.linear.Attachment0 = self.attachment
		self.linear.RelativeTo = Enum.ActuatorRelativeTo.World
		self.linear.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		self.linear.ForceLimitsEnabled = false
		self.linear.VectorVelocity = Vector3.zero
		self.linear.Parent = root
		self.orientation = Instance.new("AlignOrientation")
		self.orientation.Name = "VWFlightOrientation"
		self.orientation.Attachment0 = self.attachment
		self.orientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
		self.orientation.MaxTorque = 1000000000
		self.orientation.Responsiveness = 20
		self.orientation.Parent = root
		return true
	end

	function FlightController:_limits()
		local config = self.ctx.Config
		local policy = self.ctx.Bridge.Latest and self.ctx.Bridge.Latest.Policy or {}
		local horizontalLimit = policy.MaxFlightSpeed or 120
		local verticalLimit = policy.MaxVerticalSpeed or 90
		return math.min(config:Get("Flight.Speed"), horizontalLimit), math.min(config:Get("Flight.VerticalSpeed"), verticalLimit), horizontalLimit, verticalLimit
	end

	function FlightController:_request(enabled)
		if not self.ctx.Bridge.Available then return end
		local speed, vertical, horizontalLimit, verticalLimit = self:_limits()
		local boost = self.ctx.Config:Get("Flight.Boost")
		local requestedSpeed, requestedVertical = math.min(speed * boost, horizontalLimit), math.min(vertical * boost, verticalLimit)
		local signature = tostring(enabled) .. ":" .. tostring(requestedSpeed) .. ":" .. tostring(requestedVertical)
		if signature == self.lastRequest then return end
		self.lastRequest = signature
		self.generation += 1
		local generation, character = self.generation, self.ctx.Player.Character
		self.ctx.Bridge:Request("Flight", {Enabled = enabled, Speed = requestedSpeed, VerticalSpeed = requestedVertical}, function(response)
			if self.destroyed or self.generation ~= generation or self.ctx.Player.Character ~= character then return end
			if not response.Ok then
				self.ctx.Diagnostics:Log("Flight", "DENIED", response.Reason)
				if enabled then
					self:Disable()
					self.ctx.Config:Set("Flight.Enabled", false)
					self.ctx.Diagnostics:Set("FlightStatus", "SERVER RESTRICTION")
					self.ctx.Diagnostics:Set("FlightRestriction", response.Reason)
				end
			end
		end)
	end

	function FlightController:Enable()
		if self.destroyed or self.enabled or not self.ctx.IsAuthorized() then return false end
		self.enabled = true
		local attached = self:_attach()
		self.ctx.Diagnostics:Set("FlightStatus", if attached then "MODULE READY" else "CHARACTER NOT FOUND")
		if attached then self:_request(true) end
		return true
	end

	function FlightController:Disable()
		local wasEnabled = self.enabled
		self.enabled = false
		self.generation += 1
		self:_releaseCharacter()
		if wasEnabled then self:_request(false) end
		self.lastRequest = nil
		self.ctx.Diagnostics:Set("FlightStatus", "MODULE DISABLED")
		self.ctx.Diagnostics:Set("FlightSpeed", 0)
		self.ctx.Diagnostics:Set("FlightRequestedSpeed", 0)
		self.ctx.Diagnostics:Set("FlightCommandedSpeed", 0)
		self.ctx.Diagnostics:Set("FlightCorrection", "NOT_ACTIVE")
	end

	function FlightController:UpdateConfig(path)
		if self.enabled and (path == nil or path == "*" or string.sub(path, 1, 7) == "Flight.") then self.configDirty = true end
	end

	function FlightController:Step(dt)
		if not self.enabled or self.destroyed then return end
		if not self.ctx.IsAuthorized() then self:Disable(); self.ctx.Diagnostics:Set("FlightStatus", "SERVER RESTRICTION"); return end
		if not self:_attach() then self.ctx.Diagnostics:Set("FlightStatus", "CHARACTER NOT FOUND"); return end
		self.requestElapsed += dt
		if not self.ctx.Bridge.Available then self.lastRequest = nil
		elseif self.requestElapsed >= 0.3 and (self.configDirty or self.lastRequest == nil) then
			self.requestElapsed, self.configDirty = 0, false
			self:_request(true)
		end
		if not self.enabled then return end -- A synchronous bridge rejection may destroy the owned constraints.
		local camera = self.ctx.Services.Workspace.CurrentCamera
		if not camera then
			self.velocity = Vector3.zero
			self.linear.VectorVelocity = Vector3.zero
			self.ctx.Diagnostics:Set("FlightStatus", "CAMERA NOT FOUND")
			self.ctx.Diagnostics:Set("FlightRequestedSpeed", 0)
			self.ctx.Diagnostics:Set("FlightCommandedSpeed", 0)
			return
		end
		local input = self.ctx.Services.UserInputService
		local forward, side, vertical = 0, 0, 0
		if not self.ctx.InputCaptured and not input:GetFocusedTextBox() then
			forward = (if input:IsKeyDown(Enum.KeyCode.W) then 1 else 0) - (if input:IsKeyDown(Enum.KeyCode.S) then 1 else 0)
			side = (if input:IsKeyDown(Enum.KeyCode.D) then 1 else 0) - (if input:IsKeyDown(Enum.KeyCode.A) then 1 else 0)
			vertical = (if input:IsKeyDown(Enum.KeyCode.E) then 1 else 0) - (if input:IsKeyDown(Enum.KeyCode.Q) then 1 else 0)
		end
		local look = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
		if look.Magnitude < 0.001 then look = Vector3.new(self.root.CFrame.LookVector.X, 0, self.root.CFrame.LookVector.Z) end
		if look.Magnitude < 0.001 then look = Vector3.new(0, 0, -1) else look = look.Unit end
		local right = look:Cross(Vector3.yAxis)
		local direction = look * forward + right * side
		if direction.Magnitude > 1 then direction = direction.Unit end
		local speed, verticalSpeed, horizontalLimit, verticalLimit = self:_limits()
		local boost = if not self.ctx.InputCaptured and not input:GetFocusedTextBox() and (input:IsKeyDown(Enum.KeyCode.LeftShift) or input:IsKeyDown(Enum.KeyCode.RightShift)) then self.ctx.Config:Get("Flight.Boost") else 1
		local target = direction * math.min(speed * boost, horizontalLimit) + Vector3.yAxis * vertical * math.min(verticalSpeed * boost, verticalLimit)
		local requested = direction * self.ctx.Config:Get("Flight.Speed") * boost + Vector3.yAxis * vertical * self.ctx.Config:Get("Flight.VerticalSpeed") * boost
		local alpha = 1 - math.exp(-self.ctx.Config:Get("Flight.Acceleration") * math.clamp(dt, 0, 0.1))
		self.velocity = self.velocity:Lerp(target, alpha)
		self.linear.VectorVelocity = self.velocity
		self.orientation.CFrame = CFrame.lookAt(Vector3.zero, look)
		self.ctx.Diagnostics:Set("FlightStatus", if requested.Magnitude > target.Magnitude + 0.001 then "SERVER RESTRICTION" else "MODULE READY")
		self.ctx.Diagnostics:Set("FlightRequestedSpeed", math.round(requested.Magnitude * 10) / 10)
		self.ctx.Diagnostics:Set("FlightCommandedSpeed", math.round(self.velocity.Magnitude * 10) / 10)
		self.ctx.Diagnostics:Set("FlightSpeed", math.round(self.root.AssemblyLinearVelocity.Magnitude * 10) / 10)
		local correctionAt = self.ctx.Bridge.LastCorrectionAt or 0
		local correction = self.ctx.Bridge.Latest and self.ctx.Bridge.Latest.ConfirmedCorrection
		local confirmed = self.ctx.Bridge.Available and type(correction) == "table" and correctionAt > 0 and os.clock() - correctionAt < 3
		self.ctx.Diagnostics:Set("FlightCorrection", if confirmed then "SERVER_REPORTED" elseif (self.root.AssemblyLinearVelocity - self.velocity).Magnitude > 25 then "HEURISTIC_ONLY:SUSPECTED_LOCAL" else "HEURISTIC_ONLY:NO_LOCAL_SIGNAL")
	end

	function FlightController:Destroy()
		if self.destroyed then return end
		self:Disable()
		self.destroyed = true
		for _, connection in ipairs(self.connections) do connection:Disconnect() end
		table.clear(self.connections)
	end

	return FlightController
end
