-- Native laboratory menu. Gameplay ownership remains with the feature controllers.
return function(import)
	local CleanupManager = import("shared/CleanupManager")
	local UIManager = {}
	UIManager.__index = UIManager

	local WIDTH, HEIGHT = 780, 510
	local COLORS = {
		Background = Color3.fromRGB(8, 13, 23),
		Panel = Color3.fromRGB(17, 29, 48),
		Selected = Color3.fromRGB(18, 60, 117),
		Accent = Color3.fromRGB(57, 169, 255),
		Light = Color3.fromRGB(134, 213, 255),
		Text = Color3.fromRGB(234, 244, 255),
		Muted = Color3.fromRGB(141, 162, 188),
		Line = Color3.fromRGB(35, 52, 74),
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
		if self.Feedback then
			self.Feedback.Text = self.StatusMessage
			self.Feedback.TextColor3 = self.StatusError and COLORS.Error or COLORS.Muted
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
			if self.Tooltip then
				self.Tooltip.Text = message
				self.Tooltip.Visible = self.Open
			end
		end)
		self:_connect(control.MouseLeave, function()
			if self.Tooltip then self.Tooltip.Visible = false end
		end)
		self:_connect(control.SelectionGained, function()
			if self.Tooltip then
				self.Tooltip.Text = message
				self.Tooltip.Visible = self.Open
			end
		end)
		self:_connect(control.SelectionLost, function()
			if self.Tooltip then self.Tooltip.Visible = false end
		end)
	end

	function UIManager:_button(parent, label, position, size, callback, hint)
		local button = create("TextButton", {
			BackgroundColor3 = COLORS.Panel,
			BorderSizePixel = 0,
			Text = label,
			TextColor3 = COLORS.Light,
			TextSize = 12,
			Font = Enum.Font.GothamMedium,
			AutoButtonColor = false,
			Selectable = true,
			Position = position,
			Size = size,
		}, parent)
		corner(button)
		local outline = stroke(button)
		self:_connect(button.MouseEnter, function() outline.Color = COLORS.Accent end)
		self:_connect(button.MouseLeave, function() outline.Color = COLORS.Line end)
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
			TextSize = 10, Font = Enum.Font.GothamBold, TextColor3 = COLORS.Light,
		})
		create("Frame", {
			BackgroundColor3 = COLORS.Line, BorderSizePixel = 0,
			Position = UDim2.new(0, 0, 1, -1), Size = UDim2.new(1, 0, 0, 1),
		}, row)
	end

	function UIManager:_note(page, message, isWarning)
		local label = text(page, message, UDim2.fromOffset(0, 0), UDim2.new(1, -8, 0, 0), {
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = isWarning and COLORS.Light or COLORS.Muted,
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

	function UIManager:_toggle(page, path, label, hint)
		local row = self:_row(page, label, 38, hint)
		local button = self:_button(row, "", UDim2.new(1, -92, 0, 4), UDim2.fromOffset(92, 30), function()
			self:_set(path, not self:_get(path, false))
		end, hint or path)
		local dot = create("Frame", {
			BorderSizePixel = 0, Size = UDim2.fromOffset(5, 5),
			Position = UDim2.fromOffset(12, 13), BackgroundColor3 = COLORS.Muted,
		}, button)
		corner(dot, 3)
		self:_bind(path, function(value)
			button.Text = value and "    ATIVO" or "    INATIVO"
			button.TextColor3 = value and COLORS.Light or COLORS.Muted
			button.BackgroundColor3 = value and COLORS.Selected or COLORS.Panel
			dot.BackgroundColor3 = value and COLORS.Accent or COLORS.Muted
		end)
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
			BackgroundColor3 = COLORS.Panel, BorderSizePixel = 0,
			TextColor3 = COLORS.Light, Font = Enum.Font.GothamMedium,
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
			BackgroundColor3 = COLORS.Line, BorderSizePixel = 0,
			Position = UDim2.new(0, 0, 0.5, -2), Size = UDim2.new(1, 0, 0, 4),
		}, track)
		corner(rail, 2)
		local fill = create("Frame", {
			BackgroundColor3 = COLORS.Accent, BorderSizePixel = 0,
			Size = UDim2.fromScale(0, 1),
		}, rail)
		corner(fill, 2)
		local thumb = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(10, 10), BackgroundColor3 = COLORS.Light,
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
		if rule and type(rule.Choices) == "table" then options = rule.Choices end
		local row = self:_row(page, label, 38, hint)
		local expanded = false
		local items = {}
		local button = self:_button(row, "", UDim2.new(0.54, 0, 0, 3), UDim2.new(0.46, 0, 0, 30), function()
			expanded = not expanded
			row.Size = UDim2.new(1, -8, 0, expanded and (38 + #options * 29) or 38)
			for _, item in ipairs(items) do item.Visible = expanded end
		end, hint or path)
		for index, value in ipairs(options) do
			local item = self:_button(row, value, UDim2.new(0.54, 0, 0, 37 + (index - 1) * 29), UDim2.new(0.46, 0, 0, 26), function()
				self:_set(path, value)
				expanded = false
				row.Size = UDim2.new(1, -8, 0, 38)
				for _, option in ipairs(items) do option.Visible = false end
			end)
			item.Visible = false
			table.insert(items, item)
		end
		self:_bind(path, function(value)
			button.Text = tostring(value or "—") .. "   ▾"
			for index, item in ipairs(items) do
				item.TextColor3 = options[index] == value and COLORS.Light or COLORS.Muted
				item.BackgroundColor3 = options[index] == value and COLORS.Selected or COLORS.Panel
			end
		end)
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
			button.TextColor3 = COLORS.Accent
			self:_status("Esc cancela · CTRL fica reservado ao menu")
		end, hint or "Clique para capturar uma tecla. Esc cancela; atalhos duplicados são recusados.")
		self:_bind(path, function(value)
			if self.Capture and self.Capture.Path == path then return end
			button.Text = tostring(value or "—")
			button.TextColor3 = COLORS.Light
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
			TextColor3 = COLORS.Muted, TextSize = 10, TextWrapped = true,
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
		self:_toggle(page, "Aim.Fallback", "Fallback para torso")
		self:_toggle(page, "Aim.TargetLock", "Manter alvo")
		self:_slider(page, "Aim.SwitchDelay", "Intervalo de troca · s", 0, 2, 0.05)
		self:_slider(page, "Aim.Prediction", "Predição · s", 0, 0.5, 0.01)
		self:_toggle(page, "Aim.ShowFOV", "Exibir círculo de FOV")
	end

	function UIManager:_buildVisuals(page)
		self:_section(page, "Overlays de entidades")
		self:_toggle(page, "ESP.Enabled", "ESP")
		for _, item in ipairs({
			{ "Players", "Jogadores" }, { "NPCs", "NPCs" }, { "Items", "Itens marcados" },
		}) do self:_toggle(page, "ESP." .. item[1], item[2]) end
		self:_section(page, "Informações exibidas")
		for _, item in ipairs({
			{ "Boxes", "Caixas" }, { "Names", "Nomes" }, { "Health", "Vida" },
			{ "Distance", "Distância" }, { "Lines", "Linhas de referência" },
		}) do self:_toggle(page, "ESP." .. item[1], item[2]) end
		self:_toggle(page, "ESP.ThroughWalls", "Exibir através de paredes", "Exibição local; não altera colisão ou regras de visibilidade do servidor.")
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
		self:_section(page, "Perfis na memória")
		self:_note(page, "Perfis são temporários: existem apenas nesta sessão e somem ao descarregar. Use o JSON abaixo para transportar configurações.")
		local profileRow = create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 39) }, page)
		local profileName = create("TextBox", {
			BackgroundColor3 = COLORS.Panel, BorderSizePixel = 0, TextColor3 = COLORS.Text,
			PlaceholderText = "Nome do perfil", PlaceholderColor3 = COLORS.Muted,
			Text = "Meu perfil", ClearTextOnFocus = false, TextSize = 12, Font = Enum.Font.Gotham,
			Position = UDim2.fromOffset(0, 3), Size = UDim2.new(1, -208, 0, 30),
		}, profileRow)
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
			BackgroundColor3 = COLORS.Panel, BorderSizePixel = 0,
			Size = UDim2.new(1, -8, 0, 154), ClipsDescendants = true,
		}, page)
		corner(jsonHolder)
		stroke(jsonHolder)
		local jsonScroll = create("ScrollingFrame", {
			BackgroundTransparency = 1, BorderSizePixel = 0,
			Size = UDim2.new(1, -12, 1, -12), Position = UDim2.fromOffset(6, 6),
			CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 3, ScrollBarImageColor3 = COLORS.Accent,
			ScrollingDirection = Enum.ScrollingDirection.Y,
		}, jsonHolder)
		self.JSONField = create("TextBox", {
			BackgroundTransparency = 1, BorderSizePixel = 0, ClearTextOnFocus = false,
			MultiLine = true, TextWrapped = true, Text = "", PlaceholderText = "Cole ou exporte o JSON aqui…",
			TextColor3 = COLORS.Text, PlaceholderColor3 = COLORS.Muted,
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
		self:_note(page, "Correção suspeita é uma inferência local. Telemetria recebida do servidor é exibida separadamente e não confirma automaticamente a causa. Probe local de saúde não comprova invulnerabilidade.")
		self:_section(page, "Valores dos módulos")
		self.DiagnosticValues = text(page, "Sem valores ainda.", UDim2.fromOffset(0, 0), UDim2.new(1, -8, 0, 0), {
			AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top, TextSize = 11,
			Font = Enum.Font.Code, TextColor3 = COLORS.Muted,
		})
		self:_section(page, "Eventos e erros recentes")
		self.DiagnosticEvents = text(page, "Nenhum evento registrado.", UDim2.fromOffset(0, 0), UDim2.new(1, -8, 0, 0), {
			AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top, TextSize = 11,
			Font = Enum.Font.Code, TextColor3 = COLORS.Muted,
		})
	end

	function UIManager:_selectPage(name)
		self:_cancelCapture()
		self.SliderDrag = nil
		for pageName, page in pairs(self.Pages) do page.Visible = pageName == name end
		for pageName, tab in pairs(self.Tabs) do
			tab.BackgroundColor3 = pageName == name and COLORS.Selected or COLORS.Background
			tab.TextColor3 = pageName == name and COLORS.Light or COLORS.Muted
			tab.Indicator.Visible = pageName == name
		end
		self.PageTitle.Text = name
		self.PageSubtitle.Text = PAGE_INFO[name]
		self.ActivePage = name
		if self.Tooltip then self.Tooltip.Visible = false end
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
		local fit = math.min((viewport.X - 16) / WIDTH, (viewport.Y - 16) / HEIGHT)
		self.UIScale.Scale = math.max(0.05, math.min(requested, fit))
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
		if self.Window then self.Window.Visible = self.Open end
		self:_cancelCapture()
		self.WindowDrag, self.SliderDrag = nil, nil
		if self.Tooltip then self.Tooltip.Visible = false end
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
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.MouseButton3 then
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
			Position = UDim2.fromOffset(0, 0), BackgroundColor3 = COLORS.Background,
			BorderSizePixel = 0, Active = true, ClipsDescendants = true,
		}, self.Ctx.Gui)
		self.Window = window
		self.Cleanup:Add(window)
		corner(window, 7)
		stroke(window, COLORS.Line)
		self.UIScale = create("UIScale", { Scale = 1 }, window)
		local header = create("Frame", {
			Name = "DraggableHeader", Size = UDim2.new(1, 0, 0, 56),
			BackgroundColor3 = COLORS.Panel, BorderSizePixel = 0, Active = true,
		}, window)
		text(header, "VW", UDim2.fromOffset(20, 11), UDim2.fromOffset(40, 30), {
			TextSize = 23, Font = Enum.Font.GothamBlack, TextColor3 = COLORS.Accent,
		})
		text(header, "MENU", UDim2.fromOffset(68, 13), UDim2.fromOffset(78, 26), {
			TextSize = 18, Font = Enum.Font.GothamBold,
		})
		text(header, "LAB  /  CLIENT", UDim2.fromOffset(170, 17), UDim2.fromOffset(220, 23), {
			TextSize = 10, TextColor3 = COLORS.Muted,
		})
		text(header, "CTRL  abrir / fechar", UDim2.new(1, -215, 0, 17), UDim2.fromOffset(160, 23), {
			TextSize = 10, TextColor3 = COLORS.Muted, TextXAlignment = Enum.TextXAlignment.Right,
		})
		self:_button(header, "×", UDim2.new(1, -42, 0, 13), UDim2.fromOffset(28, 28), function()
			self:_setOpen(false)
		end, "Ocultar menu · pressione CTRL para abrir novamente")
		create("Frame", {
			BackgroundColor3 = COLORS.Selected, BorderSizePixel = 0,
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
			BackgroundColor3 = COLORS.Line, BorderSizePixel = 0,
			Position = UDim2.fromOffset(144, 56), Size = UDim2.new(0, 1, 1, -87),
		}, window)
		text(window, "WORKSPACE", UDim2.fromOffset(18, 74), UDim2.fromOffset(110, 16), {
			TextSize = 9, Font = Enum.Font.GothamBold, TextColor3 = COLORS.Muted,
		})
		for index, name in ipairs(PAGES) do
			local tab = self:_button(window, "     " .. name, UDim2.fromOffset(10, 100 + (index - 1) * 42), UDim2.fromOffset(124, 36), function()
				self:_selectPage(name)
			end)
			tab.TextXAlignment = Enum.TextXAlignment.Left
			tab.UIStroke.Transparency = 1
			local indicator = create("Frame", {
				Name = "Indicator", Position = UDim2.fromOffset(0, 9), Size = UDim2.fromOffset(2, 18),
				BackgroundColor3 = COLORS.Accent, BorderSizePixel = 0,
			}, tab)
			indicator.Visible = false
			self.Tabs[name] = tab
			local page = create("ScrollingFrame", {
				Name = name, Position = UDim2.fromOffset(164, 120), Size = UDim2.fromOffset(600, 344),
				BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false,
				CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
				ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 3,
				ScrollBarImageColor3 = COLORS.Selected, ClipsDescendants = true,
			}, window)
			create("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2),
			}, page)
			create("UIPadding", { PaddingBottom = UDim.new(0, 16) }, page)
			self.Pages[name] = page
		end
		text(window, "AUTHORIZED\nLABORATORY", UDim2.fromOffset(18, 409), UDim2.fromOffset(114, 39), {
			TextSize = 9, TextColor3 = COLORS.Muted, Font = Enum.Font.GothamBold,
		})
		self.PageTitle = text(window, "", UDim2.fromOffset(164, 69), UDim2.fromOffset(260, 25), {
			TextSize = 18, Font = Enum.Font.GothamBold,
		})
		self.PageSubtitle = text(window, "", UDim2.fromOffset(164, 96), UDim2.fromOffset(592, 17), {
			TextSize = 10, TextColor3 = COLORS.Muted,
		})
		self.Authorization = text(window, "", UDim2.fromOffset(409, 71), UDim2.fromOffset(347, 22), {
			TextSize = 9, TextColor3 = COLORS.Light, TextXAlignment = Enum.TextXAlignment.Right,
		})
		create("Frame", {
			BackgroundColor3 = COLORS.Line, BorderSizePixel = 0,
			Position = UDim2.new(0, 0, 1, -31), Size = UDim2.new(1, 0, 0, 1),
		}, window)
		self.Connection = text(window, "", UDim2.fromOffset(15, 480), UDim2.fromOffset(230, 23), {
			TextSize = 9, TextColor3 = COLORS.Muted,
		})
		self.Feedback = text(window, "Pronto · alterações são validadas pelo laboratório", UDim2.fromOffset(246, 480), UDim2.fromOffset(516, 23), {
			TextSize = 9, TextColor3 = COLORS.Muted,
			TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd,
		})
		self.Tooltip = text(window, "", UDim2.fromOffset(158, 421), UDim2.fromOffset(606, 51), {
			Visible = false, BackgroundColor3 = COLORS.Panel, BackgroundTransparency = 0,
			TextSize = 11, TextWrapped = true, TextColor3 = COLORS.Light, ZIndex = 30,
		})
		create("UIPadding", {
			PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
			PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 7),
		}, self.Tooltip)
		corner(self.Tooltip)
		stroke(self.Tooltip)
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
		self.Authorization.Text = authorized and "AUTORIZADO · LABORATÓRIO" or "BLOQUEADO · MODO DIAGNÓSTICO"
		self.Authorization.TextColor3 = authorized and COLORS.Success or COLORS.Light
		self.Connection.Text = string.format("%d FPS  ·  SERVIDOR %s", math.floor(self.FPS + 0.5), server and "DISPONÍVEL" or "AUSENTE")
		self.DiagnosticSummary.Text = string.format(
			"FPS medido: %d  |  Autorização: %s  |  Serviço do servidor: %s\nConfiguração local editável. Recursos e testes dependem da política e das confirmações de servidor.",
			math.floor(self.FPS + 0.5), authorized and "concedida" or "ausente / bloqueada", server and "disponível" or "ausente"
		)
		local diagnostics = self.Ctx.Diagnostics
		if not diagnostics or type(diagnostics.Snapshot) ~= "function" then
			self.DiagnosticValues.Text = "Snapshot de diagnóstico indisponível."
			return
		end
		local ok, snapshot = pcall(diagnostics.Snapshot, diagnostics)
		if not ok or type(snapshot) ~= "table" then
			self.DiagnosticValues.Text = "Erro ao ler diagnóstico: " .. tostring(snapshot)
			return
		end
		local values = type(snapshot.Values) == "table" and snapshot.Values or {}
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
		self:_installInput()
		local subscription = self.Ctx.Config:Subscribe(function(path)
			if self.Destroyed then return end
			if type(path) == "string" then self:_refresh(path) else self:UpdateConfig() end
			if path == "Settings.Scale" then self:_fit() end
		end)
		if subscription then self.Cleanup:Add(subscription) end
		self:_updateDiagnostics()
	end

	function UIManager:UpdateConfig()
		if self.Destroyed then return end
		for path in pairs(self.Bindings) do self:_refresh(path) end
		self:_fit()
	end

	function UIManager:Enable()
		if self.Destroyed then return end
		if not self.Initialized then self:Init() end
		self:_setOpen(true)
	end

	function UIManager:Disable()
		if not self.Destroyed then self:_setOpen(false) end
	end

	function UIManager:Step(dt)
		if not self.Initialized or self.Destroyed or not finite(dt) or dt <= 0 then return end
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
		self.Capture, self.WindowDrag, self.SliderDrag, self.SelectedSlider = nil, nil, nil, nil
		self.HeldMenuKeys = {}
		self.Cleanup:Destroy()
		self.Bindings, self.Pages, self.Tabs = {}, {}, {}
		self.Window, self.Tooltip, self.JSONField = nil, nil, nil
	end

	return UIManager
end
