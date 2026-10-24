return function(_import)
	local PermissionService = {}
	PermissionService.__index = PermissionService

	function PermissionService.IsFinite(value)
		return type(value) == "number" and value == value and value > -math.huge and value < math.huge
	end

	function PermissionService.IsBounded(value, minimum, maximum)
		return PermissionService.IsFinite(value) and value >= minimum and value <= maximum
	end

	local function contains(list, value)
		if type(list) ~= "table" then return false end
		for _, candidate in pairs(list) do
			if candidate == value then return true end
		end
		return false
	end

	function PermissionService.ValidatePolicy(policy)
		if type(policy) ~= "table" or type(policy.EnableStudioTests) ~= "boolean" or type(policy.EnablePrivateServers) ~= "boolean" then return false end
		if type(policy.UserIds) ~= "table" or type(policy.PlaceIds) ~= "table" then return false end
		local ranges = {
			SessionLeaseSeconds = {5, 30}, RateLimitPerSecond = {1, 30}, RateLimitBurst = {2, 64},
			MaxFlightSpeed = {0, 1000}, MaxVerticalSpeed = {0, 1000}, MaxWalkSpeed = {0, 500}, MaxDiagnosticDamage = {0, 1000},
		}
		for key, range in pairs(ranges) do if not PermissionService.IsBounded(policy[key], range[1], range[2]) then return false end end
		for _, userId in pairs(policy.UserIds) do if not PermissionService.IsFinite(userId) or userId <= 0 or userId % 1 ~= 0 then return false end end
		for _, placeId in pairs(policy.PlaceIds) do if not PermissionService.IsFinite(placeId) or placeId < 0 or placeId % 1 ~= 0 then return false end end
		return type(policy.AllowServerGodmode) == "boolean" and type(policy.AllowRestoreHealth) == "boolean"
	end

	function PermissionService.CheckPolicy(policy, isStudio, privateServerId, userId, placeId)
		if type(policy) ~= "table" or not PermissionService.IsFinite(userId) or userId % 1 ~= 0 then return false, "INVALID_POLICY" end
		if type(policy.PlaceIds) ~= "table" or type(policy.UserIds) ~= "table" then return false, "INVALID_POLICY" end
		if next(policy.PlaceIds) ~= nil and not contains(policy.PlaceIds, placeId) then return false, "PLACE_DENIED" end
		if isStudio then
			if policy.EnableStudioTests ~= true then return false, "STUDIO_DISABLED" end
			-- Studio's synthetic negative IDs are accepted only behind the explicit Studio opt-in.
			if userId < 0 then return true, "STUDIO_TEST_PLAYER" end
			if contains(policy.UserIds, userId) then return true, "AUTHORIZED" end
			return false, "USER_DENIED"
		end
		if policy.EnablePrivateServers ~= true or type(privateServerId) ~= "string" or privateServerId == "" then
			return false, "PRIVATE_SERVER_DISABLED"
		end
		if userId <= 0 or not contains(policy.UserIds, userId) then return false, "USER_DENIED" end
		return true, "AUTHORIZED"
	end

	function PermissionService.new(ctx)
		return setmetatable({ctx = ctx, Sessions = {}}, PermissionService)
	end

	function PermissionService:Check(player)
		local world = self.ctx.Game or game
		return PermissionService.CheckPolicy(self.ctx.Policy, self.ctx.Services.RunService:IsStudio(), world.PrivateServerId, player.UserId, world.PlaceId)
	end

	function PermissionService:Begin(player, now)
		local allowed, reason = self:Check(player)
		if not allowed then return nil, reason end
		local record = {
			Token = self.ctx.Services.HttpService:GenerateGUID(false),
			Character = player.Character,
			ExpiresAt = now + math.clamp(self.ctx.Policy.SessionLeaseSeconds or 15, 5, 30),
			Flight = false,
			Speed = false,
			Godmode = false,
		}
		self.Sessions[player] = record
		return record, "AUTHORIZED"
	end

	function PermissionService:Validate(player, token, now)
		local allowed, reason = self:Check(player)
		if not allowed then return nil, reason end
		local record = self.Sessions[player]
		if not record or token ~= record.Token then return nil, "STALE_SESSION" end
		if now >= record.ExpiresAt then return nil, "SESSION_EXPIRED" end
		if player.Character ~= record.Character then return nil, "CHARACTER_CHANGED" end
		return record, "AUTHORIZED"
	end

	function PermissionService:Renew(record, now)
		record.ExpiresAt = now + math.clamp(self.ctx.Policy.SessionLeaseSeconds or 15, 5, 30)
	end

	function PermissionService:Revoke(player)
		self.Sessions[player] = nil
	end

	function PermissionService:Destroy()
		table.clear(self.Sessions)
	end

	return PermissionService
end
