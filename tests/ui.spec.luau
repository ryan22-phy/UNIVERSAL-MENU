-- Logic-only GUI/input mocks. This does not validate Roblox rendering or replication.
local uiFactory = require("../src/shared/UIManager")
local Config = require("../src/shared/ConfigManager")(function() error("unexpected import") end)
local Cleanup = require("../src/shared/CleanupManager")(function() error("unexpected import") end)

local checks = 0
local function check(condition, message)
	checks += 1
	assert(condition, message)
end

local function signal()
	local listeners = {}
	return {
		Connect = function(_, callback)
			local token = { Callback = callback, Connected = true }
			table.insert(listeners, token)
			function token:Disconnect() self.Connected = false end
			token.Destroy = token.Disconnect
			return token
		end,
		Fire = function(_, ...)
			for _, token in ipairs(listeners) do if token.Connected then token.Callback(...) end end
		end,
	}
end

local enum = setmetatable({}, {
	__index = function(group, groupName)
		local items = setmetatable({}, {
			__index = function(container, name)
				local item = { Name = name }
				rawset(container, name, item)
				return item
			end,
		})
		rawset(group, groupName, items)
		return items
	end,
})
local vector = {}
local vectorMeta = {
	__mul = function(a, b) return vector.new(a.X * b, a.Y * b) end,
	__sub = function(a, b) return vector.new(a.X - b.X, a.Y - b.Y) end,
	__eq = function(a, b) return a.X == b.X and a.Y == b.Y end,
}
function vector.new(x, y) return setmetatable({ X = x, Y = y }, vectorMeta) end
local dim2 = {}
function dim2.new(xs, xo, ys, yo) return { X = { Scale = xs, Offset = xo }, Y = { Scale = ys, Offset = yo } } end
function dim2.fromOffset(x, y) return dim2.new(0, x, 0, y) end
function dim2.fromScale(x, y) return dim2.new(x, 0, y, 0) end

local fakeInstance = {}
function fakeInstance.new(className)
	local instance = { ClassName = className, Name = className, Children = {}, Visible = true }
	for _, event in ipairs({ "MouseEnter", "MouseLeave", "Activated", "InputBegan", "SelectionGained", "SelectionLost", "FocusLost" }) do
		instance[event] = signal()
	end
	function instance:GetChildren() return self.Children end
	function instance:IsA(name)
		if name == "GuiObject" then return self.ClassName ~= "UIListLayout" and self.ClassName ~= "UIPadding" and self.ClassName ~= "UIStroke" and self.ClassName ~= "UICorner" and self.ClassName ~= "UIScale" end
		return self.ClassName == name
	end
	function instance:IsFocused() return false end
	function instance:Destroy()
		self.Destroyed = true
		for _, child in ipairs(self.Children) do child:Destroy() end
	end
	return setmetatable(instance, {
		__index = function(self, key)
			for _, child in ipairs(self.Children) do if child.Name == key then return child end end
			return nil
		end,
		__newindex = function(self, key, value)
			rawset(self, key, value)
			if key == "Parent" and value then table.insert(value.Children, self) end
		end,
	})
end
local env = setmetatable({
	Color3 = { fromRGB = function(r, g, b) return string.format("%d,%d,%d", r, g, b) end },
	Enum = enum, Instance = fakeInstance, UDim2 = dim2,
	UDim = { new = function(scale, offset) return { Scale = scale, Offset = offset } end },
	Vector2 = vector,
}, { __index = getfenv() })
setfenv(uiFactory, env)
local UI = uiFactory(function(path)
	check(path == "shared/CleanupManager", "UI must only import its cleanup dependency")
	return Cleanup
end)

local config = Config.new()
local input = {
	InputBegan = signal(), InputChanged = signal(), InputEnded = signal(), WindowFocusReleased = signal(),
	Focused = nil,
	GetFocusedTextBox = function(self) return self.Focused end,
}
local authorized = false
local bridge = { Available = false }
local actions = { Damage = 0, Probe = 0, Import = 0 }
local profiles = {}
local gui = fakeInstance.new("ScreenGui")
gui.AbsoluteSize = vector.new(1280, 720)
local camera = { ViewportSize = vector.new(1280, 720) }
local diag = {
	Snapshot = function() return { Values = { ["Flight.CorrectionSuspected"] = false }, Events = { { Module = "Test", Status = "info", Detail = "ready" } } } end,
	Log = function() end,
}
local ctx = {
	Config = config, Gui = gui, IsAuthorized = function() return authorized end,
	Bridge = bridge, Diagnostics = diag,
	Services = {
		Workspace = { CurrentCamera = camera }, UserInputService = input,
		HttpService = { JSONEncode = function() return "{}" end },
	},
	Actions = {
		RequestDamage = function() actions.Damage += 1 return true end,
		ProbeHealth = function() actions.Probe += 1 return true end,
		Export = function() return "{\"Aim.Enabled\":false}" end,
		Import = function(json) actions.Import += 1 return json == "{}", "invalid json" end,
		SaveProfile = function(name) profiles[name] = config:Snapshot() return true end,
		LoadProfile = function(name) return config:Import(profiles[name]) end,
		Reset = function() config:Reset() return true end,
	},
}
local ui = UI.new(ctx)
ui:Init()
check(ui.Initialized and ui.Window ~= nil, "Init must construct the menu")
local window = ui.Window
ui:Init()
check(ui.Window == window, "Init must be idempotent")
for path in pairs(config:Schema()) do check(ui.Bindings[path] ~= nil, "missing UI binding: " .. path) end
local pageCount = 0
for _ in pairs(ui.Pages) do pageCount += 1 end
check(pageCount == 6, "all six pages must exist")
check(ui.Authorization.Text:find("BLOQUEADO") ~= nil, "locked mode must be explicit")
check(ui.Connection.Text:find("AUSENTE") ~= nil, "missing server must be explicit")

local function descendants(root)
	local items = {}
	local function visit(parent)
		for _, child in ipairs(parent.Children) do table.insert(items, child) visit(child) end
	end
	visit(root)
	return items
end
local function find(predicate, root)
	for _, item in ipairs(descendants(root or window)) do if predicate(item) then return item end end
	error("test control was not found")
end
local function button(value, root) return find(function(item) return item.ClassName == "TextButton" and item.Text == value end, root) end
local function key(name)
	return { UserInputType = enum.UserInputType.Keyboard, KeyCode = enum.KeyCode[name] }
end
local left, right = key("LeftControl"), key("RightControl")
input.InputBegan:Fire(left, false)
check(not ui.Open, "CTRL closes the window")
input.InputBegan:Fire(left, false)
check(not ui.Open, "repeated press must not toggle")
input.InputBegan:Fire(right, false)
check(not ui.Open, "second CTRL while one held must not toggle")
input.InputEnded:Fire(left)
input.InputEnded:Fire(right)
input.InputBegan:Fire(right, true)
check(ui.Open, "right CTRL must open even when Roblox marks input processed")
input.InputEnded:Fire(right)
input.Focused = {}
input.InputBegan:Fire(left, false)
check(ui.Open, "CTRL must be ignored while editing a TextBox")
input.InputEnded:Fire(left)
input.Focused = nil

local aimRow = find(function(item) return item.Name == "Tecla de mira" end)
button("MouseButton2", aimRow).Activated:Fire()
check(ctx.InputCaptured == true, "capture must claim input ownership")
input.InputBegan:Fire(left, false)
check(ui.Capture ~= nil and ui.Open, "CTRL is reserved during feature key capture")
input.InputBegan:Fire(key("F"), false)
check(ui.Capture ~= nil, "conflicting Flight shortcut must be rejected")
input.InputBegan:Fire(key("G"), false)
check(config:Get("Aim.Key") == "G" and not ctx.InputCaptured, "valid capture must set config and release input")
button("G", aimRow).Activated:Fire()
input.InputBegan:Fire(key("Escape"), false)
check(ui.Capture == nil and config:Get("Aim.Key") == "G", "Escape cancels without changing the bind")

local fovRow = find(function(item) return item.Name == "Campo de visão · px" end)
local fovField = find(function(item) return item.ClassName == "TextBox" end, fovRow)
fovField.Text = "999"
fovField.FocusLost:Fire()
check(config:Get("Aim.FOV") == config:Schema()["Aim.FOV"].Max, "numeric field must clamp to schema max")
fovField.Text = "nan"
fovField.FocusLost:Fire()
check(config:Get("Aim.FOV") == 400 and ui.StatusError, "invalid numeric entry must preserve prior config and report error")
local modeRow = find(function(item) return item.Name == "Modo de ativação" end)
button("Hold   ▾", modeRow).Activated:Fire()
button("Toggle", modeRow).Activated:Fire()
check(config:Get("Aim.Mode") == "Toggle", "dropdown selection must update config")

button("Solicitar teste de dano no servidor").Activated:Fire()
check(actions.Damage == 0 and ui.StatusError, "server actions must not run while locked")
button("Executar probe de saúde · LOCAL").Activated:Fire()
check(actions.Probe == 1, "local health probe remains available in diagnostic mode")
authorized, bridge.Available = true, true
button("Solicitar teste de dano no servidor").Activated:Fire()
check(actions.Damage == 1, "authorized server action must route to its callback")
button("Exportar para o campo").Activated:Fire()
check(ui.JSONField.Text == "{\"Aim.Enabled\":false}", "export must populate editable JSON field")
ui.JSONField.Text = "bad"
button("Importar do campo").Activated:Fire()
check(ui.StatusError and actions.Import == 1, "import errors must be surfaced")
ui.JSONField.Text = "{}"
button("Importar do campo").Activated:Fire()
check(not ui.StatusError and actions.Import == 2, "valid import must route and refresh")
button("Salvar").Activated:Fire()
config:Set("Aim.FOV", 123)
button("Carregar").Activated:Fire()
check(config:Get("Aim.FOV") == 400, "in-memory profile must restore saved values")

camera.ViewportSize = vector.new(360, 640)
ui.Window.Position = dim2.fromOffset(9000, -9000)
for _ = 1, 31 do ui:Step(1 / 60) end
check(math.abs(ui.FPS - 60) < 0.01, "FPS must derive from actual Step samples")
check(ui.UIScale.Scale * 780 <= 344.001, "small viewport scale must keep full width reachable")
check(ui.Window.Position.X.Offset >= 0 and ui.Window.Position.Y.Offset >= 0, "window drag bounds must stay on screen")
check(ui.Window.Position.X.Offset + 780 * ui.UIScale.Scale <= 360.001, "window must be clamped to viewport")
check(ui.DiagnosticValues.Text:find("Flight.CorrectionSuspected") ~= nil, "module snapshot values must be shown")
check(ui.DiagnosticEvents.Text:find("ready") ~= nil, "module events must be shown")
ui:Disable()
check(not window.Visible, "Disable must hide the menu")
ui:Enable()
check(window.Visible, "Enable must reopen the menu")
ui:Destroy()
ui:Destroy()
check(window.Destroyed and ui.Window == nil, "Destroy must be idempotent and remove owned GUI")
check(ctx.InputCaptured == false, "Destroy must release input ownership")
local state = ui.Open
input.InputBegan:Fire(left, false)
check(ui.Open == state, "input listeners must disconnect on Destroy")
print(string.format("ui.spec: %d logic checks passed (mock GUI; no rendering validation)", checks))
