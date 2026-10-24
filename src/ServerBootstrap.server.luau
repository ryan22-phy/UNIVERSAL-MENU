-- Install under ServerScriptService.VWMenuLabServer using default.project.json.
local root = script.Parent
local cache = {}
local loading = {}
local import
import = function(name)
	if cache[name] ~= nil then return cache[name] end
	assert(not loading[name], "Circular VWMenuLab server module: " .. name)
	local moduleScript = root
	for segment in string.gmatch(name, "[^/]+") do
		assert(segment ~= "." and segment ~= "..", "Invalid module path")
		moduleScript = moduleScript:FindFirstChild(segment)
		assert(moduleScript ~= nil, "Missing VWMenuLab server module: " .. name)
	end
	assert(moduleScript:IsA("ModuleScript"), "Expected ModuleScript: " .. name)
	loading[name] = true
	local factory = require(moduleScript)
	assert(type(factory) == "function", "Expected module factory: " .. name)
	local result = factory(import)
	loading[name] = nil
	cache[name] = result
	return result
end

local services = {
	Players = game:GetService("Players"),
	RunService = game:GetService("RunService"),
	ReplicatedStorage = game:GetService("ReplicatedStorage"),
	ServerScriptService = game:GetService("ServerScriptService"),
	HttpService = game:GetService("HttpService"),
	Workspace = game:GetService("Workspace"),
}
local service = import("server/ServerTestService").new({Services = services, Game = game, Policy = import("config/ServerPolicy")})
local ok, failure = pcall(function() service:Init() end)
if not ok then
	service:Destroy()
	error("VW MENU LAB server initialization failed: " .. tostring(failure))
end
script.Destroying:Connect(function() service:Destroy() end)
game:BindToClose(function() service:Destroy() end)
