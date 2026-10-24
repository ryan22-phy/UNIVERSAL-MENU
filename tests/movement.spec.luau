-- Execute using run_movement_tests.py --luau PATH.
-- Explicit doubles exercise module decisions/lifecycles only. They do not model
-- Roblox physics, networking, replication, server authority or input scheduling.
local assertions = 0
local function check(condition, label)
	assertions += 1
	assert(condition, label)
end

local VectorMethods = {}
local VectorMeta = {}
function VectorMeta.__index(value, key)
	if key == "Magnitude" then return math.sqrt(value.X * value.X + value.Y * value.Y + value.Z * value.Z) end
	if key == "Unit" then return value * (1 / value.Magnitude) end
	return VectorMethods[key]
end
local function vector(x, y, z) return setmetatable({X = x, Y = y, Z = z}, VectorMeta) end
function VectorMeta.__add(a, b) return vector(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
function VectorMeta.__sub(a, b) return vector(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
function VectorMeta.__mul(a, b)
	if type(a) == "number" then return vector(a * b.X, a * b.Y, a * b.Z) end
	return vector(a.X * b, a.Y * b, a.Z * b)
end
function VectorMethods:Lerp(other, alpha) return self + (other - self) * alpha end
function VectorMethods:Cross(other) return vector(self.Y * other.Z - self.Z * other.Y, self.Z * other.X - self.X * other.Z, self.X * other.Y - self.Y * other.X) end
local Vector3 = {new = vector, zero = vector(0, 0, 0), yAxis = vector(0, 1, 0)}
local CFrame = {lookAt = function(_origin, direction) return {LookVector = direction} end}
local Enum = {
	KeyCode = {},
	ActuatorRelativeTo = {World = "World"},
	VelocityConstraintMode = {Vector = "Vector"},
	OrientationAlignmentMode = {OneAttachment = "OneAttachment"},
}
local keyItems = {}
for _, name in ipairs({"F", "W", "A", "S", "D", "Q", "E", "LeftShift", "RightShift", "Unknown"}) do
	local key = {Name = name}
	Enum.KeyCode[name] = key
	table.insert(keyItems, key)
end
Enum.KeyCode.GetEnumItems = function() return keyItems end
local Instance = {new = function(className)
	return {ClassName = className, Destroy = function(self) self.Destroyed = true; self.Parent = nil end}
end}
local __Modules = {}
-- @PRODUCTION_MODULES@

local function signal()
	local listeners = {}
	return {
		Connect = function(_self, callback)
			local entry = {Callback = callback, Connected = true}
			function entry:Disconnect() self.Connected = false end
			table.insert(listeners, entry)
			return entry
		end,
		Fire = function(_self, ...)
			for _, entry in ipairs(listeners) do if entry.Connected then entry.Callback(...) end end
		end,
	}
end

local function character(walkSpeed, health)
	local model = {}
	local humanoid = {WalkSpeed = walkSpeed, Health = health, MaxHealth = 100, AutoRotate = true, Parent = model}
	local root = {Position = Vector3.zero, AssemblyLinearVelocity = Vector3.zero, CFrame = {LookVector = vector(0, 0, -1)}, Parent = model, Anchored = false}
	function root:IsA(name) return name == "BasePart" end
	function model:FindFirstChildOfClass(name) return if name == "Humanoid" then humanoid else nil end
	function model:FindFirstChild(name) return if name == "HumanoidRootPart" then root else nil end
	return model, humanoid, root
end

local function context()
	local model, humanoid, root = character(16, 70)
	local values = {
		["Speed.Enabled"] = true, ["Speed.WalkSpeed"] = 24, ["Speed.SprintSpeed"] = 36,
		["Speed.Multiplier"] = 1, ["Speed.Acceleration"] = 8, ["Speed.SprintKey"] = "LeftShift",
		["Flight.Enabled"] = false, ["Flight.Speed"] = 40, ["Flight.VerticalSpeed"] = 30,
		["Flight.Acceleration"] = 8, ["Flight.Boost"] = 1.5, ["Flight.Key"] = "F",
		["Player.ServerGodmode"] = false,
	}
	local diagnostics = {Values = {}, Logs = {}}
	function diagnostics:Set(key, value) self.Values[key] = value end
	function diagnostics:Log(module, status, detail, parameters) table.insert(self.Logs, {Module = module, Status = status, Detail = detail, Parameters = parameters}) end
	local config = {Values = values, Writes = {}}
	function config:Get(path) return self.Values[path] end
	function config:Set(path, value) self.Values[path] = value; table.insert(self.Writes, {Path = path, Value = value}) end
	local input = {InputBegan = signal(), Pressed = {}, Focused = false}
	function input:GetFocusedTextBox() return self.Focused end
	function input:IsKeyDown(key) return self.Pressed[key.Name] == true end
	local bridge = {Available = true, Latest = {Godmode = false, Health = 70, Policy = {MaxWalkSpeed = 80, MaxFlightSpeed = 120, MaxVerticalSpeed = 90}}, Requests = {}}
	function bridge:Request(action, payload, callback)
		table.insert(self.Requests, {Action = action, Payload = payload, Callback = callback})
		return true
	end
	local ctx = {
		Player = {Character = model}, Config = config, Diagnostics = diagnostics, Bridge = bridge,
		Services = {UserInputService = input, Workspace = {CurrentCamera = {CFrame = {LookVector = vector(0, 0, -1)}}}},
		Authorized = true,
	}
	ctx.IsAuthorized = function() return ctx.Authorized end
	return ctx, humanoid, root
end

local Speed = __Modules.SpeedController
local Health = __Modules.HealthDiagnostics
local Flight = __Modules.FlightController
check(Speed ~= nil and Health ~= nil and Flight ~= nil, "Harness inserted real production factories")

do
	local ctx, humanoid = context()
	ctx.Authorized = false
	local module = Speed.new(ctx):Init()
	check(module:Enable() == false, "Speed denies unauthorized enable")
	module:Step(0.1)
	check(humanoid.WalkSpeed == 16 and #ctx.Bridge.Requests == 0, "Denied speed does not mutate or request")
	module:Destroy()
end

do
	local ctx, humanoid = context()
	local module = Speed.new(ctx):Init()
	check(module:Enable() == true, "Authorized speed enables")
	check(#ctx.Bridge.Requests == 1, "Speed enable sends one immediate request")
	module:Step(0.1)
	check(humanoid.WalkSpeed > 16 and humanoid.WalkSpeed < 24, "Speed accelerates using dt")
	ctx.Services.UserInputService.Pressed.LeftShift = true
	module:Step(0.1)
	check(humanoid.WalkSpeed > 24, "Sprint uses configured speed")
	local sprintSpeed = humanoid.WalkSpeed
	ctx.InputCaptured = true
	module:Step(0.1)
	check(humanoid.WalkSpeed < sprintSpeed, "Sprint ignores key held during UI input capture")
	ctx.InputCaptured = false
	local previous, previousHumanoid = ctx.Player.Character, humanoid
	local replacement, newHumanoid = character(12, 80)
	ctx.Player.Character = replacement
	module:Step(0.1)
	check(previousHumanoid.WalkSpeed == 16, "Respawn restores old humanoid baseline")
	check(newHumanoid.WalkSpeed > 12, "Respawn captures and controls new humanoid")
	module:Disable()
	check(newHumanoid.WalkSpeed == 12, "Disable restores new humanoid baseline")
	check(previous ~= replacement, "Test used distinct character identities")
	module:Destroy()
end

do
	local ctx, humanoid = context()
	local module = Speed.new(ctx):Init()
	module:Enable()
	local pending = ctx.Bridge.Requests[1].Callback
	module:Disable()
	local writes = #ctx.Config.Writes
	pending({Ok = false, Reason = "LATE_DENIED"})
	check(#ctx.Config.Writes == writes and humanoid.WalkSpeed == 16, "Late speed enable denial ignored after disable")
	module:Enable()
	local pendingUnload = ctx.Bridge.Requests[#ctx.Bridge.Requests].Callback
	module:Destroy()
	writes = #ctx.Config.Writes
	pendingUnload({Ok = false, Reason = "LATE_DENIED"})
	check(#ctx.Config.Writes == writes and humanoid.WalkSpeed == 16, "Late speed denial ignored after unload")
end

do
	local ctx = context()
	local module = Speed.new(ctx):Init()
	module:Enable()
	ctx.Config.Values["Speed.WalkSpeed"] = 30
	for _ = 1, 10 do module:UpdateConfig("Speed.WalkSpeed") end
	check(#ctx.Bridge.Requests == 1, "Speed slider updates do not request immediately")
	module:Step(0.1); module:Step(0.1)
	check(#ctx.Bridge.Requests == 1, "Speed requests wait for coalescing interval")
	module:Step(0.11)
	check(#ctx.Bridge.Requests == 2, "Coalesced speed update sends one request")
	module:UpdateConfig("Aim.FOV")
	module:Step(0.31)
	check(#ctx.Bridge.Requests == 2, "Unrelated configuration does not send speed update")
	ctx.Authorized = false
	module:Step(0.1)
	check(module.enabled == false, "Speed stops when authorization is revoked")
	module:Destroy()
end

do
	local ctx, humanoid = context()
	local module = Health.new(ctx):Init()
	ctx.Authorized = false
	check(module:Enable() == false, "Health denies unauthorized activation")
	local ok = module:ProbeLocalHealth()
	check(ok == false and humanoid.Health == 70, "Unauthorized local health mutation denied")
	ctx.Authorized = true
	check(module:ProbeLocalHealth() == true and humanoid.Health == 100, "Explicit local probe assigns Health once")
	check(humanoid.MaxHealth == 100, "Health probe preserves MaxHealth")
	module:Disable()
	check(humanoid.Health == 70, "Health disable restores probe baseline")
	module:ProbeLocalHealth()
	humanoid.Health = 55
	module:Disable()
	check(humanoid.Health == 55, "Probe restoration preserves intervening external health update")
	module:Destroy()
end

do
	local ctx, humanoid = context()
	ctx.Config.Values["Player.ServerGodmode"] = true
	local module = Health.new(ctx):Init()
	module:Enable()
	module:Step(0.21)
	check(ctx.Diagnostics.Values.ServerGodmode == false, "Requested godmode is not reported before server ack")
	local request = ctx.Bridge.Requests[1]
	check(request.Action == "Godmode" and request.Payload.Enabled == true, "Health requests server gate explicitly")
	request.Callback({Ok = true, Reason = "OK", Data = {Godmode = true}})
	check(ctx.Diagnostics.Values.ServerGodmode == true, "Godmode reported only from explicit acknowledged state")
	humanoid.Health = 25
	module:Step(0.21); module:Step(0.21)
	check(humanoid.Health == 25 and humanoid.MaxHealth == 100, "Health diagnostics never regenerate or inflate MaxHealth")
	module:Disable()
	request.Callback({Ok = true, Reason = "LATE_OK", Data = {Godmode = true}})
	check(ctx.Diagnostics.Values.ServerGodmode == false, "Late godmode enable ack ignored after disable")
	ctx.Bridge.Latest.Godmode = true -- A previously acknowledged server snapshot remains cached.
	module:Step(0.21)
	check(ctx.Diagnostics.Values.ServerGodmode == false, "Disabled health ignores cached acknowledged protection")
	module:Destroy()
end

do
	local ctx = context()
	ctx.Config.Values["Player.ServerGodmode"] = true
	local module = Health.new(ctx):Init()
	module:Enable()
	local pending = ctx.Bridge.Requests[1].Callback
	ctx.Bridge.Available = false
	module:Disable()
	pending({Ok = true, Reason = "LATE_OK", Data = {Godmode = true}})
	check(ctx.Diagnostics.Values.ServerGodmode == false, "Late health ack ignored after bridge loss and disable")
	module:Destroy()
end

do
	local ctx = context()
	ctx.Config.Values["Player.ServerGodmode"] = true
	local module = Health.new(ctx):Init()
	module:Enable()
	local pending = ctx.Bridge.Requests[1].Callback
	module:Destroy()
	pending({Ok = true, Reason = "LATE_OK", Data = {Godmode = true}})
	check(ctx.Diagnostics.Values.ServerGodmode == false, "Unloaded health ignores delayed enable acknowledgement")
end

do
	local ctx = context()
	ctx.Config.Values["Player.ServerGodmode"] = true
	ctx.Bridge.Request = function(self, action, payload, callback)
		table.insert(self.Requests, {Action = action, Payload = payload})
		callback({Ok = false, Reason = "QUEUE_FULL", Data = {Authorized = false}})
		return false, "QUEUE_FULL"
	end
	local module = Health.new(ctx):Init()
	module:Enable()
	check(ctx.Config.Values["Player.ServerGodmode"] == false, "Rejected health enable clears desired server gate")
	check(ctx.Diagnostics.Values.ServerGodmode == false, "Rejected health enable cannot report protection")
	module:Step(0.21); module:Step(0.21)
	check(#ctx.Bridge.Requests == 1, "Rejected health request does not create a retry loop")
	module:Destroy()
end

do
	local ctx, humanoid, root = context()
	ctx.Authorized = false
	local module = Flight.new(ctx):Init()
	check(module:Enable() == false and humanoid.AutoRotate == true, "Flight denies unauthorized activation without mutation")
	ctx.Authorized = true
	check(module:Enable() == true and humanoid.AutoRotate == false, "Flight owns AutoRotate while enabled")
	local linear, orientation, attachment = module.linear, module.orientation, module.attachment
	check(linear.Parent == root and orientation.Parent == root and attachment.Parent == root, "Flight creates owned constraints on character root")
	root.AssemblyLinearVelocity = vector(12, 6, 0)
	module:Disable()
	check(linear.Destroyed and orientation.Destroyed and attachment.Destroyed, "Flight destroys all owned constraints")
	check(humanoid.AutoRotate == true and root.AssemblyLinearVelocity.Magnitude == 0, "Flight restores AutoRotate and stops residual owned motion")
	ctx.InputCaptured = true
	ctx.Services.UserInputService.InputBegan:Fire({KeyCode = Enum.KeyCode.F}, false)
	check(ctx.Config.Values["Flight.Enabled"] == false, "Flight key ignores UI input capture")
	ctx.InputCaptured = false
	ctx.Services.UserInputService.Focused = true
	ctx.Services.UserInputService.InputBegan:Fire({KeyCode = Enum.KeyCode.F}, false)
	check(ctx.Config.Values["Flight.Enabled"] == false, "Flight key ignores focused text input")
	ctx.Services.UserInputService.Focused = false
	ctx.Services.UserInputService.InputBegan:Fire({KeyCode = Enum.KeyCode.F}, false)
	check(ctx.Config.Values["Flight.Enabled"] == true, "Flight key toggles configured state")
	module:Destroy()
	local writes = #ctx.Config.Writes
	ctx.Services.UserInputService.InputBegan:Fire({KeyCode = Enum.KeyCode.F}, false)
	check(#ctx.Config.Writes == writes, "Flight disconnects its input listener on unload")
end

do
	local ctx, originalHumanoid = context()
	local module = Flight.new(ctx):Init()
	module:Enable()
	local oldLinear = module.linear
	local oldCallback = ctx.Bridge.Requests[1].Callback
	local replacement, replacementHumanoid, replacementRoot = character(14, 80)
	ctx.Player.Character = replacement
	module:Step(0.1)
	check(oldLinear.Destroyed and originalHumanoid.AutoRotate == true, "Flight respawn releases old character constraints and state")
	check(module.linear.Parent == replacementRoot and replacementHumanoid.AutoRotate == false, "Flight respawn attaches to the new character")
	local writes = #ctx.Config.Writes
	oldCallback({Ok = false, Reason = "CHARACTER_CHANGED"})
	check(module.enabled and #ctx.Config.Writes == writes, "Flight ignores delayed denial for old character generation")
	ctx.InputCaptured = true
	ctx.Services.UserInputService.Pressed.W = true
	module:Step(0.1)
	check(module.velocity.Magnitude == 0, "Flight ignores movement keys during UI capture")
	module:Disable()
	check(replacementHumanoid.AutoRotate == true, "Flight restores replacement character state")
	module:Destroy()
end

print("PASS movement.spec: " .. tostring(assertions) .. " assertions; boundary doubles only, no physics or replication")
