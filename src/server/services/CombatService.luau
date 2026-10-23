--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local InventoryService = require(script.Parent.InventoryService)
local MedicalService = require(script.Parent.MedicalService)
local LogisticsService = require(script.Parent.LogisticsService)
local CombatRequestRules = require(script.Parent.CombatRequestRules)
local CombatRules = require(script.Parent.CombatRules)

local shared = ReplicatedStorage:WaitForChild("Shared")
local configFolder = shared:WaitForChild("config")
local configModule = configFolder:WaitForChild("InventoryConfig") :: ModuleScript
local config = require(configModule)
local remoteFolder = ReplicatedStorage:WaitForChild("Remotes")
local requestRemote = remoteFolder:WaitForChild("CombatRequest") :: RemoteEvent

local REQUEST_WINDOW_SECONDS = 1
local MAX_REQUESTS_PER_WINDOW = 30

type RateBucket = {
	WindowStartedAt: number,
	Count: number,
}

local requestBuckets: { [Player]: RateBucket } = {}
local lastShotAt: { [Player]: number } = {}
local isStarted = false
local playerRemovingConnection: RBXScriptConnection? = nil
local remoteConnection: RBXScriptConnection? = nil

local CombatService = {}

local function sendResult(player: Player, response: { [string]: any })
	if player.Parent == Players then
		if response.action == "result" or response.action == "logistics_result" then
			response.status = MedicalService.GetStatus(player)
		end
		requestRemote:FireClient(player, response)
	end
end

local function getAliveCharacter(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if
		character == nil
		or not character:IsDescendantOf(Workspace)
		or character:GetAttribute("SierraIncapacitated") == true
	then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local head = character:FindFirstChild("Head")
	if humanoid == nil or humanoid.Health <= 0 or head == nil or not head:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, head
end

local function findHumanoidModel(hitInstance: Instance): (Model?, Humanoid?)
	local current: Instance? = hitInstance
	while current ~= nil and current ~= Workspace do
		if current:IsA("Model") then
			local humanoid = current:FindFirstChildOfClass("Humanoid")
			if humanoid ~= nil then
				return current, humanoid
			end
		end
		current = current.Parent
	end
	return nil, nil
end

local function processShot(player: Player, directionData: { x: number, y: number, z: number })
	local character, _, head = getAliveCharacter(player)
	if character == nil or head == nil then
		return { action = "result", requestAction = "shoot", ok = false, code = "attacker_unavailable" }
	end

	local inventory = InventoryService.GetInventory(player)
	if inventory == nil then
		return { action = "result", requestAction = "shoot", ok = false, code = "inventory_unavailable" }
	end
	local weaponId = inventory.EquippedWeaponId
	local weapon = config.Weapons[weaponId]
	local weaponState = inventory.Weapons[weaponId]
	if weapon == nil or weaponState == nil then
		return { action = "result", requestAction = "shoot", ok = false, code = "invalid_weapon" }
	end

	local now = os.clock()
	local canFire, fireError = CombatRules.CanFire(
		lastShotAt[player],
		now,
		60 / weapon.RoundsPerMinute,
		weaponState.Magazine,
		weaponState.IsReloading,
		true
	)
	if not canFire then
		return { action = "result", requestAction = "shoot", ok = false, code = fireError }
	end
	local consumed, consumeError = InventoryService.ConsumeAmmo(player)
	if not consumed then
		return { action = "result", requestAction = "shoot", ok = false, code = consumeError }
	end
	lastShotAt[player] = now

	local direction = Vector3.new(directionData.x, directionData.y, directionData.z).Unit
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { character }
	raycastParams.IgnoreWater = true
	local raycastResult = Workspace:Raycast(head.Position, direction * weapon.Range, raycastParams)

	local code = "miss"
	if raycastResult ~= nil then
		local targetCharacter, targetHumanoid = findHumanoidModel(raycastResult.Instance)
		if targetCharacter == nil or targetHumanoid == nil then
			code = "blocked"
		else
			local rootPart = targetCharacter:FindFirstChild("HumanoidRootPart")
			local targetPlayer = Players:GetPlayerFromCharacter(targetCharacter)
			local isValidTarget = CombatRules.CanDamageTarget(
				character,
				targetCharacter,
				true,
				rootPart ~= nil and rootPart:IsA("BasePart"),
				targetHumanoid.Health
			) and targetPlayer ~= player and CombatRules.IsWithinRange(
				(raycastResult.Position - head.Position).Magnitude,
				weapon.Range
			)
			if isValidTarget then
				local damage = CombatRules.CalculateDamage(targetHumanoid.Health, weapon.Damage)
				local applied, damageCode = MedicalService.ApplyDamage(targetHumanoid, damage)
				code = if applied then "hit" else damageCode
			else
				code = "invalid_target"
			end
		end
	end

	return {
		action = "result",
		requestAction = "shoot",
		ok = true,
		code = code,
		recoil = {
			pitchDegrees = weapon.Recoil.PitchDegrees,
			yawDegrees = weapon.Recoil.YawDegrees,
		},
	}
end

local function processRequest(player: Player, rawRequest: any, argumentCount: number)
	if player.Parent ~= Players then
		return { action = "result", ok = false, code = "invalid_player" }
	end

	local now = os.clock()
	local allowed, bucket =
		CombatRules.TakeRateLimitToken(requestBuckets[player], now, REQUEST_WINDOW_SECONDS, MAX_REQUESTS_PER_WINDOW)
	requestBuckets[player] = bucket
	if not allowed then
		return nil
	end

	local request, validationError = CombatRequestRules.Validate(rawRequest, argumentCount)
	if request == nil then
		return { action = "result", ok = false, code = validationError or "invalid_request" }
	end

	if request.action == "treat" or request.action == "medical_status" or request.action == "cancel_treatment" then
		return MedicalService.HandleRequest(player, request)
	elseif request.action == "logistics" then
		return LogisticsService.HandleRequest(player, request)
	end

	if request.action == "shoot" then
		return processShot(player, request.direction :: { x: number, y: number, z: number })
	elseif request.action == "reload" then
		local character = getAliveCharacter(player)
		if character == nil then
			return { action = "result", requestAction = "reload", ok = false, code = "attacker_unavailable" }
		end
		local ok, code, duration, version = InventoryService.BeginReload(player)
		if not ok or duration == nil or version == nil then
			return { action = "result", requestAction = "reload", ok = false, code = code }
		end
		task.delay(duration, function()
			local completed, amount = InventoryService.CompleteReload(player, version)
			if completed then
				sendResult(player, {
					action = "result",
					requestAction = "reload",
					ok = true,
					code = "reload_complete",
					loaded = amount,
				})
			end
		end)
		return { action = "result", requestAction = "reload", ok = true, code = "reload_started" }
	elseif request.action == "equip" then
		if getAliveCharacter(player) == nil then
			return { action = "result", requestAction = "equip", ok = false, code = "attacker_unavailable" }
		end
		local equipped, code = InventoryService.EquipWeapon(player, request.weaponId)
		if not equipped then
			return { action = "result", requestAction = "equip", ok = false, code = code }
		end
		return {
			action = "result",
			requestAction = "equip",
			ok = true,
			code = code,
			weaponId = request.weaponId,
		}
	end

	return { action = "result", ok = false, code = "invalid_action" }
end

function CombatService.Start()
	if isStarted then
		return
	end
	isStarted = true
	remoteConnection = requestRemote.OnServerEvent:Connect(function(player: Player, ...: any)
		local arguments = table.pack(...)
		local response = processRequest(player, arguments[1], arguments.n)
		if response ~= nil then
			sendResult(player, response)
		end
	end)
	playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
		requestBuckets[player] = nil
		lastShotAt[player] = nil
	end)
end

function CombatService.Stop()
	if not isStarted then
		return
	end
	isStarted = false
	if playerRemovingConnection ~= nil then
		playerRemovingConnection:Disconnect()
		playerRemovingConnection = nil
	end
	if remoteConnection ~= nil then
		remoteConnection:Disconnect()
		remoteConnection = nil
	end
	table.clear(requestBuckets)
	table.clear(lastShotAt)
end

return table.freeze(CombatService)
