--!strict

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local combatRemote = remotes:WaitForChild("CombatRequest") :: RemoteEvent

local ACTION_FIRE = "SierraCombatFire"
local ACTION_RELOAD = "SierraCombatReload"
local ACTION_RIFLE = "SierraEquipRifle"
local ACTION_SIDEARM = "SierraEquipSidearm"
local recoilRandom = Random.new()

local function fire(_actionName: string, inputState: Enum.UserInputState)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return Enum.ContextActionResult.Sink
	end
	local direction = camera.CFrame.LookVector
	combatRemote:FireServer({
		action = "shoot",
		direction = { x = direction.X, y = direction.Y, z = direction.Z },
	})
	return Enum.ContextActionResult.Sink
end

local function reload(_actionName: string, inputState: Enum.UserInputState)
	if inputState == Enum.UserInputState.Begin then
		combatRemote:FireServer({ action = "reload" })
	end
	return Enum.ContextActionResult.Sink
end

local function equip(weaponId: string)
	return function(_actionName: string, inputState: Enum.UserInputState)
		if inputState == Enum.UserInputState.Begin then
			combatRemote:FireServer({ action = "equip", weaponId = weaponId })
		end
		return Enum.ContextActionResult.Sink
	end
end

local function presentResult(message: any)
	if type(message) ~= "table" or message.action ~= "result" or message.ok ~= true then
		return
	end
	local recoil = message.recoil
	if type(recoil) ~= "table"
		or type(recoil.pitchDegrees) ~= "number"
		or type(recoil.yawDegrees) ~= "number"
	then
		return
	end

	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	local yaw = recoilRandom:NextNumber(-recoil.yawDegrees, recoil.yawDegrees)
	camera.CFrame = camera.CFrame * CFrame.Angles(-math.rad(recoil.pitchDegrees), math.rad(yaw), 0)
end

combatRemote.OnClientEvent:Connect(presentResult)

ContextActionService:BindAction(ACTION_FIRE, fire, true, Enum.UserInputType.MouseButton1, Enum.UserInputType.Touch)
ContextActionService:SetTitle(ACTION_FIRE, "Disparar")
ContextActionService:SetPosition(ACTION_FIRE, UDim2.new(1, -84, 1, -190))
ContextActionService:BindAction(ACTION_RELOAD, reload, true, Enum.KeyCode.R)
ContextActionService:SetTitle(ACTION_RELOAD, "Recargar")
ContextActionService:SetPosition(ACTION_RELOAD, UDim2.new(1, -84, 1, -110))
ContextActionService:BindAction(ACTION_RIFLE, equip("Rifle"), true, Enum.KeyCode.One)
ContextActionService:SetTitle(ACTION_RIFLE, "Fusil")
ContextActionService:SetPosition(ACTION_RIFLE, UDim2.new(1, -176, 1, -190))
ContextActionService:BindAction(ACTION_SIDEARM, equip("Sidearm"), true, Enum.KeyCode.Two)
ContextActionService:SetTitle(ACTION_SIDEARM, "Pistola")
ContextActionService:SetPosition(ACTION_SIDEARM, UDim2.new(1, -176, 1, -110))
