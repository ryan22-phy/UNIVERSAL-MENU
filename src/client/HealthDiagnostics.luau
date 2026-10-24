return function(_import)
	local HealthDiagnostics = {}
	HealthDiagnostics.__index = HealthDiagnostics

	local function finite(value)
		return type(value) == "number" and value == value and value > -math.huge and value < math.huge
	end

	function HealthDiagnostics.new(ctx)
		return setmetatable({ctx = ctx, enabled = false, destroyed = false, elapsed = 0, generation = 0, confirmedGodmode = false}, HealthDiagnostics)
	end

	function HealthDiagnostics:Init() return self end

	function HealthDiagnostics:_humanoid()
		local character = self.ctx.Player.Character
		return character and character:FindFirstChildOfClass("Humanoid")
	end

	function HealthDiagnostics:_requestGodmode(enabled)
		if not self.ctx.Bridge.Available then self.lastRequested = nil; self.confirmedGodmode = false; return false end
		self.lastRequested = enabled
		self.generation += 1
		local generation = self.generation
		local completed = false
		local function onResponse(response)
			if self.destroyed or generation ~= self.generation then return end
			completed = true
			local data = response.Data or {}
			self.confirmedGodmode = response.Ok and enabled and data.Godmode == true
			if not response.Ok then
				-- A rejected enable must not leave a sticky desired state or retry loop.
				self.lastRequested = false
				if enabled then self.ctx.Config:Set("Player.ServerGodmode", false) end
			end
			self.ctx.Diagnostics:Set("ServerGodmode", self.enabled and self.confirmedGodmode)
			self.ctx.Diagnostics:Log("Health", if response.Ok then "SERVER_ACK" else "DENIED", response.Reason, {Scope = "DamageTestController.ApplyDamage ONLY"})
		end
		local sent, reason = self.ctx.Bridge:Request("Godmode", {Enabled = enabled}, onResponse)
		if sent == false and not completed then onResponse({Ok = false, Reason = reason or "REQUEST_NOT_SENT", Data = {}}) end
		return sent, reason
	end

	function HealthDiagnostics:Enable()
		if self.destroyed or not self.ctx.IsAuthorized() then return false end
		self.enabled = true
		self:UpdateConfig()
		return true
	end

	function HealthDiagnostics:_restoreProbe()
		local probe = self.probe
		self.probe = nil
		if probe and probe.Humanoid.Parent and probe.Humanoid.Health == probe.Written then probe.Humanoid.Health = probe.Original end
	end

	function HealthDiagnostics:Disable()
		local wasEnabled = self.enabled
		self.generation += 1 -- Invalidate callbacks even when the bridge has already disappeared.
		self.enabled = false
		self.confirmedGodmode = false
		self:_restoreProbe()
		if wasEnabled and self.lastRequested == true then self:_requestGodmode(false) end
		self.lastRequested = nil
		self.ctx.Diagnostics:Set("ServerGodmode", false)
	end

	function HealthDiagnostics:UpdateConfig()
		if self.destroyed then return end
		local desired = self.enabled and self.ctx.IsAuthorized() and self.ctx.Config:Get("Player.ServerGodmode") == true
		if not self.ctx.Bridge.Available then
			if self.lastRequested ~= nil then self.generation += 1 end
			self.lastRequested = nil
			self.confirmedGodmode = false
			self.ctx.Diagnostics:Set("ServerGodmode", false)
		elseif self.lastRequested ~= desired then self:_requestGodmode(desired) end
	end

	function HealthDiagnostics:ProbeLocalHealth()
		if self.destroyed or not self.ctx.IsAuthorized() then return false, "NOT_AUTHORIZED" end
		local humanoid = self:_humanoid()
		if not humanoid or humanoid.Health <= 0 or not finite(humanoid.MaxHealth) or humanoid.MaxHealth <= 0 then return false, "CHARACTER_UNAVAILABLE" end
		self:_restoreProbe()
		local original = humanoid.Health
		humanoid.Health = humanoid.MaxHealth
		self.probe = {Humanoid = humanoid, Original = original, Written = humanoid.Health}
		self.ctx.Diagnostics:Log("Health", "LOCAL_PROBE", "One local Health assignment; it does not grant server protection", {Before = original, LocalAfter = humanoid.Health, ServerHealth = self.ctx.Bridge.Latest and self.ctx.Bridge.Latest.Health})
		-- A fresh observation is read-only and also shows whether local and server health differ.
		if self.ctx.Bridge.Available then self.ctx.Bridge:Request("Observe", {}) end
		return true, if original == humanoid.Health then "ALREADY_AT_MAX_HEALTH" else "LOCAL_ONLY"
	end

	function HealthDiagnostics:RequestDamage(amount)
		if self.destroyed or not self.ctx.IsAuthorized() or not self.ctx.Bridge.Available then return false, "SERVER_REQUIRED" end
		if not finite(amount) or amount < 0 or amount > 100 then return false, "INVALID_AMOUNT" end
		return self.ctx.Bridge:Request("Damage", {Amount = amount}, function(response)
			if not self.destroyed then self.ctx.Diagnostics:Log("Health", if response.Ok then "SERVER_ACK" else "DENIED", response.Reason) end
		end)
	end

	function HealthDiagnostics:RestoreHealth()
		if self.destroyed or not self.ctx.IsAuthorized() or not self.ctx.Bridge.Available then return false, "SERVER_REQUIRED" end
		return self.ctx.Bridge:Request("RestoreHealth", {}, function(response)
			if not self.destroyed then self.ctx.Diagnostics:Log("Health", if response.Ok then "SERVER_ACK" else "DENIED", response.Reason) end
		end)
	end

	function HealthDiagnostics:Step(dt)
		if self.destroyed then return end
		if self.enabled and not self.ctx.IsAuthorized() then self:Disable() end
		self.elapsed += dt
		if self.elapsed < 0.2 then return end
		self.elapsed = 0
		self:UpdateConfig()
		local humanoid = self:_humanoid()
		local localHealth = if humanoid then humanoid.Health else nil
		local data = self.ctx.Bridge.Latest or {}
		local available = self.ctx.Bridge.Available
		local serverHealth = if available then data.Health else nil
		self.ctx.Diagnostics:Set("LocalHealth", localHealth or "UNAVAILABLE")
		self.ctx.Diagnostics:Set("ServerHealth", serverHealth or "UNAVAILABLE")
		local protected = self.enabled and self.confirmedGodmode and available and data.Godmode == true
		self.ctx.Diagnostics:Set("ServerGodmode", protected)
		self.ctx.Diagnostics:Set("HealthDivergence", if finite(localHealth) and finite(serverHealth) then math.round((localHealth - serverHealth) * 100) / 100 else "UNAVAILABLE")
		self.ctx.Diagnostics:Set("HealthStatus", if protected then "SERVER_DAMAGE_GATE_ONLY" elseif available then "SERVER_OBSERVED" else "LOCAL_DIAGNOSTIC_ONLY")
	end

	function HealthDiagnostics:Destroy()
		if self.destroyed then return end
		self:Disable()
		self.destroyed = true
		self.generation += 1
	end

	return HealthDiagnostics
end
