--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local combatRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CombatRequest") :: RemoteEvent
local playerGui = player:WaitForChild("PlayerGui")

local screen = Instance.new("ScreenGui")
screen.Name = "SierraMedical"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = false
screen.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "MedicalPanel"
panel.AnchorPoint = Vector2.new(0, 1)
panel.Position = UDim2.new(0, 12, 1, -12)
panel.Size = UDim2.new(0, 270, 0, 204)
panel.BackgroundColor3 = Color3.fromRGB(22, 29, 31)
panel.BackgroundTransparency = 0.12
panel.BorderSizePixel = 0
panel.Parent = screen

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = panel

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "Status"
statusLabel.Position = UDim2.new(0, 10, 0, 8)
statusLabel.Size = UDim2.new(1, -20, 0, 52)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.GothamMedium
statusLabel.TextColor3 = Color3.fromRGB(240, 240, 230)
statusLabel.TextSize = 14
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextYAlignment = Enum.TextYAlignment.Top
statusLabel.TextWrapped = true
statusLabel.Text = "Estado medico: sincronizando..."
statusLabel.Parent = panel

local function createButton(name: string, title: string, x: number, width: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Position = UDim2.new(0, x, 0, 68)
	button.Size = UDim2.new(0, width, 0, 54)
	button.BackgroundColor3 = Color3.fromRGB(50, 78, 72)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamSemibold
	button.Text = title
	button.TextColor3 = Color3.fromRGB(255, 255, 245)
	button.TextSize = 13
	button.TextWrapped = true
	button.Parent = panel
	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 6)
	buttonCorner.Parent = button
	return button
end

local bandageButton = createButton("Bandage", "Vendaje [3]", 10, 78)
local medkitButton = createButton("Medkit", "Botiquin [4]", 96, 78)
local reviveButton = createButton("Revive", "Ayudar [H]", 182, 78)
local cancelButton = createButton("Cancel", "Cancelar tratamiento", 10, 250)
cancelButton.Position = UDim2.new(0, 10, 0, 132)
cancelButton.Size = UDim2.new(0, 250, 0, 44)
cancelButton.BackgroundColor3 = Color3.fromRGB(95, 65, 48)

local latestStatus: { [string]: any }? = nil
local currentHumanoid: Humanoid? = nil
local healthConnections: { RBXScriptConnection } = {}

local function requestItem(itemId: string, targetUserId: number)
	combatRemote:FireServer({
		action = "treat",
		itemId = itemId,
		targetUserId = targetUserId,
	})
end

local function nearestDownedAlly(): Player?
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	local nearest: Player? = nil
	local nearestDistance = math.huge
	for _, candidate in ipairs(Players:GetPlayers()) do
		if candidate ~= player then
			local targetCharacter = candidate.Character
			local targetRoot = if targetCharacter ~= nil
				then targetCharacter:FindFirstChild("HumanoidRootPart")
				else nil
			if
				targetCharacter ~= nil
				and targetCharacter:GetAttribute("SierraIncapacitated") == true
				and targetRoot ~= nil
				and targetRoot:IsA("BasePart")
			then
				local distance = (root.Position - targetRoot.Position).Magnitude
				if distance < nearestDistance then
					nearestDistance = distance
					nearest = candidate
				end
			end
		end
	end
	return nearest
end

local function renderStatus()
	local status = latestStatus
	if status == nil then
		return
	end
	local items = status.medicalItems or {}
	local condition = if status.incapacitated
		then "INCAPACITADO"
		elseif (status.bleedRate or 0) > 0 then `Sangrando ({status.bleedRate}/s)`
		elseif (status.wounds or 0) > 0 then `Heridas: {status.wounds}`
		else "Estable"
	local health = if currentHumanoid ~= nil then currentHumanoid.Health else status.health or 0
	if status.incapacitated then
		health = math.min(health, status.health or health)
	end
	statusLabel.Text = string.format(
		"Salud: %d / %d\n%s\nVendajes: %d  Botiquines: %d  Emergencia: %d",
		math.floor(health),
		math.floor(if currentHumanoid ~= nil then currentHumanoid.MaxHealth else status.maxHealth or 0),
		condition,
		items.Bandage or 0,
		items.Medkit or 0,
		items.EmergencyKit or 0
	)
end

bandageButton.Activated:Connect(function()
	requestItem("Bandage", player.UserId)
end)
medkitButton.Activated:Connect(function()
	requestItem("Medkit", player.UserId)
end)
reviveButton.Activated:Connect(function()
	local target = nearestDownedAlly()
	if target ~= nil then
		requestItem("EmergencyKit", target.UserId)
	else
		statusLabel.Text = "No hay aliado incapacitado cerca."
	end
end)
cancelButton.Activated:Connect(function()
	combatRemote:FireServer({ action = "cancel_treatment" })
end)

ContextActionService:BindAction("SierraUseBandage", function(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		requestItem("Bandage", player.UserId)
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.Three)
ContextActionService:BindAction("SierraUseMedkit", function(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		requestItem("Medkit", player.UserId)
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.Four)
ContextActionService:BindAction("SierraReviveAlly", function(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		local target = nearestDownedAlly()
		if target ~= nil then
			requestItem("EmergencyKit", target.UserId)
		end
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.H)

combatRemote.OnClientEvent:Connect(function(message: any)
	if type(message) ~= "table" then
		return
	end
	local snapshot = if message.action == "medical_status" then message else message.status
	if type(snapshot) == "table" and snapshot.character == player.Character then
		latestStatus = snapshot
		renderStatus()
	elseif message.action == "medical_result" then
		statusLabel.Text = if message.ok then `Accion medica: {message.code}` else `No se pudo tratar: {message.code}`
	end
end)

local function bindCharacter(character: Model)
	for _, connection in ipairs(healthConnections) do
		connection:Disconnect()
	end
	table.clear(healthConnections)
	latestStatus = nil
	currentHumanoid = nil
	statusLabel.Text = "Estado medico: sincronizando..."
	local humanoid = character:WaitForChild("Humanoid", 10)
	if player.Character ~= character then
		return
	end
	if humanoid ~= nil and humanoid:IsA("Humanoid") then
		currentHumanoid = humanoid
		table.insert(healthConnections, humanoid.HealthChanged:Connect(renderStatus))
		table.insert(healthConnections, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(renderStatus))
	end
	combatRemote:FireServer({ action = "medical_status" })
end

player.CharacterAdded:Connect(bindCharacter)
if player.Character ~= nil then
	task.spawn(bindCharacter, player.Character)
end
