-- Native laboratory menu. Gameplay ownership remains with the feature controllers.
return function(import)
	local CleanupManager = import("shared/CleanupManager")
	local UIManager = {}
	UIManager.__index = UIManager

	local WIDTH, HEIGHT = 780, 510
	local COLORS = {
		Background = Color3.fromRGB(8, 11, 18),
		Sidebar = Color3.fromRGB(13, 20, 34),
		Panel = Color3.fromRGB(19, 29, 46),
		Selected = Color3.fromRGB(20, 50, 82),
		Accent = Color3.fromRGB(38, 139, 255),
		Light = Color3.fromRGB(103, 201, 255),
		Text = Color3.fromRGB(241, 246, 255),
		Muted = Color3.fromRGB(130, 149, 175),
		Line = Color3.fromRGB(36, 53, 76),
		Error = Color3.fromRGB(255, 155, 155),
		Success = Color3.fromRGB(145, 223, 190),
	}
	local PAGES = { "Combat", "Visuals", "Movement", "Player", "Settings", "Diagnostics" }
	local PAGE_INFO = {
		Combat = "Mira assistida · entidades autorizadas do laboratório",
		Visuals = "Overlays nativos · orçamento, alcance e visibilidade",
		Movement = "Movimento local · sujeito às regras do servidor",
		Player = "Saúde e testes controlados · autoridade no servidor",
		Settings = "Configuração, perfis temporários e ciclo de vida",
		Diagnostics = "Telemetria real · atualização a cada 0,5 segundo",
	}
	local KEY_PATHS = { "Aim.Key", "Flight.Key", "Speed.SprintKey", "Settings.MenuKey" }

	local function create(className, properties, parent)
		local instance = Instance.new(className)
		for key, value in pairs(properties) do
			instance[key] = value
		end
		instance.Parent = parent
		return instance
	end

	local function round(value, increment)
		return math.floor(value / increment + 0.5) * increment
	end

	local function finite(value)
		return type(value) == "number" and value == value and math.abs(value) < math.huge
	end

	local function formatNumber(value)
		if not finite(value) then return "—" end
		return string.format("%.3f", value):gsub("0+$", ""):gsub("%.$", "")
	end

	local function text(parent, value, position, size, options)
		local properties = {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = value,
			TextColor3 = COLORS.Text,
			Font = Enum.Font.Gotham,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			Position = position,
			Size = size,
		}
		for key, item in pairs(options or {}) do properties[key] = item end
		return create("TextLabel", properties, parent)
	end

	local function stroke(parent, color)
		return create("UIStroke", { Color = color or COLORS.Line, Thickness = 1 }, parent)
	end

	local function corner(parent, radius)
		create("UICorner", { CornerRadius = UDim.new(0, radius or 4) }, parent)
	end

	function UIManager.new(ctx)
		return setmetatable({
			Ctx = ctx,
			Colors = table.clone(COLORS),
			Notifications = {},
			ActiveTweens = {},
			Cleanup = CleanupManager.new(),
			Bindings = {},
			Pages = {},
			Tabs = {},
			Open = true,
			Initialized = false,
			Destroyed = false,
			Elapsed = 0,
			FrameTime = 0,
			FrameCount = 0,
			FPS = 0,
			HeldMenuKeys = {},
			RequestedScale = 1,
		}, UIManager)
	end

	function UIManager:_connect(signal, callback)
		local connection = signal:Connect(callback)
		self.Cleanup:Add(connection)
		return connection
	end

	function UIManager:_releaseTween(control, property, expected)
		local properties = self.ActiveTweens[control]
		local entry = properties and properties[property]
		if not entry or (expected and entry ~= expected) then return end
		properties[property] = nil
		if next(properties) == nil then self.ActiveTweens[control] = nil end
		if entry.Connection then pcall(function() entry.Connection:Disconnect() end) end
		pcall(function() entry.Tween:Cancel() end)
		pcall(function() entry.Tween:Destroy() end)
	end

	function UIManager:_cancelAnimations(settle)
		for control, properties in pairs(self.ActiveTweens) do
			for property, entry in pairs(properties) do
				if settle then pcall(function() control[property] = entry.Goal end) end
				self:_releaseTween(control, property, entry)
			end
		end
	end

	function UIManager:_animate(control, goals)
		if self.Destroyed then return end
		local service = self.Ctx.Services and self.Ctx.Services.TweenService
		for property, goal in pairs(goals) do
			self:_releaseTween(control, property)
			local ok, tween = pcall(function()
				if not service or type(service.Create) ~= "function" then return nil end
				local info = TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				return service:Create(control, info, { [property] = goal })
			end)
			if not ok or not tween then
				control[property] = goal
			else
				local entry = { Tween=tween, Goal=goal }
				self.ActiveTweens[control] = self.ActiveTweens[control] or {}
				self.ActiveTweens[control][property] = entry
				local played = pcall(function()
					entry.Connection = tween.Completed:Connect(function()
						self:_releaseTween(control, property, entry)
					end)
					tween:Play()
				end)
				if not played then
					self:_releaseTween(control, property, entry)
					control[property] = goal
				end
			end
		end
	end

	function UIManager:_get(path, fallback)
		local ok, value = pcall(self.Ctx.Config.Get, self.Ctx.Config, path)
		if ok and value ~= nil then return value end
		return fallback
	end

	function UIManager:_schema(path)
		local config = self.Ctx.Config
		if type(config.Schema) ~= "function" then return nil end
		local ok, schema = pcall(config.Schema, config)
		return ok and type(schema) == "table" and schema[path] or nil
	end

	function UIManager:_status(message, isError)
		if self.Destroyed then return end
		self.StatusMessage = tostring(message)
		self.StatusError = isError == true
		self:Notification(self.StatusMessage, self.StatusError)
		if self.Feedback then
			self.Feedback.Text = self.StatusMessage
			self.Feedback.TextColor3 = self.StatusError and self.Colors.Error or self.Colors.Muted
		end
	end

	function UIManager:_set(path, value)
		local ok, result, reason = pcall(self.Ctx.Config.Set, self.Ctx.Config, path, value)
		if not ok or result == false then
			self:_status("Configuração recusada: " .. tostring(reason or result), true)
			self:_refresh(path)
			return false
		end
		self:_refresh(path)
		self:_status(path .. " atualizado")
		return true
	end

	function UIManager:_bind(path, refresh)
		self.Bindings[path] = self.Bindings[path] or {}
		table.insert(self.Bindings[path], refresh)
		refresh(self:_get(path))
	end

	function UIManager:_refresh(path)
		for _, refresh in ipairs(self.Bindings[path] or {}) do
			refresh(self:_get(path))
		end
	end

	function UIManager:_hint(control, message)
		self:_connect(control.MouseEnter, function()
			if self.TooltipLabel then
				self.TooltipLabel.Text = message
				self.TooltipLabel.Visible = self.Open
			end
		end)
		self:_connect(control.MouseLeave, function()
			if self.TooltipLabel then self.TooltipLabel.Visible = false end
		end)
		self:_connect(control.SelectionGained, function()
			if self.TooltipLabel then
				self.TooltipLabel.Text = message
				self.TooltipLabel.Visible = self.Open
			end
		end)
		self:_connect(control.SelectionLost, function()
			if self.TooltipLabel then self.TooltipLabel.Visible = false end
		end)
	end

	function UIManager:_button(parent, label, position, size, callback, hint)
		local button = create("TextButton", {
			BackgroundColor3 = self.Colors.Panel,
			BorderSizePixel = 0,
			Text = label,
			TextColor3 = self.Colors.Light,
			TextSize = 12,
			Font = Enum.Font.GothamMedium,
			AutoButtonColor = false,
			Selectable = true,
			Position = position,
			Size = size,
		}, parent)
		corner(button)
		local outline = stroke(button)
		local function focus() self:_animate(outline, { Color=self.Colors.Accent }) end
		local function blur() self:_animate(outline, { Color=self.Colors.Line }) end
		self:_connect(button.MouseEnter, focus)
		self:_connect(button.MouseLeave, blur)
		self:_connect(button.SelectionGained, focus)
		self:_connect(button.SelectionLost, blur)
		self:_connect(button.Activated, function()
			if not self.Destroyed then callback(button) end
		end)
		if hint then self:_hint(button, hint) end
		return button
	end

	function UIManager:_section(page, label)
		local row = create("Frame", {
			Name = "Section", BackgroundTransparency = 1,
			Size = UDim2.new(1, -8, 0, 34),
		}, page)
		text(row, string.upper(label), UDim2.fromOffset(0, 6), UDim2.new(1, 0, 0, 22), {
			TextSize = 10, Font = Enum.Font.GothamBold, TextColor3 = self.Colors.Light,
		})
		create("Frame", {
			BackgroundColor3 = self.Colors.Line, BorderSizePixel = 0,
			Position = UDim2.new(0, 0, 1, -1), Size = UDim2.new(1, 0, 0, 1),
		}, row)
	end

	function UIManager:_note(page, message, isWarning)
		local label = text(page, message, UDim2.fromOffset(0, 0), UDim2.new(1, -8, 0, 0), {
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = isWarning and self.Colors.Light or self.Colors.Muted,
			TextSize = 11,
		})
		create("UIPadding", { PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 7) }, label)
		return label
	end

	function UIManager:_row(page, label, height, hint)
		local row = create("Frame", {
			Name = label, BackgroundTransparency = 1,
			Size = UDim2.new(1, -8, 0, height or 38),
		}, page)
		text(row, label, UDim2.fromOffset(0, 0), UDim2.new(0.52, -8, 0, 36))
		if hint then
			local info = self:_button(row, "i", UDim2.new(0.52, -24, 0, 9), UDim2.fromOffset(18, 18), function()
				self:_status(hint)
			end, hint)
			info.TextSize = 10
		end
		return row
	end

	function UIManager:_toggle(page, path, label, hint, invert)
		local row = self:_row(page, label, 38, hint)
		local button = self:_button(row, "", UDim2.new(1, -92, 0, 4), UDim2.fromOffset(92, 30), function()
			self:_set(path, not self:_get(path, false))
		end, hint or path)
		button.Name = "ToggleSwitch"
		local rail = create("Frame", {
			Name = "SwitchRail", BorderSizePixel = 0, Size = UDim2.fromOffset(28, 16),
			Position = UDim2.fromOffset(7, 7), BackgroundColor3 = self.Colors.Line,
		}, button)
		corner(rail, 8)
		local thumb = create("Frame", {
			Name = "SwitchThumb", BorderSizePixel = 0, Size = UDim2.fromOffset(12, 12),
			Position = UDim2.fromOffset(2, 2), BackgroundColor3 = self.Colors.Muted,
		}, rail)
		corner(thumb, 6)
		local previousEnabled
		self:_bind(path, function(value)
			local enabled = value == true
			if invert then enabled = not enabled end
			button.Text = enabled and "       ON" or "       OFF"
			button.TextColor3 = enabled and self.Colors.Light or self.Colors.Muted
			local buttonGoal = enabled and self.Colors.Selected or self.Colors.Panel
			local railGoal = enabled and self.Colors.Accent or self.Colors.Line
			local thumbGoal = enabled and self.Colors.Text or self.Colors.Muted
			local position = UDim2.fromOffset(enabled and 14 or 2, 2)
			if previousEnabled == nil then
				button.BackgroundColor3, rail.BackgroundColor3 = buttonGoal, railGoal
				thumb.Position, thumb.BackgroundColor3 = position, thumbGoal
			elseif previousEnabled ~= enabled then
				self:_animate(button, { BackgroundColor3=buttonGoal })
				self:_animate(rail, { BackgroundColor3=railGoal })
				self:_animate(thumb, { Position=position, BackgroundColor3=thumbGoal })
			end
			previousEnabled = enabled
		end)
		return row
	end

	function UIManager:_slider(page, path, label, minimum, maximum, increment, hint)
		local rule = self:_schema(path)
		if rule then
			minimum = finite(rule.Min) and rule.Min or minimum
			maximum = finite(rule.Max) and rule.Max or maximum
		end
		local row = self:_row(page, label, 49, hint)
		local field = create("TextBox", {
			Position = UDim2.new(1, -74, 0, 3), Size = UDim2.fromOffset(74, 29),
			BackgroundColor3 = self.Colors.Panel, BorderSizePixel = 0,
			TextColor3 = self.Colors.Light, Font = Enum.Font.GothamMedium,
			TextSize = 12, Text = "", ClearTextOnFocus = false,
		}, row)
		corner(field)
		stroke(field)
		local track = create("TextButton", {
			Position = UDim2.new(0.54, 0, 0, 0), Size = UDim2.new(0.46, -90, 0, 38),
			BackgroundTransparency = 1, BorderSizePixel = 0,
			Text = "", AutoButtonColor = false, Selectable = true,
		}, row)
		local rail = create("Frame", {
			BackgroundColor3 = self.Colors.Line, BorderSizePixel = 0,
			Position = UDim2.new(0, 0, 0.5, -2), Size = UDim2.new(1, 0, 0, 4),
		}, track)
		corner(rail, 2)
		local fill = create("Frame", {
			BackgroundColor3 = self.Colors.Accent, BorderSizePixel = 0,
			Size = UDim2.fromScale(0, 1),
		}, rail)
		corner(fill, 2)
		local thumb = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(10, 10), BackgroundColor3 = self.Colors.Light,
			BorderSizePixel = 0,
		}, rail)
		corner(thumb, 5)
		local function fromPosition(position)
			local width = track.AbsoluteSize.X
			if width <= 0 then return end
			local fraction = math.clamp((position.X - track.AbsolutePosition.X) / width, 0, 1)
			self:_set(path, math.clamp(round(minimum + (maximum - minimum) * fraction, increment), minimum, maximum))
		end
		self:_connect(track.InputBegan, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				self.SliderDrag = { Input = input, Set = fromPosition }
				fromPosition(input.Position)
			end
		end)
		self:_connect(track.SelectionGained, function()
			self.SelectedSlider = { Path = path, Minimum = minimum, Maximum = maximum, Increment = increment }
		end)
		self:_connect(track.SelectionLost, function() self.SelectedSlider = nil end)
		self:_connect(field.FocusLost, function()
			local value = tonumber(field.Text)
			if not finite(value) then
				self:_status("Digite um número finito para " .. label, true)
				self:_refresh(path)
				return
			end
			self:_set(path, math.clamp(round(value, increment), minimum, maximum))
		end)
		self:_bind(path, function(value)
			value = finite(value) and math.clamp(value, minimum, maximum) or minimum
			local fraction = (value - minimum) / (maximum - minimum)
			fill.Size = UDim2.fromScale(fraction, 1)
			thumb.Position = UDim2.fromScale(fraction, 0.5)
			if not field:IsFocused() then field.Text = formatNumber(value) end
		end)
		self:_hint(track, hint or (path .. " · arraste ou use as setas quando selecionado"))
		self:_hint(field, "Digite o valor · intervalo " .. minimum .. " a " .. maximum)
	end

	function UIManager:_dropdown(page, path, label, options, hint)
		local rule = self:_schema(path)
		options = options or (rule and rule.Choices) or {}
		local row = self:_row(page, label, 38, hint)
		local expanded = false
		local items = {}
		local function valueOf(option)
			if type(option) == "table" then return option.Value end
			return option
		end
		local function labelOf(option) return type(option) == "table" and option.Label or tostring(option) end
		local function collapse()
			expanded = false
			row.Size = UDim2.new(1, -8, 0, 38)
			for _, item in ipairs(items) do item.Visible = false end
		end
		local button = self:_button(row, "", UDim2.new(0.54, 0, 0, 3), UDim2.new(0.46, 0, 0, 30), function()
			expanded = not expanded
			row.Size = UDim2.new(1, -8, 0, expanded and (38 + #options * 29) or 38)
			for _, item in ipairs(items) do item.Visible = expanded end
		end, hint or path)
		button.Name = "Dropdown"
		for index, option in ipairs(options) do
			local value = valueOf(option)
			local item = self:_button(row, labelOf(option), UDim2.new(0.54, 0, 0, 37 + (index - 1) * 29), UDim2.new(0.46, 0, 0, 26), function()
				if path == "Settings.Performance" then
					if self.Ctx.Actions and type(self.Ctx.Actions.ApplyPreset) == "function" then
						self:_callAction("ApplyPreset", value)
					elseif type(self.Ctx.Config.ApplyPreset) == "function" then
						local ok, reason = self.Ctx.Config:ApplyPreset(value)
						self:_status(ok and ("Preset aplicado: " .. value) or tostring(reason), not ok)
					end
					self:UpdateConfig()
				else self:_set(path, value) end
				collapse()
			end)
			item.Visible = false
			table.insert(items, item)
		end
		self:_bind(path, function(value)
			local selected = tostring(value or "—")
			for index, item in ipairs(items) do
				local active = valueOf(options[index]) == value
				if active then selected = labelOf(options[index]) end
				item.TextColor3 = active and self.Colors.Light or self.Colors.Muted
				item.BackgroundColor3 = active and self.Colors.Selected or self.Colors.Panel
			end
			button.Text = selected .. "   ▾"
		end)
		return row
	end

	-- Components share this window's bindings, cleanup ownership and theme.
	function UIManager:MultiSelect(page, label, options, hint)
		local row = self:_row(page, label, 38, hint)
		local items, expanded = {}, false
		local button = self:_button(row, "", UDim2.new(0.54, 0, 0, 3), UDim2.new(0.46, 0, 0, 30), function()
			expanded = not expanded
			row.Size = UDim2.new(1, -8, 0, expanded and (38 + #options * 29) or 38)
			for _, item in ipairs(items) do item.Visible = expanded end
		end, hint or "Selecione as categorias que devem ser exibidas.")
		button.Name = "MultiSelect"
		local function refresh()
			local selected = 0
			for index, option in ipairs(options) do
				local enabled = self:_get(option.Path, false)
				if enabled then selected += 1 end
				if items[index] then
					items[index].Text = (enabled and "✓  " or "○  ") .. option.Label
					items[index].TextColor3 = enabled and self.Colors.Light or self.Colors.Muted
				end
			end
			button.Text = selected .. " / " .. #options .. " selecionados   ▾"
		end
		for index, option in ipairs(options) do
			local item = self:_button(row, option.Label, UDim2.new(0.54, 0, 0, 37 + (index - 1) * 29), UDim2.new(0.46, 0, 0, 26), function()
				self:_set(option.Path, not self:_get(option.Path, false))
			end)
			item.Name, item.Visible = option.Path, false
			items[index] = item
			self:_bind(option.Path, refresh)
		end
		refresh()
		return row
	end

	function UIManager:ColorPicker(page, path, label, hint)
		local row = self:_row(page, label, 38, hint)
		local swatch = create("Frame", {
			Name = "ColorSwatch", BorderSizePixel = 0, Position = UDim2.new(0.54, 0, 0, 8), Size = UDim2.fromOffset(20, 20),
		}, row)
		corner(swatch, 3); stroke(swatch)
		local field = create("TextBox", {
			Name = "ColorPicker", BackgroundColor3 = self.Colors.Panel, BorderSizePixel = 0,
			Position = UDim2.new(0.54, 28, 0, 3), Size = UDim2.new(0.46, -28, 0, 30),
			Text = "", TextColor3 = self.Colors.Text, Font = Enum.Font.Code, TextSize = 12,
			ClearTextOnFocus = false, PlaceholderText = "#268BFF", PlaceholderColor3 = self.Colors.Muted,
		}, row)
		corner(field); stroke(field)
		self:_connect(field.FocusLost, function()
			local value = field.Text:gsub("^#", "")
			if #value ~= 6 or not value:match("^[%x]+$") then
				self:_status("Cor inválida: use seis dígitos RGB, como #268BFF.", true)
				self:_refresh(path)
				return
			end
			self:_set(path, string.upper(value))
		end)
		self:_bind(path, function(value)
			if type(value) ~= "string" or not value:match("^%x%x%x%x%x%x$") then return end
			if not field:IsFocused() then field.Text = "#" .. string.upper(value) end
			swatch.BackgroundColor3 = Color3.fromRGB(tonumber(value:sub(1,2),16), tonumber(value:sub(3,4),16), tonumber(value:sub(5,6),16))
		end)
		self:_hint(field, hint or "RGB hexadecimal · seis dígitos; # é opcional.")
		return row
	end

	function UIManager:_filterRows(query)
		query = string.lower(tostring(query or ""))
		local function searchable(node)
			local content = node.Name or ""
			if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then content ..= " " .. node.Text end
			for _, child in ipairs(node:GetChildren()) do content ..= " " .. searchable(child) end
			return content
		end
		for _, page in pairs(self.Pages) do
			for _, child in ipairs(page:GetChildren()) do
				if child:IsA("GuiObject") then
					child.Visible = query == "" or string.find(string.lower(searchable(child)), query, 1, true) ~= nil
				end
			end
		end
	end

	function UIManager:SearchBox(parent)
		local field = create("TextBox", {
			Name = "SearchBox", Position = UDim2.fromOffset(164, 120), Size = UDim2.fromOffset(600, 30),
			BackgroundColor3 = self.Colors.Panel, BorderSizePixel = 0, ClearTextOnFocus = false,
			Text = "", PlaceholderText = "Buscar controles na página…", PlaceholderColor3 = self.Colors.Muted,
			TextColor3 = self.Colors.Text, Font = Enum.Font.Gotham, TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, parent)
		corner(field); stroke(field)
		create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, field)
		self:_connect(field:GetPropertyChangedSignal("Text"), function() self:_filterRows(field.Text) end)
		self:_hint(field, "Filtra os controles por nome, valor ou chave. Apague o texto para mostrar todos.")
		self.SearchField = field
		return field
	end

	function UIManager:StatusIndicator(page, label)
		local row = self:_row(page, label, 38)
		local dot = create("Frame", {
			Name = "StatusDot", Size = UDim2.fromOffset(6,6), Position = UDim2.new(0.54, 0, 0, 15),
			BackgroundColor3 = self.Colors.Muted, BorderSizePixel = 0,
		}, row)
		corner(dot,3)
		local value = text(row, "SEM AMOSTRA", UDim2.new(0.54, 14, 0, 0), UDim2.new(0.46, -14, 0, 36), {
			TextSize = 10, Font = Enum.Font.Code, TextColor3 = self.Colors.Muted, TextTruncate = Enum.TextTruncate.AtEnd,
		})
		return function(message)
			value.Text = message == nil and "SEM AMOSTRA" or tostring(message)
			local status = string.upper(value.Text)
			local color = status:find("ERROR",1,true) and self.Colors.Error
				or (status:find("READY",1,true) and self.Colors.Success)
				or (status:find("RESTRICTION",1,true) and self.Colors.Light) or self.Colors.Muted
			dot.BackgroundColor3, value.TextColor3 = color, color
		end
	end

	function UIManager:Notification(message, isError)
		if not self.Window or self.Destroyed then return end
		local latest = self.Notifications[#self.Notifications]
		if latest and latest.Message == message then latest.Remaining = 3 return end
		if #self.Notifications >= 3 then table.remove(self.Notifications, 1).Frame:Destroy() end
		local frame = create("Frame", {
			Name = "Notification", BackgroundColor3 = self.Colors.Sidebar, BorderSizePixel = 0,
			Size = UDim2.fromOffset(310, 42), ZIndex = 40, Visible = self.Open,
		}, self.Window)
		corner(frame); stroke(frame, isError and self.Colors.Error or self.Colors.Line)
		text(frame, tostring(message):sub(1,160), UDim2.fromOffset(10,5), UDim2.new(1,-20,1,-10), {
			TextSize = 10, TextWrapped = true, TextColor3 = isError and self.Colors.Error or self.Colors.Text, ZIndex = 41,
		})
		table.insert(self.Notifications, { Frame=frame, Message=message, Remaining=3 })
		self:_layoutNotifications()
	end

	function UIManager:_layoutNotifications()
		for index, item in ipairs(self.Notifications) do
			item.Frame.Position = UDim2.fromOffset(WIDTH - 326, 160 + (index-1)*48)
			item.Frame.Visible = self.Open
		end
	end

	function UIManager:_applyTheme()
		self:_cancelAnimations(true)
		local previous = self.Colors
		local nextColors = table.clone(COLORS)
		if self:_get("Settings.Theme", "Blue") == "Cyan" then
			nextColors.Accent = COLORS.Light
			nextColors.Light = Color3.fromRGB(156, 225, 255)
			nextColors.Selected = Color3.fromRGB(18, 53, 64)
		end
		local function recolor(node)
			-- Swatches encode configured ESP colors and must never inherit the UI theme.
			if node.Name ~= "ColorSwatch" then
				local properties = {}
				if node:IsA("GuiObject") then table.insert(properties, "BackgroundColor3") end
				if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then table.insert(properties, "TextColor3") end
				if node:IsA("TextBox") then table.insert(properties, "PlaceholderColor3") end
				if node:IsA("ScrollingFrame") then table.insert(properties, "ScrollBarImageColor3") end
				if node:IsA("UIStroke") then table.insert(properties, "Color") end
				for _, property in ipairs(properties) do
					for name, color in pairs(previous) do
						if node[property] == color then node[property] = nextColors[name] break end
					end
				end
			end
			for _, child in ipairs(node:GetChildren()) do recolor(child) end
		end
		if self.Window then recolor(self.Window) end
		self.Colors = nextColors
	end

	function UIManager:ProfileSelector(page, profileName)
		local row = self:_row(page, "Perfis disponíveis", 38)
		local items, expanded = {}, false
		local selector
		local function close()
			expanded = false
			row.Size = UDim2.new(1, -8, 0, 38)
			for _, item in ipairs(items) do item.Visible = false end
		end
		selector = self:_button(row, "Selecionar perfil   ▾", UDim2.new(0.54,0,0,3), UDim2.new(0.46,0,0,30), function()
			if expanded then close() return end
			local action = self.Ctx.Actions and self.Ctx.Actions.ListProfiles
			if type(action) ~= "function" then self:_status("Lista de perfis indisponível neste ambiente.", true) return end
			local ok, names = pcall(action)
			if not ok or type(names) ~= "table" then self:_status("Falha ao listar os perfis da sessão.", true) return end
			local sorted = {}
			for _, name in ipairs(names) do if type(name) == "string" then table.insert(sorted,name) end end
			table.sort(sorted)
			if #sorted == 0 then self:_status("Nenhum perfil salvo nesta sessão.") return end
			expanded = true
			row.Size = UDim2.new(1,-8,0,38 + #sorted*29)
			for index, name in ipairs(sorted) do
				if not items[index] then
					local item
					item = self:_button(row, "", UDim2.new(0.54,0,0,37+(index-1)*29), UDim2.new(0.46,0,0,26), function()
						profileName.Text = item.Text
						selector.Text = item.Text .. "   ▾"
						close()
						self:_status("Perfil selecionado: " .. item.Text .. " · clique Carregar para aplicar")
					end)
					items[index] = item
				end
				items[index].Text, items[index].Visible = name, true
			end
		end, "Lista os nomes reais dos perfis salvos nesta sessão.")
		selector.Name = "ProfileSelector"
		return row
	end

	function UIManager:_cancelCapture()
		local previous = self.Capture
		self.Capture = nil
		self.Ctx.InputCaptured = false
		if previous then self:_refresh(previous.Path) end
	end

	function UIManager:_keybind(page, path, label, hint)
		local row = self:_row(page, label, 38, hint)
		local button
		button = self:_button(row, "", UDim2.new(0.54, 0, 0, 3), UDim2.new(0.46, 0, 0, 30), function()
			self:_cancelCapture()
			self.Capture = { Path = path, Button = button }
			self.Ctx.InputCaptured = true
			button.Text = "Pressione uma tecla…"
			button.TextColor3 = self.Colors.Accent
			self:_status("Esc cancela · CTRL fica reservado ao menu")
		end, hint or "Clique para capturar uma tecla. Esc cancela; atalhos duplicados são recusados.")
		self:_bind(path, function(value)
			if self.Capture and self.Capture.Path == path then return end
			button.Text = tostring(value or "—")
			button.TextColor3 = self.Colors.Light
		end)
	end

	function UIManager:_action(page, label, action, description, requiresServer)
		local row = create("Frame", {
			BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 66),
		}, page)
		self:_button(row, label, UDim2.fromOffset(0, 3), UDim2.new(1, 0, 0, 30), function()
			if requiresServer and (not self:_authorized() or not self:_serverAvailable()) then
				self:_status("Ação bloqueada: exige autorização e serviço de teste no servidor.", true)
				return
			end
			self:_callAction(action)
		end, description)
		text(row, description, UDim2.fromOffset(0, 38), UDim2.new(1, 0, 0, 25), {
			TextColor3 = self.Colors.Muted, TextSize = 10, TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
	end

	function UIManager:_callAction(name, ...)
		local action = self.Ctx.Actions and self.Ctx.Actions[name]
		if type(action) ~= "function" then
			self:_status("Ação indisponível neste ambiente: " .. name, true)
			return false, "ação indisponível"
		end
		local ok, value, reason = pcall(action, ...)
		if not ok or value == false then
			self:_status("Falha: " .. tostring(reason or value), true)
			if self.Ctx.Diagnostics then
				self.Ctx.Diagnostics:Log("UI", "error", tostring(reason or value), { Action = name })
			end
			return false, tostring(reason or value)
		end
		if not self.Destroyed then self:_status("Solicitação enviada: " .. name .. " · confira Diagnostics") end
		return true, value, reason
	end

	function UIManager:_authorized()
		if type(self.Ctx.IsAuthorized) ~= "function" then return false end
		local ok, allowed = pcall(self.Ctx.IsAuthorized)
		return ok and allowed == true
	end

	function UIManager:_serverAvailable()
		return self.Ctx.Bridge ~= nil and self.Ctx.Bridge.Available == true
	end

	function UIManager:_buildCombat(page)
		self:_section(page, "Assistência de mira")
		self:_toggle(page, "Aim.Enabled", "Aim assist", "Só considera entidades permitidas pelo laboratório e pela política local.")
		self:_dropdown(page, "Aim.Mode", "Modo de ativação", { "Hold", "Toggle" })
		self:_keybind(page, "Aim.Key", "Tecla de mira")
		self:_slider(page, "Aim.FOV", "Campo de visão · px", 20, 400, 1)
		self:_slider(page, "Aim.Smoothness", "Suavização", 1, 40, 0.5)
		self:_slider(page, "Aim.MaxDistance", "Alcance · studs", 10, 5000, 10)
		self:_section(page, "Seleção de alvo")
		self:_dropdown(page, "Aim.Priority", "Prioridade", { "Angle", "Distance" })
		self:_toggle(page, "Aim.VisibilityCheck", "Verificar visibilidade")
		self:_toggle(page, "Aim.TeamCheck", "Verificar equipe")
		self:_toggle(page, "Aim.HeadPriority", "Priorizar cabeça")
		self:_toggle(page, "Aim.Fallback", "Head Only", "Quando ativo, exige Head; desligue para permitir a peça de fallback.", true)
		self:_dropdown(page, "Aim.FallbackPart", "Peça de fallback", nil, "Peça usada quando Head não está disponível e Head Only está desligado.")
		self:_toggle(page, "Aim.TargetLock", "Manter alvo")
		self:_slider(page, "Aim.SwitchDelay", "Intervalo de troca · s", 0, 2, 0.05)
		self:_slider(page, "Aim.Prediction", "Predição · s", 0, 0.5, 0.01)
		self:_toggle(page, "Aim.ShowFOV", "Exibir círculo de FOV")
	end

	function UIManager:_buildVisuals(page)
		self:_section(page, "Overlays de entidades")
		self:_toggle(page, "ESP.Enabled", "ESP")
		self:MultiSelect(page, "Entidades", {
			{ Path="ESP.Players", Label="Jogadores" }, { Path="ESP.NPCs", Label="NPCs" }, { Path="ESP.Items", Label="Itens marcados" },
		})
		self:MultiSelect(page, "Categorias de itens", {
			{ Path="ESP.DroppedItems", Label="Itens no chão" }, { Path="ESP.Loot", Label="Loot" },
			{ Path="ESP.Weapons", Label="Armas" }, { Path="ESP.Tools", Label="Ferramentas" },
			{ Path="ESP.Collectibles", Label="Colecionáveis" }, { Path="ESP.Objectives", Label="Objetivos" }, { Path="ESP.TestObjects", Label="Objetos de teste" },
		})
		self:_section(page, "Informações exibidas")
		for _, item in ipairs({
			{ "Boxes", "Caixas" }, { "Names", "Nomes" }, { "Health", "Vida" },
			{ "Distance", "Distância" }, { "Lines", "Linhas de referência" }, { "Skeleton", "Esqueleto" },
			{ "Highlight", "Highlight" }, { "HeadMarker", "Marcador de cabeça" }, { "TargetIndicator", "Indicador de alvo" },
			{ "TeamIdentification", "Identificação de equipe" }, { "ColorByTeam", "Cores por equipe" }, { "ShowDead", "Exibir mortos" },
		}) do self:_toggle(page, "ESP." .. item[1], item[2]) end
		self:_dropdown(page, "ESP.ThroughWalls", "Visibilidade do overlay", {
			{ Label="Visible Only", Value=false }, { Label="Always On Top", Value=true },
		}, "Visible Only respeita a oclusão; Always On Top exibe o overlay através de obstáculos.")
		self:_section(page, "Cores RGB")
		for _, item in ipairs({ {"PlayerColor","Cor de jogadores"}, {"NPCColor","Cor de NPCs"}, {"ItemColor","Cor de itens"}, {"TargetColor","Cor do alvo"} }) do
			self:ColorPicker(page, "ESP." .. item[1], item[2])
		end
		self:_section(page, "Orçamento de renderização")
		self:_slider(page, "ESP.MaxDistance", "Alcance · studs", 10, 5000, 10)
		self:_slider(page, "ESP.MaxElements", "Limite de elementos", 1, 128, 1)
		self:_slider(page, "ESP.RefreshRate", "Atualização · Hz", 5, 60, 1)
	end

	function UIManager:_buildMovement(page)
		self:_section(page, "Flight")
		self:_toggle(page, "Flight.Enabled", "Ativar voo")
		self:_keybind(page, "Flight.Key", "Alternar voo")
		self:_slider(page, "Flight.Speed", "Velocidade horizontal", 1, 120, 1)
		self:_slider(page, "Flight.VerticalSpeed", "Velocidade vertical", 1, 100, 1)
		self:_slider(page, "Flight.Acceleration", "Aceleração do voo", 1, 25, 0.5)
		self:_slider(page, "Flight.Boost", "Multiplicador de boost", 1, 2, 0.1)
		self:_note(page, "Durante o voo: WASD move, E sobe, Q desce e Shift aplica boost. F alterna o voo por padrão. CTRL abre ou fecha o menu.")
		self:_section(page, "Speed")
		self:_toggle(page, "Speed.Enabled", "Ativar velocidade")
		self:_slider(page, "Speed.WalkSpeed", "Velocidade ao caminhar", 1, 100, 1)
		self:_slider(page, "Speed.SprintSpeed", "Velocidade de sprint", 1, 100, 1)
		self:_slider(page, "Speed.Multiplier", "Multiplicador", 0.25, 2, 0.05)
		self:_slider(page, "Speed.Acceleration", "Aceleração", 1, 25, 0.5)
		self:_keybind(page, "Speed.SprintKey", "Tecla de sprint")
		self:_note(page, "O servidor pode corrigir movimento local. Suspeitas de correção e telemetria confirmada são separadas em Diagnostics.", true)
	end

	function UIManager:_buildPlayer(page)
		self:_section(page, "Saúde com autoridade de servidor")
		self:_toggle(page, "Player.ServerGodmode", "Godmode no servidor", "Pedido ao serviço autorizado. O toggle sozinho não comprova proteção ou invulnerabilidade.")
		self:_note(page, "Disponível apenas quando o serviço de teste privado confirma permissão. Flags do cliente não concedem privilégios no servidor.", true)
		self:_action(page, "Solicitar teste de dano no servidor", "RequestDamage", "Teste controlado, sujeito à permissão, sessão e limites validados no servidor.", true)
		self:_action(page, "Solicitar restauração de saúde", "RequestRestore", "Solicita a restauração pelo serviço do laboratório; confira a confirmação no diagnóstico.", true)
		self:_section(page, "Diagnóstico local")
		self:_action(page, "Executar probe de saúde · LOCAL", "ProbeHealth", "Inspeção apenas local. Não prova invulnerabilidade nem proteção contra dano do servidor.", false)
	end

	function UIManager:_buildSettings(page)
		self:_section(page, "Interface")
		local shortcutRow = self:_row(page, "Atalho do menu", 38, "CTRL esquerdo e direito. Atalho fixo reservado; ignorado enquanto você digita em campos.")
		local shortcut = self:_button(shortcutRow, "CTRL esq. / dir. · fixo", UDim2.new(0.54, 0, 0, 3), UDim2.new(0.46, 0, 0, 30), function()
			self:_status("CTRL esquerdo e direito abrem ou fecham o menu. O atalho é fixo.")
		end)
		self:_bind("Settings.MenuKey", function() shortcut.Text = "CTRL esq. / dir. · fixo" end)
		self:_slider(page, "Settings.Scale", "Escala da interface", 0.65, 1.3, 0.05, "A escala é limitada automaticamente para manter a janela dentro da tela.")
		self:_dropdown(page, "Settings.Theme", "Tema", nil, "Altera o destaque de toda a janela entre Blue e Cyan.")
		self:_dropdown(page, "Settings.Adapter", "Adapter de entidades", nil, "Auto usa o adaptador adequado ao jogo; a seleção efetiva aparece em Diagnostics.")
		self:_dropdown(page, "Settings.Performance", "Preset de desempenho", nil, "Aplica orçamento de ESP e detalhes; preserva os módulos ligados ou desligados.")
		self:_section(page, "Perfis na memória")
		self:_note(page, "Perfis são temporários: existem apenas nesta sessão e somem ao descarregar. Use o JSON abaixo para transportar configurações.")
		local profileRow = create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 39) }, page)
		local profileName = create("TextBox", {
			BackgroundColor3 = self.Colors.Panel, BorderSizePixel = 0, TextColor3 = self.Colors.Text,
			PlaceholderText = "Nome do perfil", PlaceholderColor3 = self.Colors.Muted,
			Text = "Meu perfil", ClearTextOnFocus = false, TextSize = 12, Font = Enum.Font.Gotham,
			Position = UDim2.fromOffset(0, 3), Size = UDim2.new(1, -208, 0, 30),
		}, profileRow)
		self.ProfileName = profileName
		self:ProfileSelector(page, profileName)
		corner(profileName)
		stroke(profileName)
		self:_button(profileRow, "Salvar", UDim2.new(1, -196, 0, 3), UDim2.fromOffset(92, 30), function()
			local ok = self:_callAction("SaveProfile", profileName.Text)
			if ok then self:_status("Perfil salvo apenas na memória: " .. profileName.Text) end
		end, "Salva a configuração atual na memória desta sessão.")
		self:_button(profileRow, "Carregar", UDim2.new(1, -96, 0, 3), UDim2.fromOffset(96, 30), function()
			local ok = self:_callAction("LoadProfile", profileName.Text)
			if ok then self:UpdateConfig() end
		end, "Carrega um perfil desta sessão pelo nome exato.")
		self:_section(page, "Importar / exportar JSON")
		self:_note(page, "Use copiar e colar no campo. Nenhuma API de arquivo ou clipboard é necessária. Importações passam pela validação do ConfigManager.")
		local jsonHolder = create("Frame", {
			BackgroundColor3 = self.Colors.Panel, BorderSizePixel = 0,
			Size = UDim2.new(1, -8, 0, 154), ClipsDescendants = true,
		}, page)
		corner(jsonHolder)
		stroke(jsonHolder)
		local jsonScroll = create("ScrollingFrame", {
			BackgroundTransparency = 1, BorderSizePixel = 0,
			Size = UDim2.new(1, -12, 1, -12), Position = UDim2.fromOffset(6, 6),
			CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 3, ScrollBarImageColor3 = self.Colors.Accent,
			ScrollingDirection = Enum.ScrollingDirection.Y,
		}, jsonHolder)
		self.JSONField = create("TextBox", {
			BackgroundTransparency = 1, BorderSizePixel = 0, ClearTextOnFocus = false,
			MultiLine = true, TextWrapped = true, Text = "", PlaceholderText = "Cole ou exporte o JSON aqui…",
			TextColor3 = self.Colors.Text, PlaceholderColor3 = self.Colors.Muted,
			TextSize = 11, Font = Enum.Font.Code,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(1, -8, 0, 140), AutomaticSize = Enum.AutomaticSize.Y,
		}, jsonScroll)
		local jsonActions = create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 39) }, page)
		self:_button(jsonActions, "Exportar para o campo", UDim2.fromOffset(0, 3), UDim2.new(0.5, -4, 0, 30), function()
			local ok, value = self:_callAction("Export")
			if ok and type(value) == "string" then
				self.JSONField.Text = value
				self:_status("JSON exportado · selecione e copie o conteúdo do campo")
			elseif ok then
				self:_status("A exportação não retornou texto JSON.", true)
			end
		end, "Gera JSON validado no campo editável; copie manualmente.")
		self:_button(jsonActions, "Importar do campo", UDim2.new(0.5, 4, 0, 3), UDim2.new(0.5, -4, 0, 30), function()
			local ok = self:_callAction("Import", self.JSONField.Text)
			if ok then self:UpdateConfig() end
		end, "Valida e aplica o JSON do campo. Erros são exibidos no rodapé.")
		self:_section(page, "Sessão")
		self:_action(page, "Verificar versão", "CheckVersion", "Consulta a verificação de versão configurada pelo laboratório; falhas de rede aparecem no diagnóstico.")
		self:_action(page, "Restaurar configuração de fábrica", "Reset", "Aplica os valores padrão. Use Salvar ou Exportar antes para preservar a configuração atual.")
		self:_action(page, "Descarregar VW MENU", "Unload", "Encerra módulos e conexões, remove o menu e restaura recursos locais sob responsabilidade dos controladores.")
	end

	function UIManager:_buildDiagnostics(page)
		self:_section(page, "Estado e capacidades")
		self.DiagnosticSummary = self:_note(page, "Aguardando amostras…", true)
		self.ModuleIndicators = {}
		for _, name in ipairs({ "Aim", "ESP", "Flight", "Speed", "Health" }) do
			self.ModuleIndicators[name] = self:StatusIndicator(page, name .. " · estado efetivo")
		end
		self:_note(page, "Correção suspeita é uma inferência local. Telemetria recebida do servidor é exibida separadamente e não confirma automaticamente a causa. Probe local de saúde não comprova invulnerabilidade.")
		self:_section(page, "Valores dos módulos")
		self.DiagnosticValues = text(page, "Sem valores ainda.", UDim2.fromOffset(0, 0), UDim2.new(1, -8, 0, 0), {
			AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top, TextSize = 11,
			Font = Enum.Font.Code, TextColor3 = self.Colors.Muted,
		})
		self:_section(page, "Eventos e erros recentes")
		self.DiagnosticEvents = text(page, "Nenhum evento registrado.", UDim2.fromOffset(0, 0), UDim2.new(1, -8, 0, 0), {
			AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top, TextSize = 11,
			Font = Enum.Font.Code, TextColor3 = self.Colors.Muted,
		})
	end

	function UIManager:_selectPage(name)
		self:_cancelCapture()
		self.SliderDrag = nil
		for pageName, page in pairs(self.Pages) do page.Visible = pageName == name end
		for pageName, tab in pairs(self.Tabs) do
			tab.BackgroundColor3 = pageName == name and self.Colors.Selected or self.Colors.Sidebar
			tab.TextColor3 = pageName == name and self.Colors.Light or self.Colors.Muted
			tab.Indicator.Visible = pageName == name
		end
		self.PageTitle.Text = name
		self.PageSubtitle.Text = PAGE_INFO[name]
		self.ActivePage = name
		if self.TooltipLabel then self.TooltipLabel.Visible = false end
	end

	function UIManager:_viewport()
		local camera = self.Ctx.Services.Workspace.CurrentCamera
		if camera and camera.ViewportSize.X > 0 and camera.ViewportSize.Y > 0 then return camera.ViewportSize end
		local size = self.Ctx.Gui.AbsoluteSize
		return Vector2.new(math.max(size.X, 1), math.max(size.Y, 1))
	end

	function UIManager:_fit(center)
		if not self.Window then return end
		local viewport = self:_viewport()
		local requested = self:_get("Settings.Scale", 1)
		if not finite(requested) then requested = 1 end
		local fit = math.min(math.max(1, viewport.X - 16) / WIDTH, math.max(1, viewport.Y - 16) / HEIGHT)
		self.UIScale.Scale = math.min(math.max(0.05, requested), fit)
		local size = Vector2.new(WIDTH, HEIGHT) * self.UIScale.Scale
		local position = self.Window.Position
		local x, y = position.X.Offset, position.Y.Offset
		if center or not self.Placed then
			x, y = (viewport.X - size.X) / 2, (viewport.Y - size.Y) / 2
			self.Placed = true
		end
		x = math.clamp(x, 0, math.max(0, viewport.X - size.X))
		y = math.clamp(y, 0, math.max(0, viewport.Y - size.Y))
		self.Window.Position = UDim2.fromOffset(x, y)
		self.LastViewport = viewport
	end

	function UIManager:_setOpen(open)
		self.Open = open == true
		if not self.Open then self:_cancelAnimations(true) end
		self:_layoutNotifications()
		if self.Window then self.Window.Visible = self.Open end
		self:_cancelCapture()
		self.WindowDrag, self.SliderDrag = nil, nil
		if self.TooltipLabel then self.TooltipLabel.Visible = false end
		if self.Open then self:_fit() end
	end

	function UIManager:_captureInput(input)
		local path = self.Capture.Path
		if input.KeyCode == Enum.KeyCode.Escape then
			self:_cancelCapture()
			self:_status("Captura de tecla cancelada")
			return
		end
		local name
		if input.UserInputType == Enum.UserInputType.Keyboard then
			if input.KeyCode ~= Enum.KeyCode.Unknown then name = input.KeyCode.Name end
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.MouseButton3 then
			name = input.UserInputType.Name
		end
		if not name then return end
		if (name == "LeftControl" or name == "RightControl") and path ~= "Settings.MenuKey" then
			self:_status("CTRL está reservado ao menu. Escolha outra tecla.", true)
			return
		end
		for _, otherPath in ipairs(KEY_PATHS) do
			if otherPath ~= path and self:_get(otherPath) == name then
				self:_status("Tecla já utilizada por " .. otherPath, true)
				return
			end
		end
		self:_cancelCapture()
		self:_set(path, name)
	end

	function UIManager:_installInput()
		local inputService = self.Ctx.Services.UserInputService
		self:_connect(inputService.InputBegan, function(input, processed)
			if inputService:GetFocusedTextBox() then return end
			if self.Capture then self:_captureInput(input) return end
			if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
			local name = input.KeyCode.Name
			local isMenu = name == "LeftControl" or name == "RightControl" or name == self:_get("Settings.MenuKey", "LeftControl")
			if isMenu then
				if self.HeldMenuKeys[name] then return end
				local held = next(self.HeldMenuKeys) ~= nil
				self.HeldMenuKeys[name] = true
				if not held then self:_setOpen(not self.Open) end
				return
			end
			if not self.Open then return end
			local selected = self.SelectedSlider
			if selected and (input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.Right) then
				local direction = input.KeyCode == Enum.KeyCode.Left and -1 or 1
				local value = self:_get(selected.Path, selected.Minimum) + direction * selected.Increment
				self:_set(selected.Path, math.clamp(round(value, selected.Increment), selected.Minimum, selected.Maximum))
			end
		end)
		self:_connect(inputService.InputChanged, function(input)
			local mouse = input.UserInputType == Enum.UserInputType.MouseMovement
			if self.SliderDrag and ((mouse and self.SliderDrag.Input.UserInputType == Enum.UserInputType.MouseButton1) or input == self.SliderDrag.Input) then
				self.SliderDrag.Set(input.Position)
			end
			local drag = self.WindowDrag
			if drag and ((mouse and drag.Input.UserInputType == Enum.UserInputType.MouseButton1) or input == drag.Input) then
				local offset = Vector2.new(input.Position.X, input.Position.Y) - drag.Start
				self.Window.Position = UDim2.fromOffset(drag.Position.X + offset.X, drag.Position.Y + offset.Y)
				self:_fit()
			end
		end)
		self:_connect(inputService.InputEnded, function(input)
			if input.UserInputType == Enum.UserInputType.Keyboard then self.HeldMenuKeys[input.KeyCode.Name] = nil end
			local mouse = input.UserInputType == Enum.UserInputType.MouseButton1
			if self.SliderDrag and (mouse or input == self.SliderDrag.Input) then self.SliderDrag = nil end
			if self.WindowDrag and (mouse or input == self.WindowDrag.Input) then self.WindowDrag = nil end
		end)
		self:_connect(inputService.WindowFocusReleased, function()
			self.HeldMenuKeys = {}
			self.WindowDrag, self.SliderDrag = nil, nil
			self:_cancelCapture()
		end)
	end

	function UIManager:_build()
		local window = create("Frame", {
			Name = "VWMenuWindow", Size = UDim2.fromOffset(WIDTH, HEIGHT),
			Position = UDim2.fromOffset(0, 0), BackgroundColor3 = self.Colors.Background,
			BorderSizePixel = 0, Active = true, ClipsDescendants = true, Visible = true,
		}, self.Ctx.Gui)
		self.Window = window
		self.Cleanup:Add(window)
		corner(window, 6)
		stroke(window, self.Colors.Line)
		self.UIScale = create("UIScale", { Scale = 1 }, window)
		local header = create("Frame", {
			Name = "DraggableHeader", Size = UDim2.new(1, 0, 0, 56),
			BackgroundColor3 = self.Colors.Sidebar, BorderSizePixel = 0, Active = true,
		}, window)
		self.Brand = text(header, "VW MENU", UDim2.fromOffset(20, 11), UDim2.fromOffset(140, 30), {
			TextSize = 21, Font = Enum.Font.GothamBlack, TextColor3 = self.Colors.Accent,
		})
		text(header, "UNIVERSAL EDITION", UDim2.fromOffset(174, 17), UDim2.fromOffset(155, 23), {
			TextSize = 10, Font = Enum.Font.GothamMedium, TextColor3 = self.Colors.Muted,
		})
		text(header, "v4.0", UDim2.fromOffset(333, 17), UDim2.fromOffset(50, 23), {
			TextSize = 10, Font = Enum.Font.Code, TextColor3 = self.Colors.Light,
		})
		text(header, "CTRL  abrir / fechar", UDim2.new(1, -215, 0, 17), UDim2.fromOffset(160, 23), {
			TextSize = 10, TextColor3 = self.Colors.Muted, TextXAlignment = Enum.TextXAlignment.Right,
		})
		self:_button(header, "×", UDim2.new(1, -42, 0, 13), UDim2.fromOffset(28, 28), function()
			self:_setOpen(false)
		end, "Ocultar menu · pressione CTRL para abrir novamente")
		create("Frame", {
			BackgroundColor3 = self.Colors.Selected, BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 55), Size = UDim2.new(1, 0, 0, 1),
		}, window)
		self:_connect(header.InputBegan, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				self.WindowDrag = {
					Input = input, Start = Vector2.new(input.Position.X, input.Position.Y),
					Position = Vector2.new(window.Position.X.Offset, window.Position.Y.Offset),
				}
			end
		end)
		create("Frame", {
			BackgroundColor3 = self.Colors.Line, BorderSizePixel = 0,
			Position = UDim2.fromOffset(144, 56), Size = UDim2.new(0, 1, 1, -87),
		}, window)
		create("Frame", {
			Name = "FixedSidebar", Position = UDim2.fromOffset(0,56), Size = UDim2.new(0,144,1,-87),
			BackgroundColor3 = self.Colors.Sidebar, BorderSizePixel = 0,
		}, window)
		text(window, "WORKSPACE", UDim2.fromOffset(18, 74), UDim2.fromOffset(110, 16), {
			TextSize = 9, Font = Enum.Font.GothamBold, TextColor3 = self.Colors.Muted,
		})
		for index, name in ipairs(PAGES) do
			local tab = self:_button(window, "     " .. name, UDim2.fromOffset(10, 100 + (index - 1) * 42), UDim2.fromOffset(124, 36), function()
				self:_selectPage(name)
			end)
			tab.TextXAlignment = Enum.TextXAlignment.Left
			tab.UIStroke.Transparency = 1
			local indicator = create("Frame", {
				Name = "Indicator", Position = UDim2.fromOffset(0, 9), Size = UDim2.fromOffset(2, 18),
				BackgroundColor3 = self.Colors.Accent, BorderSizePixel = 0,
			}, tab)
			indicator.Visible = false
			self.Tabs[name] = tab
			local page = create("ScrollingFrame", {
				Name = name, Position = UDim2.fromOffset(164, 158), Size = UDim2.fromOffset(600, 306),
				BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false,
				CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
				ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 3,
				ScrollBarImageColor3 = self.Colors.Selected, ClipsDescendants = true,
			}, window)
			create("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2),
			}, page)
			create("UIPadding", { PaddingBottom = UDim.new(0, 16) }, page)
			self.Pages[name] = page
		end
		text(window, "Interface pública; ações do laboratório exigem autorização", UDim2.fromOffset(18, 393), UDim2.fromOffset(114, 70), {
			TextSize = 10, TextColor3 = self.Colors.Muted, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
		})
		self.PageTitle = text(window, "", UDim2.fromOffset(164, 69), UDim2.fromOffset(260, 25), {
			TextSize = 18, Font = Enum.Font.GothamBold,
		})
		self.PageSubtitle = text(window, "", UDim2.fromOffset(164, 96), UDim2.fromOffset(592, 17), {
			TextSize = 10, TextColor3 = self.Colors.Muted,
		})
		self.Authorization = text(window, "", UDim2.fromOffset(409, 71), UDim2.fromOffset(347, 22), {
			TextSize = 9, TextColor3 = self.Colors.Light, TextXAlignment = Enum.TextXAlignment.Right,
		})
		create("Frame", {
			BackgroundColor3 = self.Colors.Line, BorderSizePixel = 0,
			Position = UDim2.new(0, 0, 1, -31), Size = UDim2.new(1, 0, 0, 1),
		}, window)
		self.Connection = text(window, "", UDim2.fromOffset(15, 480), UDim2.fromOffset(230, 23), {
			TextSize = 9, TextColor3 = self.Colors.Muted,
		})
		self.Feedback = text(window, "Interface pública · CTRL abre / fecha", UDim2.fromOffset(246, 480), UDim2.fromOffset(516, 23), {
			TextSize = 9, TextColor3 = self.Colors.Muted,
			TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd,
		})
		self.TooltipLabel = text(window, "", UDim2.fromOffset(158, 421), UDim2.fromOffset(606, 51), {
			Visible = false, BackgroundColor3 = self.Colors.Panel, BackgroundTransparency = 0,
			TextSize = 11, TextWrapped = true, TextColor3 = self.Colors.Light, ZIndex = 30,
		})
		create("UIPadding", {
			PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
			PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 7),
		}, self.TooltipLabel)
		corner(self.TooltipLabel)
		stroke(self.TooltipLabel)
		self:SearchBox(window)
		self:_buildCombat(self.Pages.Combat)
		self:_buildVisuals(self.Pages.Visuals)
		self:_buildMovement(self.Pages.Movement)
		self:_buildPlayer(self.Pages.Player)
		self:_buildSettings(self.Pages.Settings)
		self:_buildDiagnostics(self.Pages.Diagnostics)
		-- Stable explicit orders avoid relying on child name sorting for long pages.
		for _, page in pairs(self.Pages) do
			local order = 0
			for _, child in ipairs(page:GetChildren()) do
				if child:IsA("GuiObject") then order += 1 child.LayoutOrder = order end
			end
		end
		self:_selectPage("Combat")
		self:_fit(true)
	end

	function UIManager:_displayValue(value)
		if type(value) ~= "table" then return tostring(value) end
		local ok, encoded = pcall(self.Ctx.Services.HttpService.JSONEncode, self.Ctx.Services.HttpService, value)
		local rendered = ok and encoded or "[tabela não serializável]"
		return #rendered > 600 and (rendered:sub(1, 600) .. "…") or rendered
	end

	function UIManager:_updateDiagnostics()
		local authorized, server = self:_authorized(), self:_serverAvailable()
		self.Authorization.Text = authorized and "INTERFACE PÚBLICA · LAB AUTORIZADO" or "INTERFACE PÚBLICA · LAB BLOQUEADO"
		self.Authorization.TextColor3 = authorized and self.Colors.Success or self.Colors.Light
		self.Connection.Text = string.format("%d FPS  ·  SERVIDOR %s", math.floor(self.FPS + 0.5), server and "DISPONÍVEL" or "AUSENTE")
		self.DiagnosticSummary.Text = string.format(
			"FPS medido: %d  |  Autorização do laboratório: %s  |  Serviço do servidor: %s\nInterface pública; ações do laboratório exigem autorização. Configuração local editável.",
			math.floor(self.FPS + 0.5), authorized and "concedida" or "ausente / bloqueada", server and "disponível" or "ausente"
		)
		local requested = {}
		for _, module in ipairs({ "Aim", "ESP", "Flight", "Speed" }) do
			table.insert(requested, module .. " " .. (self:_get(module .. ".Enabled", false) and "ON" or "OFF"))
		end
		self.DiagnosticSummary.Text ..= "\nSolicitado: " .. table.concat(requested, " · ")
		for _, update in pairs(self.ModuleIndicators or {}) do update(nil) end
		local diagnostics = self.Ctx.Diagnostics
		if not diagnostics or type(diagnostics.Snapshot) ~= "function" then
			self.DiagnosticValues.Text = "Snapshot de diagnóstico indisponível."
			self.DiagnosticEvents.Text = "Eventos de diagnóstico indisponíveis."
			return
		end
		local ok, snapshot = pcall(diagnostics.Snapshot, diagnostics)
		if not ok or type(snapshot) ~= "table" then
			self.DiagnosticValues.Text = "Erro ao ler diagnóstico: " .. tostring(snapshot)
			self.DiagnosticEvents.Text = "Eventos de diagnóstico indisponíveis."
			return
		end
		local values = type(snapshot.Values) == "table" and snapshot.Values or {}
		for module, update in pairs(self.ModuleIndicators or {}) do
			local status = values[module .. ".Status"]
			if status == nil and type(values["Module.Status"]) == "table" then status = values["Module.Status"][module] end
			update(status)
		end
		local keys = {}
		for key in pairs(values) do table.insert(keys, key) end
		table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
		local lines = {}
		for _, key in ipairs(keys) do
			table.insert(lines, tostring(key) .. " = " .. self:_displayValue(values[key]))
		end
		self.DiagnosticValues.Text = #lines > 0 and table.concat(lines, "\n") or "Sem telemetria de módulos ainda."
		local events = type(snapshot.Events) == "table" and snapshot.Events or {}
		local eventLines = {}
		for index = #events, math.max(1, #events - 14), -1 do
			local event = events[index]
			if type(event) == "table" then
				table.insert(eventLines, string.format("[%s] %s · %s", tostring(event.Status or event.status or "info"), tostring(event.Module or event.module or "runtime"), tostring(event.Detail or event.detail or event.Message or event.message or self:_displayValue(event))))
			else
				table.insert(eventLines, tostring(event))
			end
		end
		self.DiagnosticEvents.Text = #eventLines > 0 and table.concat(eventLines, "\n\n") or "Nenhum evento registrado."
	end

	function UIManager:Init()
		if self.Initialized or self.Destroyed then return end
		self.Initialized = true
		self:_build()
		self:_applyTheme()
		self:_installInput()
		local subscription = self.Ctx.Config:Subscribe(function(path)
			if self.Destroyed then return end
			if type(path) == "string" then self:_refresh(path) else self:UpdateConfig() end
			if path == "Settings.Scale" then self:_fit() end
			if path == "Settings.Theme" then self:_applyTheme() end
		end)
		if subscription then self.Cleanup:Add(subscription) end
		self:_updateDiagnostics()
	end

	function UIManager:UpdateConfig()
		if self.Destroyed then return end
		for path in pairs(self.Bindings) do self:_refresh(path) end
		self:_applyTheme()
		self:_fit()
	end

	function UIManager:Show()
		if self.Destroyed then return end
		if not self.Initialized then self:Init() end
		self:_setOpen(true)
	end

	function UIManager:Hide()
		if not self.Destroyed then self:_setOpen(false) end
	end

	-- Compatibility with the feature-controller lifecycle; visibility is public.
	UIManager.Enable = UIManager.Show
	UIManager.Disable = UIManager.Hide

	function UIManager:Step(dt)
		if not self.Initialized or self.Destroyed or not finite(dt) or dt <= 0 then return end
		for index = #self.Notifications, 1, -1 do
			local item = self.Notifications[index]
			item.Remaining -= dt
			if item.Remaining <= 0 then item.Frame:Destroy() table.remove(self.Notifications,index) end
		end
		self:_layoutNotifications()
		self.FrameTime += dt
		self.FrameCount += 1
		self.Elapsed += dt
		if self.Elapsed >= 0.5 then
			self.Elapsed = self.Elapsed % 0.5
			self.FPS = self.FrameCount / math.max(self.FrameTime, 0.001)
			self.FrameTime, self.FrameCount = 0, 0
			local viewport = self:_viewport()
			if not self.LastViewport or viewport ~= self.LastViewport then self:_fit() end
			self:_updateDiagnostics()
		end
	end

	function UIManager:Destroy()
		if self.Destroyed then return end
		self:_cancelCapture()
		self.Destroyed = true
		self:_cancelAnimations(false)
		self.Capture, self.WindowDrag, self.SliderDrag, self.SelectedSlider = nil, nil, nil, nil
		self.HeldMenuKeys = {}
		self.Cleanup:Destroy()
		self.Bindings, self.Pages, self.Tabs, self.Notifications = {}, {}, {}, {}
		self.Window, self.TooltipLabel, self.JSONField = nil, nil, nil
		self.SearchField, self.ProfileName, self.Brand, self.UIScale = nil, nil, nil, nil
		self.PageTitle, self.PageSubtitle, self.Authorization, self.Connection, self.Feedback = nil, nil, nil, nil, nil
		self.DiagnosticSummary, self.DiagnosticValues, self.DiagnosticEvents = nil, nil, nil
		self.ModuleIndicators = {}
	end

	UIManager.ToggleSwitch = UIManager._toggle
	UIManager.ModernSlider = UIManager._slider
	UIManager.KeybindPicker = UIManager._keybind
	UIManager.Dropdown = UIManager._dropdown
	UIManager.SectionHeader = UIManager._section
	UIManager.Tooltip = UIManager._hint

	return UIManager
end
