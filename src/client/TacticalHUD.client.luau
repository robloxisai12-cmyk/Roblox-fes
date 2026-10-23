--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local combatRemote = remotes:WaitForChild("CombatRequest") :: RemoteEvent
local squadRemote = remotes:WaitForChild("SquadRequest") :: RemoteFunction
local TacticalUIRules = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("config"):WaitForChild("TacticalUIRules") :: ModuleScript
)

local COLORS = {
	Background = Color3.fromRGB(19, 26, 27),
	Surface = Color3.fromRGB(31, 42, 41),
	SurfaceActive = Color3.fromRGB(51, 77, 66),
	Accent = Color3.fromRGB(183, 202, 145),
	Text = Color3.fromRGB(242, 241, 226),
	Muted = Color3.fromRGB(183, 190, 177),
	Danger = Color3.fromRGB(193, 100, 79),
}

local currentTextScale = 1
local screen = Instance.new("ScreenGui")
screen.Name = "SierraTacticalHUD"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = false
screen.DisplayOrder = 20
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

local function round(instance: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function addText(
	parent: Instance,
	name: string,
	text: string,
	size: number,
	color: Color3,
	font: Enum.Font?
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = font or Enum.Font.Gotham
	label.Text = text
	label.TextColor3 = color
	label.TextSize = math.max(13, math.floor(size * currentTextScale + 0.5))
	label:SetAttribute("BaseTextSize", size)
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = parent
	return label
end

local function addButton(parent: Instance, name: string, text: string, order: number?): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.LayoutOrder = order or 0
	button.Size = UDim2.new(1, 0, 0, 48)
	button.BackgroundColor3 = COLORS.Surface
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Font = Enum.Font.GothamSemibold
	button.Text = text
	button.TextColor3 = COLORS.Text
	button.TextSize = math.max(13, math.floor(15 * currentTextScale + 0.5))
	button:SetAttribute("BaseTextSize", 15)
	button.TextWrapped = true
	button.Parent = parent
	round(button, 7)
	return button
end

local statusCard = Instance.new("Frame")
statusCard.Name = "StatusCard"
statusCard.Position = UDim2.new(0, 12, 0, 12)
statusCard.Size = UDim2.new(0.7, 0, 0, 102)
statusCard.BackgroundColor3 = COLORS.Background
statusCard.BackgroundTransparency = 0.12
statusCard.BorderSizePixel = 0
statusCard.Parent = screen
round(statusCard, 8)

local statusConstraint = Instance.new("UISizeConstraint")
statusConstraint.MinSize = Vector2.new(180, 102)
statusConstraint.MaxSize = Vector2.new(340, 102)
statusConstraint.Parent = statusCard

local healthText = addText(statusCard, "Health", "SALUD  -- / --", 18, COLORS.Text, Enum.Font.GothamBold)
healthText.Position = UDim2.new(0, 12, 0, 8)
healthText.Size = UDim2.new(1, -24, 0, 25)

local conditionText = addText(statusCard, "Condition", "Estado: sincronizando", 14, COLORS.Accent)
conditionText.Position = UDim2.new(0, 12, 0, 34)
conditionText.Size = UDim2.new(1, -24, 0, 21)

local ammoText = addText(statusCard, "Ammunition", "MUNICION  --", 14, COLORS.Text, Enum.Font.GothamSemibold)
ammoText.Position = UDim2.new(0, 12, 0, 58)
ammoText.Size = UDim2.new(1, -24, 0, 20)

local menuButton = Instance.new("TextButton")
menuButton.Name = "MenuToggle"
menuButton.AnchorPoint = Vector2.new(1, 0)
menuButton.Position = UDim2.new(1, -12, 0, 12)
menuButton.Size = UDim2.fromOffset(94, 48)
menuButton.BackgroundColor3 = COLORS.SurfaceActive
menuButton.BorderSizePixel = 0
menuButton.Font = Enum.Font.GothamBold
menuButton.Text = "TAB  MENU"
menuButton.TextColor3 = COLORS.Text
menuButton.TextSize = 14
menuButton:SetAttribute("BaseTextSize", 14)
menuButton.Parent = screen
round(menuButton, 8)

local hub = Instance.new("Frame")
hub.Name = "TacticalMenu"
hub.AnchorPoint = Vector2.new(0.5, 0.5)
hub.Position = UDim2.fromScale(0.5, 0.52)
hub.BackgroundColor3 = COLORS.Background
hub.BackgroundTransparency = 0.03
hub.BorderSizePixel = 0
hub.Visible = false
hub.Parent = screen
round(hub, 10)

local hubConstraint = Instance.new("UISizeConstraint")
hubConstraint.MinSize = Vector2.new(280, 240)
hubConstraint.MaxSize = Vector2.new(460, 520)
hubConstraint.Parent = hub

local header = addText(hub, "Header", "CENTRO TACTICO", 19, COLORS.Text, Enum.Font.GothamBold)
header.Position = UDim2.new(0, 16, 0, 10)
header.Size = UDim2.new(1, -32, 0, 32)

local subheader = addText(hub, "Subheader", "Estado e inventario", 13, COLORS.Muted)
subheader.Position = UDim2.new(0, 16, 0, 42)
subheader.Size = UDim2.new(1, -32, 0, 22)

local pageScroll = Instance.new("ScrollingFrame")
pageScroll.Name = "Page"
pageScroll.Position = UDim2.new(0, 12, 0, 72)
pageScroll.Size = UDim2.new(1, -24, 1, -84)
pageScroll.BackgroundTransparency = 1
pageScroll.BorderSizePixel = 0
pageScroll.CanvasSize = UDim2.new()
pageScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
pageScroll.ScrollBarThickness = 5
pageScroll.ScrollingDirection = Enum.ScrollingDirection.Y
pageScroll.Parent = hub

local pagePadding = Instance.new("UIPadding")
pagePadding.PaddingBottom = UDim.new(0, 6)
pagePadding.PaddingLeft = UDim.new(0, 2)
pagePadding.PaddingRight = UDim.new(0, 2)
pagePadding.PaddingTop = UDim.new(0, 2)
pagePadding.Parent = pageScroll

local pageLayout = Instance.new("UIListLayout")
pageLayout.Padding = UDim.new(0, 7)
pageLayout.SortOrder = Enum.SortOrder.LayoutOrder
pageLayout.Parent = pageScroll

local medicalSummary = addText(pageScroll, "InventorySummary", "Cargando equipo del servidor...", 14, COLORS.Text)
medicalSummary.Size = UDim2.new(1, 0, 0, 102)
medicalSummary.LayoutOrder = 1
medicalSummary.TextYAlignment = Enum.TextYAlignment.Top

local weaponButtons = Instance.new("Frame")
weaponButtons.Name = "WeaponButtons"
weaponButtons.Size = UDim2.new(1, 0, 0, 48)
weaponButtons.BackgroundTransparency = 1
weaponButtons.LayoutOrder = 2
weaponButtons.Parent = pageScroll

local rifleButton = addButton(weaponButtons, "EquipRifle", "Equipar fusil [1]")
rifleButton.Position = UDim2.new(0, 0, 0, 0)
rifleButton.Size = UDim2.new(0.49, 0, 1, 0)

local sidearmButton = addButton(weaponButtons, "EquipSidearm", "Equipar pistola [2]")
sidearmButton.Position = UDim2.new(0.51, 0, 0, 0)
sidearmButton.Size = UDim2.new(0.49, 0, 1, 0)

local squadHeading = addText(pageScroll, "SquadHeading", "ESCUADRONES", 15, COLORS.Accent, Enum.Font.GothamBold)
squadHeading.Size = UDim2.new(1, 0, 0, 24)
squadHeading.LayoutOrder = 3

local companyButton = addButton(pageScroll, "Company", "Compania: Sierra", 4)
companyButton.Size = UDim2.new(1, 0, 0, 44)

local squadName = Instance.new("TextBox")
squadName.Name = "SquadName"
squadName.LayoutOrder = 5
squadName.Size = UDim2.new(1, 0, 0, 44)
squadName.BackgroundColor3 = COLORS.Surface
squadName.BorderSizePixel = 0
squadName.ClearTextOnFocus = false
squadName.Font = Enum.Font.Gotham
squadName.PlaceholderText = "Nombre para crear escuadron"
squadName.Text = ""
squadName.TextColor3 = COLORS.Text
squadName.PlaceholderColor3 = COLORS.Muted
squadName.TextSize = 14
squadName:SetAttribute("BaseTextSize", 14)
squadName.Parent = pageScroll
round(squadName, 7)

local createSquadButton = addButton(pageScroll, "CreateSquad", "Crear escuadron", 6)
createSquadButton.Size = UDim2.new(1, 0, 0, 44)

local rosterMessage = addText(pageScroll, "RosterMessage", "Consultando escuadrones...", 13, COLORS.Muted)
rosterMessage.Size = UDim2.new(1, 0, 0, 36)
rosterMessage.LayoutOrder = 7
rosterMessage.TextYAlignment = Enum.TextYAlignment.Top

local rosterList = Instance.new("Frame")
rosterList.Name = "Roster"
rosterList.Size = UDim2.new(1, 0, 0, 0)
rosterList.AutomaticSize = Enum.AutomaticSize.Y
rosterList.BackgroundTransparency = 1
rosterList.LayoutOrder = 8
rosterList.Parent = pageScroll

local rosterLayout = Instance.new("UIListLayout")
rosterLayout.Padding = UDim.new(0, 5)
rosterLayout.SortOrder = Enum.SortOrder.LayoutOrder
rosterLayout.Parent = rosterList

local controlHelp = addText(
	pageScroll,
	"Controls",
	"PC: TAB menu | R recargar | 1/2 armas | 3/4 medicina | H ayudar | B vehiculo | V entregar | Enter radio\nMovil: usa el boton de menu y los controles tactiles.",
	12,
	COLORS.Muted
)
controlHelp.Size = UDim2.new(1, 0, 0, 50)
controlHelp.LayoutOrder = 9

local squadBackButton = addButton(pageScroll, "BackToMenu", "Volver al centro tactico", 2)
squadBackButton.Visible = false

local viewGuiNames = {
	medical = "SierraMedical",
	radio = "SierraRadio",
	mission = "SierraMission",
	logistics = "SierraLogistics",
}
local viewGuis: { [string]: ScreenGui } = {}
local refreshSquads: (() -> ())? = nil
local refreshRadio: (() -> ())? = nil
local closeMenu: () -> ()

local function setStatusMessage(text: string)
	rosterMessage.Text = text
end

local function clearRoster()
	for _, child in ipairs(rosterList:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextLabel") or child:IsA("TextButton") then
			child:Destroy()
		end
	end
end

local function updateProfile()
	local camera = Workspace.CurrentCamera
	local viewport = if camera ~= nil then camera.ViewportSize else Vector2.new(1280, 720)
	local profile = TacticalUIRules.GetProfile(viewport.X, viewport.Y)
	currentTextScale = profile.Scale
	local statusWidth = math.min(profile.PanelWidth, 340, math.max(180, viewport.X - 124))
	statusCard.Size = UDim2.new(0, statusWidth, 0, 102)
	statusConstraint.MinSize = Vector2.new(math.min(180, statusWidth), 102)
	statusConstraint.MaxSize = Vector2.new(statusWidth, 102)
	hub.Size = UDim2.fromOffset(profile.PanelWidth, profile.PanelHeight)
	hubConstraint.MinSize = Vector2.new(math.min(280, profile.PanelWidth), math.min(240, profile.PanelHeight))
	hubConstraint.MaxSize = Vector2.new(profile.PanelWidth, profile.PanelHeight)
	for _, descendant in ipairs(screen:GetDescendants()) do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
			local baseTextSize = descendant:GetAttribute("BaseTextSize")
			if type(baseTextSize) == "number" then
				descendant.TextSize = math.max(13, math.floor(baseTextSize * profile.Scale + 0.5))
			end
		end
	end
	menuButton.Text = if profile.IsCompact then "MENU" else "TAB  MENU"
end

local function setPage(page: string)
	local isSquadPage = page == "squad"
	medicalSummary.Visible = not isSquadPage
	weaponButtons.Visible = not isSquadPage
	squadHeading.Visible = isSquadPage
	squadBackButton.Visible = isSquadPage
	companyButton.Visible = isSquadPage
	squadName.Visible = isSquadPage
	createSquadButton.Visible = isSquadPage
	rosterMessage.Visible = isSquadPage
	rosterList.Visible = isSquadPage
	controlHelp.Visible = not isSquadPage

	for _, button in ipairs(pageScroll:GetChildren()) do
		if button:IsA("TextButton") and button.Name:match("^View_") then
			button:Destroy()
		end
	end

	if isSquadPage then
		header.Text = "ESCUADRON"
		subheader.Text = "Miembros, rango y estado actual"
		if refreshSquads ~= nil then
			task.spawn(refreshSquads)
		end
	else
		header.Text = "CENTRO TACTICO"
		subheader.Text = "Inventario y sistemas de mision"
		local viewItems = {
			{ Id = "squad", Label = "Escuadron y miembros" },
			{ Id = "medical", Label = "Medicina y tratamientos" },
			{ Id = "radio", Label = "Radio y mensajes" },
			{ Id = "mission", Label = "Objetivos y partida" },
			{ Id = "logistics", Label = "Logistica y vehiculos" },
		}
		for index, item in ipairs(viewItems) do
			local button = addButton(pageScroll, `View_{item.Id}`, item.Label, 2 + index)
			button.Activated:Connect(function()
				if item.Id == "squad" then
					setPage("squad")
					return
				end
				hub.Visible = false
				closeMenu()
				statusCard.Visible = false
				for _, gui in pairs(viewGuis) do
					gui.Enabled = false
				end
				local gui = viewGuis[item.Id]
				if gui ~= nil then
					gui.Enabled = true
				end
				if item.Id == "radio" and refreshRadio ~= nil then
					refreshRadio()
				end
			end)
		end
	end

	squadBackButton.Activated:Connect(function()
		setPage("home")
	end)
end

local function openMenu()
	for _, gui in pairs(viewGuis) do
		gui.Enabled = false
	end
	setPage("home")
	hub.Visible = true
	statusCard.Visible = true
	menuButton.Text = "CERRAR"
	if refreshSquads ~= nil then
		task.spawn(refreshSquads)
	end
	if refreshRadio ~= nil then
		refreshRadio()
	end
end

closeMenu = function()
	hub.Visible = false
	menuButton.Text = if TacticalUIRules.GetProfile(
		(Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize.X) or 1280,
		(Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize.Y) or 720
	).IsCompact then "MENU" else "TAB  MENU"
end

menuButton.Activated:Connect(function()
	if hub.Visible then
		closeMenu()
	else
		openMenu()
	end
end)

local function makeRosterRow(order: number, text: string, actionText: string?, callback: (() -> ())?)
	local row = Instance.new("Frame")
	row.Name = `RosterRow{order}`
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, if callback ~= nil then 54 else 44)
	row.BackgroundColor3 = COLORS.Surface
	row.BorderSizePixel = 0
	row.Parent = rosterList
	round(row, 6)

	local label = addText(row, "Member", text, 13, COLORS.Text)
	label.Position = UDim2.new(0, 9, 0, 3)
	label.Size = UDim2.new(if callback ~= nil then 0.68 else 1, -12, 1, -6)

	if callback ~= nil and actionText ~= nil then
		local button = Instance.new("TextButton")
		button.Name = "Action"
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -6, 0.5, 0)
		button.Size = UDim2.new(0.3, -4, 0, 42)
		button.BackgroundColor3 = COLORS.SurfaceActive
		button.BorderSizePixel = 0
		button.Font = Enum.Font.GothamSemibold
		button.Text = actionText
		button.TextColor3 = COLORS.Text
		button.TextSize = math.max(13, math.floor(12 * currentTextScale + 0.5))
		button:SetAttribute("BaseTextSize", 12)
		button.TextWrapped = true
		button.Parent = row
		round(button, 6)
		button.Activated:Connect(callback)
	end
end

local function showSquadState(response: any)
	clearRoster()
	if type(response) ~= "table" or response.ok ~= true then
		setStatusMessage(`No se pudo leer el escuadron: {if type(response) == "table" then response.code or "error" else "sin respuesta"}`)
		return
	end
	setStatusMessage("Los rangos y el estado los proporciona el servidor.")
	local currentUserSquad: any = nil
	for _, squad in ipairs(response.squads or {}) do
		for _, member in ipairs(squad.members or {}) do
			if member.userId == player.UserId then
				currentUserSquad = squad
				break
			end
		end
	end
	if currentUserSquad ~= nil then
		makeRosterRow(1, `{currentUserSquad.name}  |  {currentUserSquad.companyId}`, nil, nil)
		local memberOrder = 2
		for _, member in ipairs(currentUserSquad.members or {}) do
			makeRosterRow(
				memberOrder,
				string.format(
					"%s  |  %s / %s  |  %s",
					member.displayName or `Jugador {member.userId}`,
					member.rank or "Sin rango",
					member.role or "Sin rol",
					member.status or "Desconocido"
				),
				nil,
				nil
			)
			memberOrder += 1
		end
		local leave = addButton(rosterList, "LeaveSquad", "Salir del escuadron", memberOrder)
		leave.Size = UDim2.new(1, 0, 0, 46)
		leave.Activated:Connect(function()
			local ok, result = pcall(function()
				return squadRemote:InvokeServer({ action = "leave" })
			end)
			if not ok then
				setStatusMessage("Error de red al salir del escuadron.")
			elseif type(result) == "table" then
				setStatusMessage(if result.ok then "Saliste del escuadron." else `No se pudo salir: {result.code}`)
				task.defer(function()
					local success, latest = pcall(function()
						return squadRemote:InvokeServer({ action = "list" })
					end)
					if success then
						showSquadState(latest)
					end
				end)
			end
		end)
	else
		makeRosterRow(1, "No perteneces a un escuadron.", nil, nil)
		local order = 2
		for _, squad in ipairs(response.squads or {}) do
			local title = `{squad.name}  |  {#squad.members}/{squad.maxMembers or 8}`
			makeRosterRow(order, title, "UNIRSE", function()
				local ok, result = pcall(function()
					return squadRemote:InvokeServer({
						action = "join",
						squadId = squad.id,
					})
				end)
				if not ok then
					setStatusMessage("Error de red al unirse.")
				elseif type(result) == "table" then
					setStatusMessage(if result.ok then "Te uniste al escuadron." else `No se pudo unir: {result.code}`)
					task.defer(function()
						local success, latest = pcall(function()
							return squadRemote:InvokeServer({ action = "list" })
						end)
						if success then
							showSquadState(latest)
						end
					end)
				end
			end)
			order += 1
		end
	end
end

local squadList: { any } = {}
local selectedCompany = "sierra"
companyButton.Activated:Connect(function()
	if #squadList == 0 then
		return
	end
	local selectedIndex = 0
	for index, company in ipairs(squadList) do
		if company.id == selectedCompany then
			selectedIndex = index
			break
		end
	end
	local nextCompany = squadList[selectedIndex % #squadList + 1]
	selectedCompany = nextCompany.id
	companyButton.Text = `Compania: {nextCompany.name}`
end)

createSquadButton.Activated:Connect(function()
	local name = squadName.Text
	local ok, result = pcall(function()
		return squadRemote:InvokeServer({
			action = "create",
			name = name,
			companyId = selectedCompany,
		})
	end)
	if not ok then
		setStatusMessage("Error de red al crear el escuadron.")
	elseif type(result) == "table" then
		setStatusMessage(if result.ok then "Escuadron creado." else `No se pudo crear: {result.code}`)
		local success, latest = pcall(function()
			return squadRemote:InvokeServer({ action = "list" })
		end)
		if success then
			showSquadState(latest)
		end
	end
end)

rifleButton.Activated:Connect(function()
	combatRemote:FireServer({ action = "equip", weaponId = "Rifle" })
end)
sidearmButton.Activated:Connect(function()
	combatRemote:FireServer({ action = "equip", weaponId = "Sidearm" })
end)

local latestMedicalStatus: any = nil
local function requestMedicalStatus()
	combatRemote:FireServer({ action = "medical_status" })
end

local function renderMedicalStatus(status: any)
	if type(status) ~= "table" then
		return
	end
	latestMedicalStatus = status
	local health = if type(status.health) == "number" then status.health else 0
	local maxHealth = if type(status.maxHealth) == "number" then status.maxHealth else 0
	local wounds = if type(status.wounds) == "number" then status.wounds else 0
	local bleedRate = if type(status.bleedRate) == "number" then status.bleedRate else 0
	local incapacitated = status.incapacitated == true
	local condition = TacticalUIRules.GetCondition(health, maxHealth, wounds, bleedRate, incapacitated)
	healthText.Text = string.format("SALUD  %d / %d", math.floor(health), math.floor(maxHealth))
	conditionText.Text = condition
	conditionText.TextColor3 = if incapacitated or bleedRate > 0 then COLORS.Danger else COLORS.Accent

	local weaponId = if type(status.equippedWeaponId) == "string" then status.equippedWeaponId else "Rifle"
	local weapons = if type(status.weapons) == "table" then status.weapons else {}
	local weapon = weapons[weaponId]
	if type(weapon) == "table" then
		ammoText.Text = `{status.weaponName or weaponId}  {TacticalUIRules.GetAmmoText(
			if type(weapon.magazine) == "number" then weapon.magazine else 0,
			if type(weapon.reserve) == "number" then weapon.reserve else 0,
			weapon.isReloading == true
		)}`
	else
		ammoText.Text = "MUNICION  sincronizando"
	end

	local items = if type(status.medicalItems) == "table" then status.medicalItems else {}
	local summaryLines = {
		`Condicion: {condition}`,
		`Rol: {status.role or "Rifleman"}`,
		`Heridas: {wounds}  |  Sangrado: {string.format("%.1f", bleedRate)}/s`,
		`Arma: {status.weaponName or weaponId}`,
		`Cargador: {if type(weapon) == "table" then weapon.magazine or 0 else "--"}  |  Reserva: {if type(weapon) == "table" then weapon.reserve or 0 else "--"}`,
		`Vendajes: {items.Bandage or 0}  |  Botiquines: {items.Medkit or 0}  |  Emergencia: {items.EmergencyKit or 0}`,
	}
	medicalSummary.Text = table.concat(summaryLines, "\n")
end

combatRemote.OnClientEvent:Connect(function(message: any)
	if type(message) == "table" and message.action == "medical_status" then
		renderMedicalStatus(message)
	elseif type(message) == "table" and message.action == "result" and message.ok == true then
		if message.requestAction == "equip" or message.requestAction == "shoot" or message.requestAction == "reload" then
			task.delay(0.15, function()
				requestMedicalStatus()
			end)
		end
	end
end)

refreshSquads = function()
	local ok, response = pcall(function()
		return squadRemote:InvokeServer({ action = "list" })
	end)
	if not ok then
		setStatusMessage("No se pudo consultar la lista de escuadrones.")
		return
	end
	if type(response) == "table" and type(response.companies) == "table" then
		squadList = response.companies
		for _, company in ipairs(squadList) do
			if company.id == selectedCompany then
				companyButton.Text = `Compania: {company.name}`
				break
			end
		end
	end
	showSquadState(response)
end
refreshRadio = function()
	local radio = viewGuis.radio
	if radio ~= nil then
		local remote = remotes:FindFirstChild("RadioRequest")
		if remote ~= nil and remote:IsA("RemoteEvent") then
			remote:FireServer({ action = "state" })
		end
	end
end

for view, name in pairs(viewGuiNames) do
	task.spawn(function()
		local gui = playerGui:WaitForChild(name, 30)
		if gui ~= nil and gui:IsA("ScreenGui") then
			viewGuis[view] = gui
			gui.Enabled = false
		end
	end)
end

local function toggleMenuAction(_, inputState: Enum.UserInputState, inputObject: InputObject)
	if inputState == Enum.UserInputState.Begin then
		if UserInputService:GetFocusedTextBox() ~= nil then
			return Enum.ContextActionResult.Pass
		end
		if inputObject.KeyCode == Enum.KeyCode.Escape and not hub.Visible then
			return Enum.ContextActionResult.Pass
		end
		if hub.Visible then
			closeMenu()
		else
			openMenu()
		end
	end
	return Enum.ContextActionResult.Sink
end

ContextActionService:BindAction("SierraTacticalMenu", toggleMenuAction, false, Enum.KeyCode.Tab, Enum.KeyCode.Escape)

player.CharacterAdded:Connect(function(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid ~= nil and humanoid:IsA("Humanoid") then
		humanoid.HealthChanged:Connect(function(health)
			if latestMedicalStatus ~= nil then
				latestMedicalStatus.health = health
				renderMedicalStatus(latestMedicalStatus)
			end
		end)
	end
	task.delay(0.5, requestMedicalStatus)
end)

if player.Character ~= nil then
	task.defer(function()
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid ~= nil then
			humanoid.HealthChanged:Connect(function(health)
				if latestMedicalStatus ~= nil then
					latestMedicalStatus.health = health
					renderMedicalStatus(latestMedicalStatus)
				end
			end)
		end
		requestMedicalStatus()
	end)
end

task.spawn(function()
	while screen.Parent ~= nil do
		task.wait(2)
		requestMedicalStatus()
		if hub.Visible and header.Text == "ESCUADRON" then
			refreshSquads()
		end
	end
end)

updateProfile()
local camera = Workspace.CurrentCamera
if camera ~= nil then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateProfile)
end
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	local currentCamera = Workspace.CurrentCamera
	if currentCamera ~= nil then
		currentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateProfile)
		updateProfile()
	end
end)
refreshSquads()
setPage("home")
