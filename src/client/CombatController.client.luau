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
local HUDLayout = require(ReplicatedStorage.Shared:WaitForChild("HUDLayout") :: ModuleScript)
local hudFolder = script.Parent:WaitForChild("hud")
local Theme = require(hudFolder:WaitForChild("Theme") :: ModuleScript)
local Icons = require(hudFolder:WaitForChild("Icons") :: ModuleScript)
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

-- Touch buttons share the HUD's safe-area coordinate space so HUDLayout can keep them clear of the
-- native thumbstick/jump areas and of every other HUD element.
local touchScreen = Instance.new("ScreenGui")
touchScreen.Name = "SierraCombatTouch"
touchScreen.ResetOnSpawn = false
touchScreen.IgnoreGuiInset = false
touchScreen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
touchScreen.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
touchScreen.DisplayOrder = 10
touchScreen.Parent = playerGui

local feedback = Instance.new("TextLabel")
feedback.Name = "CombatFeedback"
feedback.BackgroundTransparency = 1
feedback.Font = Enum.Font.GothamBold
feedback.TextColor3 = Theme.Color.Text
feedback.TextStrokeTransparency = 0.5
feedback.TextSize = 15
feedback.TextWrapped = true
feedback.Text = ""
feedback.Parent = touchScreen

local function canAct(): boolean
	local character = player.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	return humanoid ~= nil
		and humanoid.Health > 0
		and humanoid.SeatPart == nil
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

local function addRoundButton(name: string, icon: string, tint: Color3, action: string): (TextButton, Frame, TextLabel)
	local button = Theme.Button(touchScreen, name)
	Theme.Round(button)
	local iconBox = Instance.new("Frame")
	iconBox.Name = "IconBox"
	iconBox.BackgroundTransparency = 1
	iconBox.AnchorPoint = Vector2.new(0.5, 0.5)
	iconBox.Position = UDim2.fromScale(0.5, 0.5)
	iconBox.Size = UDim2.fromScale(0.52, 0.52)
	iconBox.Parent = button
	Icons.Draw(iconBox, icon, tint, Theme.Color.Panel)
	local caption = Theme.Label(button, "Caption", "", 13, Theme.Color.Text, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
	caption.Size = UDim2.fromScale(1, 1)
	caption.Visible = false
	button.Activated:Connect(function()
		request(action, nil)
	end)
	return button, iconBox, caption
end

-- Weapons are chosen from the HUD quick slots (and keys 1/2); only fire and reload need big buttons.
local fire, fireIcon, fireCaption = addRoundButton("Fire", "bullet", Theme.Color.Accent, "shoot")
local reload, reloadIcon, reloadCaption = addRoundButton("Reload", "magazine", Theme.Color.Text, "reload")

local layout: any = nil
local function updateLayout()
	local size = touchScreen.AbsoluteSize
	layout = HUDLayout.Compute(size.X, size.Y, { Mode = "walking", Touch = true })
	local function place(gui: GuiObject, rect: any)
		gui.Position = UDim2.fromOffset(rect.X, rect.Y)
		gui.Size = UDim2.fromOffset(rect.W, rect.H)
	end
	place(fire, layout.Fire)
	place(reload, layout.Reload)
	place(feedback, { X = layout.Notice.X, Y = layout.Notice.Y - 32, W = layout.Notice.W, H = 30 })
end
touchScreen:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateLayout)
updateLayout()

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
	reticle.Visible = available
	local touchVisible = UserInputService.TouchEnabled and available
	fire.Visible, reload.Visible = touchVisible, touchVisible
	if not touchVisible then
		return
	end
	local weaponId = if status ~= nil then status.equippedWeaponId else nil
	local weapon = if status ~= nil and weaponId ~= nil then status.weapons[weaponId] else nil
	local reloading = weapon ~= nil and weapon.isReloading == true
	local empty = weapon ~= nil and weapon.magazine <= 0
	fire.Interactable = not reloading and weapon ~= nil and not empty
	fire.BackgroundTransparency = if fire.Interactable then 0.18 else 0.55
	fireIcon.Visible = not empty
	fireCaption.Visible = empty
	fireCaption.Text = if empty then "VACÍO" else ""
	fireCaption.TextColor3 = Theme.Color.Health
	reload.Interactable = not reloading
	reloadIcon.Visible = not reloading
	reloadCaption.Visible = reloading
	if reloading and type(weapon.reloadEndsAt) == "number" then
		reloadCaption.Text = string.format("%.1f", math.max(0, weapon.reloadEndsAt - Workspace:GetServerTimeNow()))
	else
		reloadCaption.Text = ""
	end
end)
