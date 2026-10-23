--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local missionRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MissionRequest") :: RemoteEvent
local playerGui = player:WaitForChild("PlayerGui")

local screen = Instance.new("ScreenGui")
screen.Name = "SierraMission"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = false
screen.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "MissionPanel"
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.Position = UDim2.new(0.5, 0, 0, 10)
panel.Size = UDim2.new(0.94, 0, 0, 206)
panel.BackgroundColor3 = Color3.fromRGB(22, 29, 31)
panel.BackgroundTransparency = 0.1
panel.BorderSizePixel = 0
panel.Parent = screen

local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MinSize = Vector2.new(280, 150)
sizeLimit.MaxSize = Vector2.new(520, 206)
sizeLimit.Parent = panel

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = panel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Position = UDim2.new(0, 12, 0, 8)
title.Size = UDim2.new(0.58, 0, 0, 26)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.Text = "MISION COOPERATIVA"
title.TextColor3 = Color3.fromRGB(236, 240, 225)
title.TextSize = 15
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel

local matchStatus = Instance.new("TextLabel")
matchStatus.Name = "MatchStatus"
matchStatus.Position = UDim2.new(0.58, -8, 0, 8)
matchStatus.Size = UDim2.new(0.42, -4, 0, 26)
matchStatus.BackgroundTransparency = 1
matchStatus.Font = Enum.Font.GothamSemibold
matchStatus.Text = "Estado: conectando"
matchStatus.TextColor3 = Color3.fromRGB(202, 213, 180)
matchStatus.TextSize = 13
matchStatus.TextXAlignment = Enum.TextXAlignment.Right
matchStatus.TextTruncate = Enum.TextTruncate.AtEnd
matchStatus.Parent = panel

local squadStatus = Instance.new("TextLabel")
squadStatus.Name = "SquadStatus"
squadStatus.Position = UDim2.new(0, 12, 0, 30)
squadStatus.Size = UDim2.new(1, -24, 0, 18)
squadStatus.BackgroundTransparency = 1
squadStatus.Font = Enum.Font.Gotham
squadStatus.Text = ""
squadStatus.TextColor3 = Color3.fromRGB(202, 213, 180)
squadStatus.TextSize = 11
squadStatus.TextXAlignment = Enum.TextXAlignment.Left
squadStatus.TextTruncate = Enum.TextTruncate.AtEnd
squadStatus.Parent = panel

local objectiveList = Instance.new("ScrollingFrame")
objectiveList.Name = "ObjectiveList"
objectiveList.Position = UDim2.new(0, 10, 0, 52)
objectiveList.Size = UDim2.new(1, -20, 1, -62)
objectiveList.BackgroundColor3 = Color3.fromRGB(14, 19, 20)
objectiveList.BackgroundTransparency = 0.08
objectiveList.BorderSizePixel = 0
objectiveList.CanvasSize = UDim2.new()
objectiveList.AutomaticCanvasSize = Enum.AutomaticSize.Y
objectiveList.ScrollBarThickness = 5
objectiveList.ScrollingDirection = Enum.ScrollingDirection.Y
objectiveList.Parent = panel

local listCorner = Instance.new("UICorner")
listCorner.CornerRadius = UDim.new(0, 6)
listCorner.Parent = objectiveList

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 7)
padding.PaddingBottom = UDim.new(0, 7)
padding.PaddingLeft = UDim.new(0, 8)
padding.PaddingRight = UDim.new(0, 8)
padding.Parent = objectiveList

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 4)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = objectiveList

local STATUS_NAMES = {
	waiting = "Esperando jugadores",
	preparation = "Preparacion",
	active = "Partida activa",
	victory = "Victoria",
	defeat = "Derrota",
	ended = "Finalizando partida",
}

local OBJECTIVE_STATUS = {
	active = "EN CURSO",
	complete = "COMPLETADO",
	locked = "PENDIENTE",
}

local function renderState(state: any)
	if type(state.status) ~= "string" then
		return
	end
	local statusName = STATUS_NAMES[state.status] or state.status
	local round = if type(state.round) == "number" then state.round else 0
	local remaining = if type(state.secondsRemaining) == "number"
		then string.format("  %ds", state.secondsRemaining)
		else ""
	matchStatus.Text = string.format("Ronda %d  |  %s%s", round, statusName, remaining)
	local participatingSquads = if type(state.participatingSquads) == "table"
		then table.concat(state.participatingSquads, ", ")
		else ""
	squadStatus.Text = if participatingSquads ~= ""
		then `Escuadrones en zona: {participatingSquads}`
		else ""

	for _, child in ipairs(objectiveList:GetChildren()) do
		if child:IsA("Frame") and child.Name == "Objective" then
			child:Destroy()
		end
	end

	if type(state.objectives) ~= "table" then
		return
	end
	for index, objective in ipairs(state.objectives) do
		if type(objective) == "table"
			and type(objective.name) == "string"
			and type(objective.description) == "string"
		then
			local row = Instance.new("Frame")
			row.Name = "Objective"
			row.LayoutOrder = index
			row.Size = UDim2.new(1, 0, 0, 52)
			row.BackgroundColor3 = Color3.fromRGB(37, 46, 44)
			row.BackgroundTransparency = if objective.status == "active" then 0 else 0.35
			row.BorderSizePixel = 0
			row.Parent = objectiveList

			local rowCorner = Instance.new("UICorner")
			rowCorner.CornerRadius = UDim.new(0, 5)
			rowCorner.Parent = row

			local status = OBJECTIVE_STATUS[objective.status] or "PENDIENTE"
			local progress = if type(objective.progress) == "number" then objective.progress else 0
			local required = if type(objective.requiredProgress) == "number" then objective.requiredProgress else 0
			local contributors = if type(objective.contributorCount) == "number"
				then objective.contributorCount
				else 0

			local text = Instance.new("TextLabel")
			text.Name = "ObjectiveText"
			text.Position = UDim2.new(0, 8, 0, 4)
			text.Size = UDim2.new(1, -16, 1, -8)
			text.BackgroundTransparency = 1
			text.Font = Enum.Font.GothamMedium
			text.Text = string.format(
				"%s  %s\n%s\nProgreso: %d / %d  |  Aportantes: %d",
				status,
				objective.name,
				objective.description,
				math.floor(progress),
				math.floor(required),
				contributors
			)
			text.TextColor3 = Color3.fromRGB(240, 240, 230)
			text.TextSize = 12
			text.TextWrapped = true
			text.TextXAlignment = Enum.TextXAlignment.Left
			text.TextYAlignment = Enum.TextYAlignment.Center
			text.Parent = row
		end
	end
	task.defer(function()
		objectiveList.CanvasPosition = Vector2.new(0, 0)
	end)
end

missionRemote.OnClientEvent:Connect(function(message: any)
	if type(message) ~= "table" then
		return
	end
	if message.action == "mission_state" and type(message.state) == "table" then
		renderState(message.state)
	elseif message.action == "mission_result" and message.ok == false then
		matchStatus.Text = `Mision: {message.code or "error"}`
	end
end)

missionRemote:FireServer({
	action = "state",
})

local function updatePanelSize()
	local camera = Workspace.CurrentCamera
	local viewportHeight = if camera ~= nil then camera.ViewportSize.Y else 720
	panel.Size = UDim2.new(0.94, 0, 0, math.max(150, math.min(206, viewportHeight - 24)))
end

updatePanelSize()
local camera = Workspace.CurrentCamera
if camera ~= nil then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(updatePanelSize)
end
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	local currentCamera = Workspace.CurrentCamera
	if currentCamera ~= nil then
		currentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updatePanelSize)
		updatePanelSize()
	end
end)
