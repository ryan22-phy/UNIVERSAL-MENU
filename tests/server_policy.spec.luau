-- Standalone pure Luau CLI test; no Roblox engine required.
	local Permission = require("../src/server/PermissionService")(function() error("Unexpected dependency") end)
	local policy = {EnableStudioTests = false, EnablePrivateServers = false, UserIds = {42}, PlaceIds = {}}
	assert(Permission.CheckPolicy(policy, true, "", -1, 0) == false, "Studio defaults to deny")
	assert(Permission.CheckPolicy(policy, false, "private", 42, 1) == false, "Private servers require opt-in")
	policy.EnableStudioTests = true
	assert(Permission.CheckPolicy(policy, true, "", -1, 0) == true, "Explicit Studio opt-in permits synthetic user")
	assert(Permission.CheckPolicy(policy, true, "", 43, 0) == false, "Real Studio users need allowlist")
	policy.EnablePrivateServers = true
	assert(Permission.CheckPolicy(policy, false, "", 42, 1) == false, "Public server always denied")
	assert(Permission.CheckPolicy(policy, false, "private", 43, 1) == false, "Private user allowlist checked")
	assert(Permission.CheckPolicy(policy, false, "private", 42, 1) == true, "Private opt-in plus allowlist")
	assert(Permission.CheckPolicy(policy, false, "private", -1, 1) == false, "Synthetic users never allowed outside Studio")
	policy.PlaceIds = {2}
	assert(Permission.CheckPolicy(policy, false, "private", 42, 1) == false, "Place allowlist checked")
	assert(Permission.IsBounded(0 / 0, 0, 100) == false)
	assert(Permission.IsBounded(math.huge, 0, 100) == false)
	assert(Permission.IsBounded(-1, 0, 100) == false)
	assert(Permission.IsBounded(50, 0, 100) == true)
	local serverPolicy = require("../src/config/ServerPolicy")(function() error("Unexpected dependency") end)
	assert(Permission.ValidatePolicy(serverPolicy) == true, "Default policy is structurally valid")
	serverPolicy.MaxWalkSpeed = math.huge
	assert(Permission.ValidatePolicy(serverPolicy) == false, "Non-finite policy fails closed")
	local mockPlayer = {UserId = -1, Character = {}}
	local clockPolicy = require("../src/config/ServerPolicy")(nil)
	clockPolicy.EnableStudioTests = true
	local permissions = Permission.new({
		Policy = clockPolicy,
		Game = {PrivateServerId = "", PlaceId = 0},
		Services = {RunService = {IsStudio = function() return true end}, HttpService = {GenerateGUID = function() return "session-test" end}},
	})
	local session = permissions:Begin(mockPlayer, 0)
	assert(session ~= nil and session.ExpiresAt == 15, "Session starts with 15 second lease")
	assert(permissions:Validate(mockPlayer, "session-test", 14) == session, "Fresh token accepted")
	assert(permissions:Validate(mockPlayer, "stale", 1) == nil, "Stale token denied")
	assert(permissions:Validate(mockPlayer, "session-test", 15) == nil, "Lease boundary expires")
	permissions:Renew(session, 10)
	assert(permissions:Validate(mockPlayer, "session-test", 24) == session, "Observe renewal extends lease")
	mockPlayer.Character = {}
	assert(permissions:Validate(mockPlayer, "session-test", 11) == nil, "Respawn invalidates session")
	mockPlayer.Character = session.Character
	clockPolicy.EnableStudioTests = false
	assert(permissions:Validate(mockPlayer, "session-test", 11) == nil, "Live authorization revoked")
	permissions:Revoke(mockPlayer)
	assert(permissions.Sessions[mockPlayer] == nil, "Release clears session")
	local Damage = require("../src/server/DamageTestController")(function() return Permission end)
	local Server = require("../src/server/ServerTestService")(function(name)
		return if name == "server/PermissionService" then Permission else Damage
	end)
	assert(Server.ValidatePayload("Observe", {}) == true, "Empty observation accepted")
	assert(Server.ValidatePayload("Observe", {UserId = 42}) == false, "Client identity rejected")
	assert(Server.ValidatePayload("Godmode", {Enabled = "true"}) == false, "Boolean string rejected")
	assert(Server.ValidatePayload("Godmode", {Enabled = true}) == true, "Boolean accepted")
	assert(Server.ValidatePayload("Speed", {Enabled = true, WalkSpeed = 0 / 0}) == false, "NaN rejected")
	assert(Server.ValidatePayload("Flight", {Enabled = true, Speed = math.huge}) == false, "Infinity rejected")
	assert(Server.ValidatePayload("Damage", {Amount = {25}}) == false, "Nested payload rejected")
	assert(Server.ValidatePayload("Unknown", {}) == false, "Unknown action rejected")
	assert(Server.ValidatePayload("Observe", {ConfirmedCorrection = {Sequence = 1, Reason = "client claim"}}) == false, "Client correction confirmation rejected")
	assert(Server.ValidatePayload("Flight", {Enabled = true, ConfirmedCorrection = true}) == false, "Client cannot confirm movement correction")
	-- Real ServerTestService with explicit Humanoid boundary double; no engine/replication.
	local baselineCharacter = {}
	local baselineHumanoid = {WalkSpeed = 16, Parent = baselineCharacter}
	function baselineCharacter:FindFirstChildOfClass(name) return if name == "Humanoid" then baselineHumanoid else nil end
	local baselinePlayer = {Character = baselineCharacter}
	local baselineService = Server.new({Policy = clockPolicy, Services = {}})
	baselineService.players[baselinePlayer] = {Connections = {}}
	baselineService:_capture(baselinePlayer)
	assert(baselineService.players[baselinePlayer].WalkSpeed == 16, "Server captures initial speed baseline")
	baselineHumanoid.WalkSpeed = 20 -- A normal game buff before laboratory ownership.
	baselineService:_capture(baselinePlayer)
	assert(baselineService.players[baselinePlayer].WalkSpeed == 20, "Unowned baseline follows normal game speed changes")
	baselineService.players[baselinePlayer].SpeedOwned = true
	baselineHumanoid.WalkSpeed = 40
	baselineService:_capture(baselinePlayer)
	assert(baselineService.players[baselinePlayer].WalkSpeed == 20, "Owned speed does not overwrite baseline")
	baselineService:_release(baselinePlayer)
	assert(baselineHumanoid.WalkSpeed == 20, "Release restores latest pre-ownership baseline")
	print("PASS server_policy.spec: 37 assertions")
