return function(import)
	local PermissionService = import("server/PermissionService")
	local DamageTestController = import("server/DamageTestController")
	local ServerTestService = {}
	ServerTestService.__index = ServerTestService
	local allowedActions = {Hello = true, Observe = true, Flight = true, Speed = true, Godmode = true, Damage = true, RestoreHealth = true, Release = true}
	local payloadFields = {
		Hello = {}, Observe = {}, Release = {}, RestoreHealth = {},
		Flight = {Enabled = "boolean", Speed = "number", VerticalSpeed = "number"},
		Speed = {Enabled = "boolean", WalkSpeed = "number", SprintSpeed = "number", Multiplier = "number"},
		Godmode = {Enabled = "boolean"}, Damage = {Amount = "number"},
	}

	local function horizontal(vector)
		return Vector3.new(vector.X, 0, vector.Z).Magnitude
	end

	local function validPayload(action, payload)
		if type(payload) ~= "table" then return false end
		local fields = payloadFields[action]
		if not fields then return false end
		local count = 0
		for key, value in pairs(payload) do
			count += 1
			if count > 4 or fields[key] == nil or type(value) ~= fields[key] then return false end
			if type(value) == "number" and not PermissionService.IsFinite(value) then return false end
		end
		if action == "Flight" or action == "Speed" or action == "Godmode" then return type(payload.Enabled) == "boolean" end
		if action == "Damage" then return type(payload.Amount) == "number" end
		return true
	end
	ServerTestService.ValidatePayload = validPayload

	function ServerTestService.new(ctx)
		local self = setmetatable({ctx = ctx, connections = {}, players = {}, buckets = {}, destroyed = false, elapsed = 0}, ServerTestService)
		self.Permission = PermissionService.new(ctx)
		self.Damage = DamageTestController.new({CanProtect = function(player)
			local session = self.Permission.Sessions[player]
			return session ~= nil and self.Permission:Validate(player, session.Token, os.clock()) ~= nil and session.Godmode == true
		end})
		return self
	end

	function ServerTestService:_capture(player)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local state = self.players[player]
		if not state then return end
		if humanoid and state.Humanoid ~= humanoid then
			state.Humanoid = humanoid
			state.WalkSpeed = humanoid.WalkSpeed
			state.SpeedOwned = false
		elseif humanoid and not state.SpeedOwned then
			-- Follow ordinary game buffs/debuffs until the laboratory acquires speed.
			state.WalkSpeed = humanoid.WalkSpeed
		end
	end

	function ServerTestService:_release(player)
		local state = self.players[player]
		if state and state.SpeedOwned and state.Humanoid and state.Humanoid.Parent then
			state.Humanoid.WalkSpeed = state.WalkSpeed
			state.SpeedOwned = false
		end
		self.Damage:Release(player)
		self.Permission:Revoke(player)
	end

	function ServerTestService:_addPlayer(player)
		if self.players[player] then return end
		local state = {Connections = {}}
		self.players[player] = state
		table.insert(state.Connections, player.CharacterAdded:Connect(function()
			self:_release(player)
			state.Humanoid = nil
			self:_capture(player)
		end))
		table.insert(state.Connections, player.CharacterRemoving:Connect(function() self:_release(player) end))
		self:_capture(player)
	end

	function ServerTestService:_removePlayer(player)
		self:_release(player)
		local state = self.players[player]
		if state then
			for _, connection in ipairs(state.Connections) do connection:Disconnect() end
		end
		self.players[player] = nil
		self.buckets[player] = nil
	end

	function ServerTestService:_allowRequest(player, now)
		local policy = self.ctx.Policy
		local burst = math.clamp(policy.RateLimitBurst or 16, 2, 64)
		local rate = math.clamp(policy.RateLimitPerSecond or 8, 1, 30)
		local bucket = self.buckets[player]
		if not bucket then bucket = {Tokens = burst, At = now}; self.buckets[player] = bucket end
		bucket.Tokens = math.min(burst, bucket.Tokens + math.max(0, now - bucket.At) * rate)
		bucket.At = now
		if bucket.Tokens < 1 then return false end
		bucket.Tokens -= 1
		return true
	end

	function ServerTestService:_data(player, session)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		return {
			Authorized = session ~= nil,
			Godmode = session ~= nil and self.Damage:IsProtected(player),
			Health = if humanoid then humanoid.Health else nil,
			MaxHealth = if humanoid then humanoid.MaxHealth else nil,
			CharacterAlive = humanoid ~= nil and humanoid.Health > 0,
			Flight = session ~= nil and session.Flight == true,
			Speed = session ~= nil and session.Speed == true,
			ObservedHorizontalSpeed = if session then session.ObservedHorizontalSpeed or 0 else 0,
			PositionDelta = if session then session.PositionDelta or 0 else 0,
			DisplacementSpeed = if session then session.DisplacementSpeed or 0 else 0,
			SuspectedCorrection = session ~= nil and session.SuspectedCorrection == true,
			CorrectionStatus = "HEURISTIC_ONLY",
			ConfirmedCorrection = if session then session.ConfirmedCorrection else nil,
			ProtectionScope = "DamageTestController.ApplyDamage ONLY",
			Policy = {MaxFlightSpeed = self.ctx.Policy.MaxFlightSpeed, MaxVerticalSpeed = self.ctx.Policy.MaxVerticalSpeed, MaxWalkSpeed = self.ctx.Policy.MaxWalkSpeed},
		}
	end

	function ServerTestService:_respond(player, id, ok, reason, session)
		if self.destroyed or player.Parent ~= self.ctx.Services.Players then return end
		self.Response:FireClient(player, {Id = id, Ok = ok, Reason = reason, Session = if session then session.Token else nil, Data = self:_data(player, session)})
	end

	function ServerTestService:_onRequest(player, message)
		local now = os.clock()
		-- Invalid/rate-limited packets are dropped before any game mutation or response.
		if not self:_allowRequest(player, now) or type(message) ~= "table" then return end
		local id, action, payload = message.Id, message.Action, message.Payload
		if not PermissionService.IsBounded(id, 1, 1000000000) or id % 1 ~= 0 then return end
		if type(action) ~= "string" or not allowedActions[action] or not validPayload(action, payload) then
			self:_respond(player, id, false, "INVALID_REQUEST", nil); return
		end
		local fieldCount = 0
		for key in pairs(message) do
			fieldCount += 1
			if fieldCount > 4 or (key ~= "Id" and key ~= "Action" and key ~= "Payload" and key ~= "Session") then
				self:_respond(player, id, false, "INVALID_REQUEST", nil); return
			end
		end
		if action == "Hello" then
			self:_release(player)
			self:_capture(player)
			local session, reason = self.Permission:Begin(player, now)
			if session then session.Seen = {}; session.SeenQueue = {} end
			self:_respond(player, id, session ~= nil, reason, session)
			return
		end
		if type(message.Session) ~= "string" or #message.Session > 64 then self:_respond(player, id, false, "STALE_SESSION", nil); return end
		local session, reason = self.Permission:Validate(player, message.Session, now)
		if not session then
			self:_release(player)
			self:_respond(player, id, false, reason, nil); return
		end
		if session.Seen[id] then self:_respond(player, id, false, "DUPLICATE_REQUEST", session); return end
		session.Seen[id] = true
		table.insert(session.SeenQueue, id)
		if #session.SeenQueue > 64 then session.Seen[table.remove(session.SeenQueue, 1)] = nil end
		local ok = true
		reason = "OK"
		if action == "Observe" then
			self.Permission:Renew(session, now)
		elseif action == "Release" then
			self:_release(player)
			session = nil
			reason = "RELEASED"
		elseif action == "Flight" then
			if (payload.Speed ~= nil and not PermissionService.IsBounded(payload.Speed, 0, self.ctx.Policy.MaxFlightSpeed)) or (payload.VerticalSpeed ~= nil and not PermissionService.IsBounded(payload.VerticalSpeed, 0, self.ctx.Policy.MaxVerticalSpeed)) then
				ok, reason = false, "FLIGHT_LIMIT"
			else
				session.Flight = payload.Enabled
				session.AllowedFlightSpeed = payload.Speed or self.ctx.Policy.MaxFlightSpeed
			end
		elseif action == "Speed" then
			local walk, sprint, multiplier = payload.WalkSpeed or 24, payload.SprintSpeed or 36, payload.Multiplier or 1
			local limit = self.ctx.Policy.MaxWalkSpeed
			if not PermissionService.IsBounded(walk, 0, limit) or not PermissionService.IsBounded(sprint, 0, limit) or not PermissionService.IsBounded(multiplier, 0.1, 10) or math.max(walk, sprint) * multiplier > limit then
				ok, reason = false, "SPEED_LIMIT"
			else
				self:_capture(player)
				local state = self.players[player]
				if not state or not state.Humanoid or state.Humanoid.Health <= 0 then ok, reason = false, "CHARACTER_UNAVAILABLE"
				else
					session.Speed = payload.Enabled
					session.AllowedWalkSpeed = math.max(walk, sprint) * multiplier
					state.SpeedOwned = payload.Enabled
					state.Humanoid.WalkSpeed = if payload.Enabled then walk * multiplier else state.WalkSpeed
				end
			end
		elseif action == "Godmode" then
			if payload.Enabled and self.ctx.Policy.AllowServerGodmode ~= true then ok, reason = false, "GODMODE_DISABLED"
			else session.Godmode = payload.Enabled; self.Damage:SetGodmode(player, payload.Enabled) end
		elseif action == "Damage" then
			if not PermissionService.IsBounded(payload.Amount, 0, self.ctx.Policy.MaxDiagnosticDamage) then ok, reason = false, "DAMAGE_LIMIT"
			else
				ok, reason = self.Damage:ApplyDamage(player, payload.Amount)
				-- Blocking the diagnostic damage is a successful observation of this gate.
				if reason == "GODMODE_BLOCKED" then ok = true end
			end
		elseif action == "RestoreHealth" then
			if self.ctx.Policy.AllowRestoreHealth ~= true then ok, reason = false, "RESTORE_DISABLED"
			else ok, reason = self.Damage:RestoreHealth(player) end
		end
		self:_respond(player, id, ok, reason, session)
	end

	function ServerTestService:_step(dt)
		self.elapsed += dt
		if self.elapsed < 0.25 then return end
		self.elapsed = 0
		local now = os.clock()
		for player in pairs(self.players) do self:_capture(player) end
		for player, session in pairs(self.Permission.Sessions) do
			if not self.Permission:Validate(player, session.Token, now) then self:_release(player)
			else
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					session.ObservedHorizontalSpeed = horizontal(root.AssemblyLinearVelocity)
					if session.LastPosition and session.LastSampleAt then
						local delta = horizontal(root.Position - session.LastPosition)
						local elapsed = math.max(now - session.LastSampleAt, 0.001)
						session.PositionDelta = delta
						session.DisplacementSpeed = delta / elapsed
						local expected = math.max(session.AllowedFlightSpeed or 0, session.AllowedWalkSpeed or 0, 16)
						-- Teleports, latency and collisions can all trigger this; it is never proof of a correction.
						session.SuspectedCorrection = session.DisplacementSpeed > math.max(100, expected * 3) and math.abs(session.DisplacementSpeed - session.ObservedHorizontalSpeed) > 60
					end
					session.LastPosition, session.LastSampleAt = root.Position, now
				end
			end
		end
	end

	function ServerTestService:Init()
		local services = self.ctx.Services
		assert(PermissionService.ValidatePolicy(self.ctx.Policy), "Invalid server policy; refusing to initialize")
		assert(not services.ReplicatedStorage:FindFirstChild("VWMenuLabRemote"), "VWMenuLabRemote already exists: install one server bootstrap only")
		self.Folder = Instance.new("Folder")
		self.Folder.Name = "VWMenuLabRemote"
		self.Request = Instance.new("RemoteEvent")
		self.Request.Name = "Request"
		self.Request.Parent = self.Folder
		self.Response = Instance.new("RemoteEvent")
		self.Response.Name = "Response"
		self.Response.Parent = self.Folder
		-- This gateway is server-only. External weapons can call Invoke(targetPlayer, damage).
		assert(not services.ServerScriptService:FindFirstChild("VWMenuLabDamage"), "VWMenuLabDamage already exists")
		assert(not services.ServerScriptService:FindFirstChild("VWMenuLabCorrection"), "VWMenuLabCorrection already exists")
		self.DamageGateway = Instance.new("BindableFunction")
		self.DamageGateway.Name = "VWMenuLabDamage"
		self.DamageGateway.OnInvoke = function(targetPlayer, amount)
			if typeof(targetPlayer) ~= "Instance" or not targetPlayer:IsA("Player") or targetPlayer.Parent ~= services.Players then return false, "INVALID_TARGET" end
			return self.Damage:ApplyDamage(targetPlayer, amount)
		end
		self.DamageGateway.Parent = services.ServerScriptService
		-- Optional instrumentation: the owning game fires this only AFTER it corrects a player.
		self.CorrectionGateway = Instance.new("BindableEvent")
		self.CorrectionGateway.Name = "VWMenuLabCorrection"
		table.insert(self.connections, self.CorrectionGateway.Event:Connect(function(player, reason)
			if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= services.Players then return end
			if type(reason) ~= "string" or #reason < 1 or #reason > 128 then return end
			local session = self.Permission.Sessions[player]
			if not session or not self.Permission:Validate(player, session.Token, os.clock()) then return end
			session.CorrectionSequence = (session.CorrectionSequence or 0) + 1
			session.ConfirmedCorrection = {Sequence = session.CorrectionSequence, Reason = reason}
		end))
		self.CorrectionGateway.Parent = services.ServerScriptService
		table.insert(self.connections, self.Request.OnServerEvent:Connect(function(player, message) self:_onRequest(player, message) end))
		table.insert(self.connections, services.Players.PlayerAdded:Connect(function(player) self:_addPlayer(player) end))
		table.insert(self.connections, services.Players.PlayerRemoving:Connect(function(player) self:_removePlayer(player) end))
		table.insert(self.connections, services.RunService.Heartbeat:Connect(function(dt) self:_step(dt) end))
		for _, player in ipairs(services.Players:GetPlayers()) do self:_addPlayer(player) end
		self.Folder.Parent = services.ReplicatedStorage
		return self
	end

	function ServerTestService:Destroy()
		if self.destroyed then return end
		self.destroyed = true
		for _, connection in ipairs(self.connections) do connection:Disconnect() end
		for player in pairs(self.players) do self:_removePlayer(player) end
		self.Permission:Destroy()
		self.Damage:Destroy()
		if self.DamageGateway then self.DamageGateway:Destroy() end
		if self.CorrectionGateway then self.CorrectionGateway:Destroy() end
		if self.Folder then self.Folder:Destroy() end
	end

	return ServerTestService
end
