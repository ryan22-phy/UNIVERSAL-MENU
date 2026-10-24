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
	function instance:GetPropertyChangedSignal(property)
		self.PropertySignals = self.PropertySignals or {}
		self.PropertySignals[property] = self.PropertySignals[property] or signal()
		return self.PropertySignals[property]
	end
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
	Snapshot = function() return { Values = { ["Flight.CorrectionSuspected"] = false, ["Aim.Status"]="MODULE READY", ["ESP.Status"]="DISABLED", ["Adapter.Name"]="GenericRobloxAdapter", ["Aim.TargetPart"]="Head", ["Aim.StabilityDeg"]=0.5, ["ESP.VisualObjects"]=12, ["Timing.AimMs"]=0.2 }, Events = { { Module = "Test", Status = "info", Detail = "ready" } } } end,
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
		ListProfiles = function() local names = {} for name in pairs(profiles) do table.insert(names,name) end return names end,
		ApplyPreset = function(name) actions.Preset = (actions.Preset or 0)+1 return config:ApplyPreset(name) end,
		LoadProfile = function(name) return config:Import(profiles[name]) end,
		Reset = function() config:Reset() return true end,
	},
}
local ui = UI.new(ctx)
ctx.Actions.Unload = function() actions.Unload = (actions.Unload or 0) + 1 ui:Destroy() end
ui:Init()
check(ui.Initialized and ui.Window ~= nil, "Init must construct the menu")
check(not authorized and ui.Open and ui.Window.Visible, "public menu must start visible without laboratory authorization")
local window = ui.Window
ui:Init()
check(ui.Window == window, "Init must be idempotent")
for path in pairs(config:Schema()) do check(ui.Bindings[path] ~= nil, "missing UI binding: " .. path) end
local pageCount = 0
for _ in pairs(ui.Pages) do pageCount += 1 end
check(pageCount == 6, "all six pages must exist")
check(ui.Authorization.Text:find("INTERFACE PÚBLICA") ~= nil and ui.Authorization.Text:find("LAB BLOQUEADO") ~= nil, "feature lock must not imply the public UI is locked")
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
check(find(function(item) return item.Text == "Interface pública; ações do laboratório exigem autorização" end) ~= nil, "visible menu must explain public access and private laboratory actions")
ui.Tabs.Settings.Activated:Fire()
check(ui.ActivePage == "Settings" and ui.Pages.Settings.Visible and not ui.Pages.Combat.Visible, "public navigation must work without authorization")
config:Set("Aim.FOV", 200)
button("Restaurar configuração de fábrica").Activated:Fire()
check(config:Get("Aim.FOV") == 120, "public reset must work without authorization")
ui.Tabs.Diagnostics.Activated:Fire()
check(ui.ActivePage == "Diagnostics" and ui.Pages.Diagnostics.Visible, "Diagnostics must remain public")
ui.Tabs.Combat.Activated:Fire()
button("×").Activated:Fire()
check(not window.Visible and not window.Destroyed, "close button must hide the existing window")
ui:Show()
check(ui.Window == window and window.Visible and ui.Open, "public Show must reopen the same window without authorization")
ui:Hide()
check(not window.Visible, "public Hide must hide the menu")
ui:Show()
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
check(not authorized and config:Get("Aim.Key") == "G" and not ctx.InputCaptured, "public keybind capture must set config and release input without authorization")
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


check(ui.Brand.Text == "VW MENU", "V4 brand header")
check(find(function(item) return item.Text == "UNIVERSAL EDITION" end) ~= nil, "edition header")
check(find(function(item) return item.Text == "v4.0" end) ~= nil, "version header")
for _, component in ipairs({"ToggleSwitch","ModernSlider","KeybindPicker","ColorPicker","Dropdown","MultiSelect","SearchBox","SectionHeader","StatusIndicator","Tooltip","Notification","ProfileSelector"}) do
    check(type(ui[component]) == "function", "reusable component API: " .. component)
end
local headOnlyRow = find(function(item) return item.Name == "Head Only" end)
button("       OFF", headOnlyRow).Activated:Fire()
check(config:Get("Aim.Fallback") == false, "Head Only inverts the canonical fallback boolean")
button("       ON", headOnlyRow).Activated:Fire()
check(config:Get("Aim.Fallback"), "Head Only off restores fallback")
local fallbackPartRow = find(function(item) return item.Name == "Peça de fallback" end)
button("HumanoidRootPart   ▾", fallbackPartRow).Activated:Fire()
button("UpperTorso", fallbackPartRow).Activated:Fire()
check(config:Get("Aim.FallbackPart") == "UpperTorso", "fallback part dropdown is configured")
local colorRow = find(function(item) return item.Name == "Cor de jogadores" end)
local colorField = find(function(item) return item.Name == "ColorPicker" end, colorRow)
colorField.Text = "#12abEF"; colorField.FocusLost:Fire()
check(config:Get("ESP.PlayerColor") == "12ABEF" and colorField.Text == "#12ABEF", "color field normalizes validated RGB")
local swatch = find(function(item) return item.Name == "ColorSwatch" end, colorRow)
check(swatch.BackgroundColor3 == "18,171,239", "color swatch renders actual RGB")
colorField.Text = "#12345X"; colorField.FocusLost:Fire()
check(config:Get("ESP.PlayerColor") == "12ABEF" and ui.StatusError, "invalid RGB preserves config")
local entitiesRow = find(function(item) return item.Name == "Entidades" end)
button("3 / 3 selecionados   ▾", entitiesRow).Activated:Fire()
button("✓  NPCs", entitiesRow).Activated:Fire()
check(not config:Get("ESP.NPCs") and config:Get("ESP.Players"), "multiselect updates only chosen config path")
local wallsRow = find(function(item) return item.Name == "Visibilidade do overlay" end)
button("Visible Only   ▾", wallsRow).Activated:Fire(); button("Always On Top", wallsRow).Activated:Fire()
check(config:Get("ESP.ThroughWalls") == true, "Always On Top maps to canonical true")
button("Always On Top   ▾", wallsRow).Activated:Fire(); button("Visible Only", wallsRow).Activated:Fire()
check(config:Get("ESP.ThroughWalls") == false, "Visible Only maps to canonical false")
config:Set("ESP.Enabled", true)
local presetRow = find(function(item) return item.Name == "Preset de desempenho" end)
button("Balanced   ▾", presetRow).Activated:Fire(); button("High", presetRow).Activated:Fire()
check(actions.Preset == 1 and config:Get("ESP.MaxElements") == 96 and config:Get("ESP.Skeleton"), "preset UI calls actual atomic action")
check(config:Get("ESP.Enabled"), "preset UI preserves feature enable request")
local themeRow = find(function(item) return item.Name == "Tema" end)
button("Blue   ▾", themeRow).Activated:Fire(); button("Cyan", themeRow).Activated:Fire()
check(ui.Brand.TextColor3 == "103,201,255", "Cyan visibly changes existing window accent")
check(swatch.BackgroundColor3 == "18,171,239", "UI theme preserves configured ESP colors")
config:Set("Settings.Theme", "Blue")
check(ui.Brand.TextColor3 == "38,139,255", "Blue restores window accent")
ui.SearchField.Text = "esqueleto"; ui.SearchField:GetPropertyChangedSignal("Text"):Fire()
check(find(function(item) return item.Name == "Esqueleto" end).Visible, "search keeps matching rows")
check(not find(function(item) return item.Name == "Caixas" end).Visible, "search filters nonmatching rows")
check(ui.Tabs.Visuals.Visible, "search never hides navigation")
ui.SearchField.Text = ""; ui.SearchField:GetPropertyChangedSignal("Text"):Fire()
check(find(function(item) return item.Name == "Caixas" end).Visible, "clearing search restores rows")
profiles["Zeta profile"] = config:Snapshot()
profiles["Alpha profile"] = config:Snapshot()
local profileRow = find(function(item) return item.Name == "Perfis disponíveis" end)
button("Selecionar perfil   ▾", profileRow).Activated:Fire()
button("Alpha profile", profileRow).Activated:Fire()
check(ui.ProfileName.Text == "Alpha profile", "profile selector uses actual listed session names")
config:Set("Aim.FOV", 222); button("Carregar").Activated:Fire()
check(config:Get("Aim.FOV") == 400, "selected profile loads the actual saved snapshot")
local profileButtons = #profileRow:GetChildren()
for _=1,5 do button("Alpha profile   ▾",profileRow).Activated:Fire(); button("Alpha profile   ▾",profileRow).Activated:Fire() end
check(#profileRow:GetChildren() == profileButtons, "profile reopening reuses option controls")
for index=1,8 do ui:_status("bounded notification " .. index) end
check(#ui.Notifications == 3, "notifications retain at most three frames")
ui:Step(4)
check(#ui.Notifications == 0, "notifications expire through owned Step lifecycle")
check(ui.DiagnosticValues.Text:find("Adapter.Name") and ui.DiagnosticValues.Text:find("Timing.AimMs"), "new diagnostics render actual snapshot keys")
check(ui.DiagnosticSummary.Text:find("Solicitado:") ~= nil, "diagnostics distinguish requested config from effective status")
check(find(function(item) return item.Text == "MODULE READY" end) ~= nil, "status indicator uses actual module state")

camera.ViewportSize = vector.new(360, 640)
ui.Window.Position = dim2.fromOffset(9000, -9000)
for _ = 1, 31 do ui:Step(1 / 60) end
check(math.abs(ui.FPS - 60) < 0.01, "FPS must derive from actual Step samples")
check(ui.UIScale.Scale * 780 <= 344.001, "small viewport scale must keep full width reachable")
check(ui.Window.Position.X.Offset >= 0 and ui.Window.Position.Y.Offset >= 0, "window drag bounds must stay on screen")
check(ui.Window.Position.X.Offset + 780 * ui.UIScale.Scale <= 360.001, "window must be clamped to viewport")
check(ui.DiagnosticValues.Text:find("Flight.CorrectionSuspected") ~= nil, "module snapshot values must be shown")
check(ui.DiagnosticEvents.Text:find("ready") ~= nil, "module events must be shown")
camera.ViewportSize = vector.new(32, 24)
ui:_fit()
check(ui.UIScale.Scale * 780 <= 32 and ui.UIScale.Scale * 510 <= 24, "very small viewports must not overflow the scale floor")
ui:Disable()
check(not window.Visible, "Disable must hide the menu")
ui:Enable()
check(window.Visible, "Enable must reopen the menu")
button("Descarregar VW MENU").Activated:Fire()
check(actions.Unload == 1, "Settings unload must call the runtime unload action")
ui:Destroy()
ui:Destroy()
check(window.Destroyed and ui.Window == nil, "Destroy must be idempotent and remove owned GUI")
check(ctx.InputCaptured == false, "Destroy must release input ownership")
check(ui.SearchField == nil and ui.ProfileName == nil and next(ui.ModuleIndicators) == nil and #ui.Notifications == 0, "Destroy releases new owned GUI references and status closures")
local state = ui.Open
input.InputBegan:Fire(left, false)
check(ui.Open == state, "input listeners must disconnect on Destroy")
local fallbackGui = fakeInstance.new("ScreenGui")
fallbackGui.AbsoluteSize = vector.new(800, 600)
local fallbackConfig = Config.new()
local fallback = UI.new({
	Gui = fallbackGui, Config = fallbackConfig, Services = ctx.Services,
	IsAuthorized = function() error("optional policy unavailable") end,
	Actions = { Reset = function() return fallbackConfig:Reset() end },
})
fallback:Show()
check(fallback.Initialized and fallback.Window.Visible, "missing feature modules, bridge, diagnostics and failed policy must not block public Show")
fallback.Tabs.Diagnostics.Activated:Fire()
check(fallback.Pages.Diagnostics.Visible and fallback.DiagnosticValues.Text == "Snapshot de diagnóstico indisponível.", "Diagnostics navigation must survive absent optional diagnostics")
button("Solicitar teste de dano no servidor", fallback.Window).Activated:Fire()
check(fallback.StatusError, "private server actions must remain locked with no policy or bridge")
fallbackConfig:Set("Aim.FOV", 180)
button("Restaurar configuração de fábrica", fallback.Window).Activated:Fire()
check(fallbackConfig:Get("Aim.FOV") == 120, "public controls must stay usable after optional capability failures")
local fallbackPresetRow = find(function(item) return item.Name == "Preset de desempenho" end, fallback.Window)
button("Balanced   ▾", fallbackPresetRow).Activated:Fire(); button("Low", fallbackPresetRow).Activated:Fire()
check(fallbackConfig:Get("ESP.MaxElements") == 24, "preset control falls back to real config API when action wrapper is absent")
button("Selecionar perfil   ▾", fallback.Window).Activated:Fire()
check(fallback.StatusError and fallback.Open, "missing profile action is explicit and leaves public UI usable")
fallback:Destroy()

-- Optional TweenService transitions use bounded per-property ownership.
env.TweenInfo = { new=function(duration, style, direction) return { Time=duration, Style=style, Direction=direction } end }
local tweenService = { Tweens={}, FailCreate=false, FailPlay=false }
function tweenService:Create(control, info, goals)
    if self.FailCreate then error("mock Create failure") end
    local tween = { Completed=signal(), Control=control, Info=info, Goals=goals }
    function tween:Play()
        if tweenService.FailPlay then error("mock Play failure") end
        self.Played = true
    end
    function tween:Cancel() self.Cancelled=true self.Completed:Fire(enum.PlaybackState.Cancelled) end
    function tween:Destroy() self.Destroyed=true end
    function tween:Complete()
        for property, value in pairs(self.Goals) do self.Control[property] = value end
        self.Completed:Fire(enum.PlaybackState.Completed)
    end
    table.insert(self.Tweens,tween)
    return tween
end
local animatedGui = fakeInstance.new("ScreenGui")
animatedGui.AbsoluteSize = vector.new(1280,720)
local animatedConfig = Config.new()
local animatedServices = table.clone(ctx.Services)
animatedServices.TweenService = tweenService
local animated = UI.new({ Gui=animatedGui, Config=animatedConfig, Services=animatedServices })
animated:Init()
check(animated.Initialized and #tweenService.Tweens == 0, "optional animation service does not tween initial construction")
local animatedAimRow = find(function(item) return item.Name == "Aim assist" end, animated.Window)
local animatedSwitch = button("       OFF", animatedAimRow)
local animatedThumb = find(function(item) return item.Name == "SwitchThumb" end, animatedAimRow)
animatedSwitch.Activated:Fire()
check(animatedConfig:Get("Aim.Enabled") and #tweenService.Tweens == 4, "switch changes create exactly one transition per animated property")
check(animatedThumb.Position.X.Offset == 2, "switch thumb waits for native tween progression")
for _, tween in ipairs(tweenService.Tweens) do
    check(tween.Played and tween.Info.Time == 0.10, "native transitions play for 0.10 seconds")
    tween:Complete()
    check(tween.Destroyed, "completed native tween releases its instance")
end
check(next(animated.ActiveTweens) == nil and animatedThumb.Position.X.Offset == 14, "completion clears all active tween ownership")
local animatedOutline = find(function(item) return item.ClassName == "UIStroke" end, animatedSwitch)
local stableCleanupCount = #animated.Cleanup._items
animatedSwitch.MouseEnter:Fire()
local previousTween = tweenService.Tweens[#tweenService.Tweens]
animatedSwitch.MouseLeave:Fire()
check(previousTween.Cancelled and previousTween.Destroyed, "new hover state cancels and releases the previous property tween")
local activeCount=0
for _, properties in pairs(animated.ActiveTweens) do for _ in pairs(properties) do activeCount += 1 end end
check(activeCount == 1, "rapid hover retains only one tween per control/property")
tweenService.Tweens[#tweenService.Tweens]:Complete()
for _=1,20 do
    animatedSwitch.MouseEnter:Fire(); animatedSwitch.MouseLeave:Fire()
    tweenService.Tweens[#tweenService.Tweens]:Complete()
end
check(next(animated.ActiveTweens) == nil and #animated.Cleanup._items == stableCleanupCount, "completed animations do not accumulate cleanup entries")
tweenService.FailCreate=true
animatedSwitch.MouseEnter:Fire()
check(animatedOutline.Color == animated.Colors.Accent and next(animated.ActiveTweens) == nil, "Create failure falls back to direct state")
tweenService.FailCreate=false; tweenService.FailPlay=true
animatedSwitch.MouseLeave:Fire()
local failedTween = tweenService.Tweens[#tweenService.Tweens]
check(animatedOutline.Color == animated.Colors.Line and failedTween.Cancelled and failedTween.Destroyed and next(animated.ActiveTweens) == nil, "Play failure releases tween and applies direct state")
tweenService.FailPlay=false
local savedTweenInfo = env.TweenInfo
env.TweenInfo=nil
animatedSwitch.MouseEnter:Fire()
check(animatedOutline.Color == animated.Colors.Accent and next(animated.ActiveTweens) == nil, "missing TweenInfo does not block direct hover")
env.TweenInfo=savedTweenInfo
local savedEnum=env.Enum
env.Enum=nil
animated:_animate(animatedOutline,{Color=animated.Colors.Line})
check(animatedOutline.Color == animated.Colors.Line and next(animated.ActiveTweens) == nil, "missing animation enum falls back without raising")
env.Enum=savedEnum
animatedSwitch.MouseEnter:Fire()
animatedConfig:Set("Settings.Theme", "Cyan")
check(next(animated.ActiveTweens) == nil and animatedOutline.Color == animated.Colors.Accent, "theme changes settle active animations before recoloring")
animatedSwitch.MouseLeave:Fire()
animated:Hide()
check(next(animated.ActiveTweens) == nil and animatedOutline.Color == animated.Colors.Line, "hiding settles and releases active transitions")
animated:Show()
animatedConfig:Set("Aim.Enabled",false)
local pendingTweens={}
for _, properties in pairs(animated.ActiveTweens) do for _, entry in pairs(properties) do table.insert(pendingTweens,entry.Tween) end end
check(#pendingTweens == 4, "switch transition is active before unload")
animated:Destroy()
for _, tween in ipairs(pendingTweens) do check(tween.Cancelled and tween.Destroyed, "Destroy cancels and destroys every pending transition") end
check(next(animated.ActiveTweens) == nil, "Destroy releases the active tween map")

print(string.format("ui.spec: %d logic checks passed (mock GUI; no rendering validation)", checks))
