--!strict

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local combatRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CombatRequest") :: RemoteEvent
local config = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("config"):WaitForChild("InventoryConfig") :: ModuleScript
)
local uiRules = require(ReplicatedStorage.Shared.config:WaitForChild("TacticalUIRules") :: ModuleScript)
local recoilRandom = Random.new()
local status: any = nil

local screen = Instance.new("ScreenGui")
screen.Name = "SierraCombatControls"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 10
screen.Parent = playerGui

local reticle = Instance.new("TextLabel")
reticle.Name = "Reticle"
reticle.AnchorPoint = Vector2.new(0.5, 0.5)
reticle.Position = UDim2.fromScale(0.5, 0.5)
reticle.Size = UDim2.fromOffset(24, 24)
reticle.BackgroundTransparency = 1
reticle.Text = "+"
reticle.TextSize = 24
reticle.TextColor3 = Color3.new(1, 1, 1)
reticle.TextStrokeTransparency = 0.3
reticle.Parent = screen

local controls = Instance.new("Frame")
controls.Name = "TouchActions"
controls.AnchorPoint = Vector2.new(1, 1)
-- Reserve the bottom-right region for Roblox's jump button.
controls.Position = UDim2.new(1, -24, 1, -150)
controls.Size = UDim2.fromOffset(176, 120)
controls.BackgroundTransparency = 1
controls.Parent = screen

local feedback = Instance.new("TextLabel")
feedback.Name = "CombatFeedback"
feedback.AnchorPoint = Vector2.new(0.5, 1)
feedback.Position = UDim2.new(0.5, 0, 1, -24)
feedback.Size = UDim2.new(0.6, 0, 0, 48)
feedback.BackgroundTransparency = 1
feedback.TextColor3 = Color3.new(1, 1, 1)
feedback.TextStrokeTransparency = 0.3
feedback.TextSize = 16
feedback.TextWrapped = true
feedback.Text = ""
feedback.Parent = screen

local function canAct(): boolean
	local character = player.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	return humanoid ~= nil
		and humanoid.Health > 0
		and character ~= nil
		and character:GetAttribute("SierraIncapacitated") ~= true
		and playerGui:GetAttribute("SierraMenuOpen") ~= true
		and not GuiService.MenuIsOpen
		and UserInputService:GetFocusedTextBox() == nil
end

local function request(action: string, weaponId: string?)
	if not canAct() then
		return
	end
	if action ~= "shoot" then
		combatRemote:FireServer({ action = action, weaponId = weaponId })
		return
	end
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local head = if character ~= nil then character:FindFirstChild("Head") else nil
	if camera == nil or head == nil or not head:IsA("BasePart") then
		return
	end
	local weaponId = if status ~= nil then status.equippedWeaponId else config.DefaultWeapon
	local weapon = config.Weapons[weaponId] or config.Weapons[config.DefaultWeapon]
	local ray = camera:ViewportPointToRay(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character :: Model }
	params.IgnoreWater = true
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * weapon.Range, params)
	local aimPoint = if hit ~= nil then hit.Position else ray.Origin + ray.Direction * weapon.Range
	local offset = aimPoint - head.Position
	if offset.Magnitude < 0.001 then
		return
	end
	-- Only intent is sent. The server still casts from its own head and applies range/damage rules.
	local direction = if offset:Dot(ray.Direction) > 0 then offset.Unit else ray.Direction
	combatRemote:FireServer({ action = "shoot", direction = { x = direction.X, y = direction.Y, z = direction.Z } })
end

local function addButton(
	name: string,
	title: string,
	column: number,
	row: number,
	action: string,
	weaponId: string?
): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Position = UDim2.fromOffset(column * 92, row * 64)
	button.Size = UDim2.fromOffset(84, 56)
	button.BackgroundColor3 = Color3.fromRGB(31, 42, 41)
	button.BackgroundTransparency = 0.15
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextSize = 15
	button.TextWrapped = true
	button.Text = title
	button.Parent = controls
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button
	button.Activated:Connect(function()
		request(action, weaponId)
	end)
	return button
end

local rifle = addButton("Rifle", "Fusil", 0, 0, "equip", "Rifle")
local sidearm = addButton("Sidearm", "Pistola", 0, 1, "equip", "Sidearm")
local fire = addButton("Fire", "Disparar", 1, 0, "shoot", nil)
local reload = addButton("Reload", "Recargar", 1, 1, "reload", nil)

local function bind(name: string, action: string, weaponId: string?, key: EnumItem)
	ContextActionService:BindAction(name, function(_, inputState)
		if not canAct() then
			return Enum.ContextActionResult.Pass
		end
		if inputState == Enum.UserInputState.Begin then
			request(action, weaponId)
		end
		return Enum.ContextActionResult.Sink
	end, false, key)
end

-- Touch input belongs only to the dedicated buttons, leaving camera drags and joystick touches alone.
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not gameProcessed and input.UserInputType == Enum.UserInputType.MouseButton1 then
		request("shoot", nil)
	end
end)
bind("SierraCombatReload", "reload", nil, Enum.KeyCode.R)
bind("SierraEquipRifle", "equip", "Rifle", Enum.KeyCode.One)
bind("SierraEquipSidearm", "equip", "Sidearm", Enum.KeyCode.Two)

local feedbackVersion = 0
combatRemote.OnClientEvent:Connect(function(message: any)
	if type(message) ~= "table" then
		return
	end
	local snapshot = if message.action == "medical_status" then message else message.status
	if type(snapshot) == "table" then
		if snapshot.character ~= player.Character then
			return
		end
		status = snapshot
	end
	if message.action ~= "result" then
		return
	end
	local text = uiRules.GetCombatMessage(message.code, message.ok == true)
	if text ~= "" then
		feedbackVersion += 1
		local version = feedbackVersion
		feedback.Text = text
		task.delay(3, function()
			if feedbackVersion == version then
				feedback.Text = ""
			end
		end)
	end
	local recoil = message.recoil
	local camera = Workspace.CurrentCamera
	if message.ok == true and type(recoil) == "table" and camera ~= nil and canAct() then
		local yaw = recoilRandom:NextNumber(-recoil.yawDegrees, recoil.yawDegrees)
		camera.CFrame *= CFrame.Angles(-math.rad(recoil.pitchDegrees), math.rad(yaw), 0)
	end
end)

player.CharacterAdded:Connect(function()
	status = nil
	feedbackVersion += 1
	feedback.Text = ""
end)

local elapsed = 0
RunService.Heartbeat:Connect(function(deltaSeconds)
	elapsed += deltaSeconds
	if elapsed < 0.1 then
		return
	end
	elapsed = 0
	local available = canAct()
	local camera = Workspace.CurrentCamera
	local height = if camera ~= nil then camera.ViewportSize.Y else 720
	controls.Position = UDim2.new(1, -24, 1, -math.min(150, math.floor(height * 0.32)))
	controls.Visible = UserInputService.TouchEnabled and available
	reticle.Visible = available
	local weaponId = if status ~= nil then status.equippedWeaponId else nil
	local weapon = if status ~= nil then status.weapons[weaponId] else nil
	local reloading = weapon ~= nil and weapon.isReloading == true
	for _, button in ipairs({ rifle, sidearm }) do
		button.Interactable = not reloading
		button.BackgroundColor3 = if button.Name == weaponId
			then Color3.fromRGB(51, 100, 66)
			else Color3.fromRGB(31, 42, 41)
	end
	fire.Interactable = not reloading and weapon ~= nil and weapon.magazine > 0
	fire.Text = if weapon ~= nil and weapon.magazine <= 0 then "Sin municion" else "Disparar"
	reload.Interactable = not reloading
	if reloading and type(weapon.reloadEndsAt) == "number" then
		reload.Text = string.format("Recarga %.1fs", math.max(0, weapon.reloadEndsAt - Workspace:GetServerTimeNow()))
	else
		reload.Text = if reloading then "Recargando" else "Recargar"
	end
end)
