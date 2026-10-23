--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local InventoryService = require(script.Parent.InventoryService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local MedicalRules = require(script.Parent.MedicalRules)

local configFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("config")
local configModule = configFolder:WaitForChild("MedicalConfig") :: ModuleScript
local config = require(configModule)
local inventoryConfig = require(configFolder:WaitForChild("InventoryConfig") :: ModuleScript)
local requestRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CombatRequest") :: RemoteEvent

type MedicalState = {
	Health: number,
	MaxHealth: number,
	Wounds: { { Severity: number, BleedRate: number } },
	BleedRate: number,
	IsIncapacitated: boolean,
	IncapacitatedUntil: number?,
}

type CharacterRecord = {
	Humanoid: Humanoid,
	State: MedicalState,
	DiedConnection: RBXScriptConnection?,
	LoopRunning: boolean,
	SavedMovement: { WalkSpeed: number, JumpPower: number, JumpHeight: number, AutoRotate: boolean }?,
}

type Treatment = {
	Actor: Player,
	Target: Player,
	ActorCharacter: Model,
	TargetCharacter: Model,
	ItemId: string,
	ReservationId: number,
}

type RateBucket = {
	WindowStartedAt: number,
	Count: number,
}

local records: { [Model]: CharacterRecord } = {}
local playerConnections: { [Player]: { RBXScriptConnection } } = {}
local serviceConnections: { RBXScriptConnection } = {}
local requestBuckets: { [Player]: RateBucket } = {}
local lastTreatmentAt: { [Player]: number } = {}
local pendingByActor: { [Player]: Treatment } = {}
local pendingByTarget: { [Player]: Treatment } = {}
local isStarted = false

local MedicalService = {}

local function getCharacterParts(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if character == nil or character.Parent == nil or not character:IsDescendantOf(Workspace) then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or humanoid.Health <= 0 or rootPart == nil or not rootPart:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, rootPart
end

local function sendStatus(player: Player)
	if player.Parent ~= Players then
		return
	end
	local status = MedicalService.GetStatus(player)
	if status ~= nil then
		requestRemote:FireClient(player, status)
	end
end

local function clearTreatment(treatment: Treatment, code: string, notify: boolean)
	if pendingByActor[treatment.Actor] == treatment then
		pendingByActor[treatment.Actor] = nil
	end
	if pendingByTarget[treatment.Target] == treatment then
		pendingByTarget[treatment.Target] = nil
	end
	InventoryService.ReleaseMedicalItem(treatment.Actor, treatment.ReservationId)
	if notify and treatment.Actor.Parent == Players then
		requestRemote:FireClient(treatment.Actor, {
			action = "medical_result",
			ok = false,
			code = code,
		})
	end
end

local function clearCharacter(character: Model)
	local record = records[character]
	if record == nil then
		return
	end
	records[character] = nil
	if record.DiedConnection ~= nil then
		record.DiedConnection:Disconnect()
		record.DiedConnection = nil
	end
	local player = Players:GetPlayerFromCharacter(character)
	if player ~= nil then
		local actorTreatment = pendingByActor[player]
		if actorTreatment ~= nil then
			clearTreatment(actorTreatment, "character_unavailable", true)
		end
		local targetTreatment = pendingByTarget[player]
		if targetTreatment ~= nil then
			clearTreatment(targetTreatment, "target_unavailable", true)
		end
	end
end

local function setIncapacitated(character: Model, record: CharacterRecord)
	if record.SavedMovement ~= nil then
		return
	end
	local humanoid = record.Humanoid
	record.SavedMovement = {
		WalkSpeed = humanoid.WalkSpeed,
		JumpPower = humanoid.JumpPower,
		JumpHeight = humanoid.JumpHeight,
		AutoRotate = humanoid.AutoRotate,
	}
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false
	character:SetAttribute("SierraIncapacitated", true)
	local player = Players:GetPlayerFromCharacter(character)
	if player ~= nil then
		InventoryService.CancelReload(player)
	end
end

local function restoreAfterRevive(character: Model, record: CharacterRecord)
	local movement = record.SavedMovement
	if movement ~= nil then
		record.Humanoid.WalkSpeed = movement.WalkSpeed
		record.Humanoid.JumpPower = movement.JumpPower
		record.Humanoid.JumpHeight = movement.JumpHeight
		record.Humanoid.AutoRotate = movement.AutoRotate
		record.SavedMovement = nil
	end
	character:SetAttribute("SierraIncapacitated", false)
end

local function isRecordCurrent(character: Model, record: CharacterRecord): boolean
	return records[character] == record and character.Parent ~= nil and record.Humanoid.Parent ~= nil
end

local function syncHealth(record: CharacterRecord)
	local humanoid = record.Humanoid
	record.State.MaxHealth = math.max(1, humanoid.MaxHealth)
	-- A downed character stays down until MedicalRules.Revive succeeds.
	if record.State.IsIncapacitated and humanoid.Health > 0 then
		record.State.Health = math.min(record.State.Health, record.State.MaxHealth)
	else
		record.State.Health = math.clamp(humanoid.Health, 0, record.State.MaxHealth)
	end
end

local function startBleedLoop(character: Model, record: CharacterRecord)
	if record.LoopRunning then
		return
	end
	record.LoopRunning = true
	task.spawn(function()
		while isRecordCurrent(character, record) and (record.State.BleedRate > 0 or record.State.IsIncapacitated) do
			task.wait(config.BleedTickSeconds)
			if not isRecordCurrent(character, record) then
				break
			end
			syncHealth(record)
			local _, expired = MedicalRules.ApplyBleedTick(record.State, config.BleedTickSeconds, os.clock(), config)
			record.Humanoid.Health = record.State.Health
			if record.State.IsIncapacitated then
				setIncapacitated(character, record)
			end
			local player = Players:GetPlayerFromCharacter(character)
			if player ~= nil then
				sendStatus(player)
			end
			if expired or record.State.Health <= 0 then
				record.Humanoid.Health = 0
				break
			end
		end
		if isRecordCurrent(character, record) then
			record.LoopRunning = false
		elseif character.Parent == nil then
			clearCharacter(character)
		end
	end)
end

local function createRecord(character: Model, humanoid: Humanoid): CharacterRecord?
	local existing = records[character]
	if existing ~= nil and existing.Humanoid == humanoid then
		return existing
	end
	if existing ~= nil then
		clearCharacter(character)
	end
	local state = MedicalRules.Create(humanoid.MaxHealth, config)
	if state == nil then
		warn("MedicalService: invalid MedicalConfig or Humanoid.MaxHealth")
		return nil
	end
	state.Health = math.clamp(humanoid.Health, 0, state.MaxHealth)
	local record: CharacterRecord = {
		Humanoid = humanoid,
		State = state,
		DiedConnection = nil,
		LoopRunning = false,
		SavedMovement = nil,
	}
	records[character] = record
	record.DiedConnection = humanoid.Died:Connect(function()
		clearCharacter(character)
	end)
	character:SetAttribute("SierraIncapacitated", false)
	return record
end

local function bindCharacter(player: Player, character: Model)
	task.spawn(function()
		local humanoidInstance = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
		if
			humanoidInstance == nil
			or not humanoidInstance:IsA("Humanoid")
			or player.Parent ~= Players
			or player.Character ~= character
		then
			return
		end
		local record = createRecord(character, humanoidInstance)
		if record ~= nil then
			sendStatus(player)
		end
	end)
end

local function isTreatmentCurrent(treatment: Treatment): (boolean, string)
	if
		treatment.Actor.Parent ~= Players
		or treatment.Target.Parent ~= Players
		or treatment.Actor.Character ~= treatment.ActorCharacter
		or treatment.Target.Character ~= treatment.TargetCharacter
	then
		return false, "character_unavailable"
	end
	local actorCharacter, actorHumanoid, actorRoot = getCharacterParts(treatment.Actor)
	local targetCharacter, targetHumanoid, targetRoot = getCharacterParts(treatment.Target)
	if actorCharacter == nil or actorHumanoid == nil or actorRoot == nil then
		return false, "healer_unavailable"
	end
	if targetCharacter == nil or targetHumanoid == nil or targetRoot == nil then
		return false, "target_unavailable"
	end
	local distance = (actorRoot.Position - targetRoot.Position).Magnitude
	if not MedicalRules.IsWithinRange(distance, config.TreatmentRange) then
		return false, "out_of_range"
	end
	return true, "ready"
end

local function finishTreatment(treatment: Treatment)
	if pendingByActor[treatment.Actor] ~= treatment or pendingByTarget[treatment.Target] ~= treatment then
		return
	end
	local valid, validationCode = isTreatmentCurrent(treatment)
	if not valid then
		clearTreatment(treatment, validationCode, true)
		return
	end
	local targetRecord = records[treatment.TargetCharacter]
	local item = config.Items[treatment.ItemId]
	if targetRecord == nil or item == nil then
		clearTreatment(treatment, "treatment_unavailable", true)
		return
	end

	syncHealth(targetRecord)
	if treatment.ItemId == "EmergencyKit" then
		if not targetRecord.State.IsIncapacitated then
			clearTreatment(treatment, "target_not_incapacitated", true)
			return
		end
		local consumed = InventoryService.ConsumeReservedMedicalItem(treatment.Actor, treatment.ReservationId)
		if not consumed then
			clearTreatment(treatment, "medical_item_unavailable", true)
			return
		end
		local revived, code = MedicalRules.Revive(targetRecord.State, os.clock(), config)
		if not revived then
			InventoryService.AddMedicalItem(treatment.Actor, treatment.ItemId, 1)
			clearTreatment(treatment, code, true)
			return
		end
		restoreAfterRevive(treatment.TargetCharacter, targetRecord)
	else
		local canTreat, code = MedicalRules.CanTreat(targetRecord.State, item)
		if not canTreat then
			clearTreatment(treatment, code, true)
			return
		end
		local consumed = InventoryService.ConsumeReservedMedicalItem(treatment.Actor, treatment.ReservationId)
		if not consumed then
			clearTreatment(treatment, "medical_item_unavailable", true)
			return
		end
		local treated, treatmentCode = MedicalRules.ApplyTreatment(targetRecord.State, item)
		if not treated then
			InventoryService.AddMedicalItem(treatment.Actor, treatment.ItemId, 1)
			clearTreatment(treatment, treatmentCode, true)
			return
		end
	end

	targetRecord.Humanoid.Health = targetRecord.State.Health
	lastTreatmentAt[treatment.Actor] = os.clock()
	pendingByActor[treatment.Actor] = nil
	pendingByTarget[treatment.Target] = nil
	sendStatus(treatment.Target)
	if treatment.Actor.Parent == Players and treatment.Actor ~= treatment.Target then
		sendStatus(treatment.Actor)
	end
	if treatment.Actor.Parent == Players then
		requestRemote:FireClient(treatment.Actor, {
			action = "medical_result",
			ok = true,
			code = if treatment.ItemId == "EmergencyKit" then "revived" else "treated",
		})
	end
end

local function beginTreatment(
	actor: Player,
	request: { action: "treat", itemId: string, targetUserId: number }
): (boolean, string)
	if pendingByActor[actor] ~= nil then
		return false, "treatment_in_progress"
	end
	local now = os.clock()
	if lastTreatmentAt[actor] ~= nil and now - lastTreatmentAt[actor] < config.TreatmentCooldown then
		return false, "treatment_cooldown"
	end
	local actorCharacter, actorHumanoid, actorRoot = getCharacterParts(actor)
	if actorCharacter == nil or actorHumanoid == nil or actorRoot == nil then
		return false, "healer_unavailable"
	end
	local actorRecord = records[actorCharacter]
	if actorRecord ~= nil and actorRecord.State.IsIncapacitated then
		return false, "healer_unavailable"
	end
	local target = Players:GetPlayerByUserId(request.targetUserId)
	if target == nil then
		return false, "invalid_target"
	end
	if target ~= actor and config.MedicOnlyForAllyTreatment == true then
		local session = PlayerDataService.GetSession(actor)
		if session == nil or session.Role ~= "Medic" then
			return false, "medic_required"
		end
	end
	local targetCharacter, targetHumanoid, targetRoot = getCharacterParts(target)
	if targetCharacter == nil or targetHumanoid == nil or targetRoot == nil then
		return false, "target_unavailable"
	end
	if pendingByTarget[target] ~= nil then
		return false, "treatment_in_progress"
	end
	if not MedicalRules.IsWithinRange((actorRoot.Position - targetRoot.Position).Magnitude, config.TreatmentRange) then
		return false, "out_of_range"
	end
	local targetRecord = createRecord(targetCharacter, targetHumanoid)
	if targetRecord == nil then
		return false, "medical_state_unavailable"
	end
	syncHealth(targetRecord)
	local item = config.Items[request.itemId]
	if item == nil then
		return false, "invalid_medical_item"
	end
	if request.itemId == "EmergencyKit" then
		if target == actor or not targetRecord.State.IsIncapacitated then
			return false, "target_not_incapacitated"
		end
	else
		if targetRecord.State.IsIncapacitated then
			return false, "target_incapacitated"
		end
		local canTreat, code = MedicalRules.CanTreat(targetRecord.State, item)
		if not canTreat then
			return false, code
		end
	end

	local reservationId, reservationCode = InventoryService.ReserveMedicalItem(actor, request.itemId)
	if reservationId == nil then
		return false, reservationCode
	end
	local treatment: Treatment = {
		Actor = actor,
		Target = target,
		ActorCharacter = actorCharacter,
		TargetCharacter = targetCharacter,
		ItemId = request.itemId,
		ReservationId = reservationId,
	}
	pendingByActor[actor] = treatment
	pendingByTarget[target] = treatment
	task.spawn(function()
		local startedAt = os.clock()
		while os.clock() - startedAt < item.UseSeconds do
			task.wait(math.min(0.25, item.UseSeconds))
			if pendingByActor[actor] ~= treatment then
				return
			end
			if not InventoryService.HasMedicalReservation(actor, treatment.ReservationId) then
				clearTreatment(treatment, "medical_item_unavailable", true)
				return
			end
			local current, code = isTreatmentCurrent(treatment)
			if not current then
				clearTreatment(treatment, code, true)
				return
			end
			if request.itemId == "EmergencyKit" then
				local currentRecord = records[targetCharacter]
				if
					currentRecord == nil
					or not currentRecord.State.IsIncapacitated
					or currentRecord.State.IncapacitatedUntil == nil
					or os.clock() >= currentRecord.State.IncapacitatedUntil
				then
					clearTreatment(treatment, "revive_interrupted", true)
					return
				end
			end
		end
		finishTreatment(treatment)
	end)
	return true, "treatment_started"
end

function MedicalService.GetStatus(player: Player): { [string]: any }?
	local character = player.Character
	local record = if character ~= nil then records[character] else nil
	local inventory = InventoryService.GetInventory(player)
	if record == nil or inventory == nil then
		return nil
	end
	syncHealth(record)
	local session = PlayerDataService.GetSession(player)
	local weapons = {}
	for weaponId, weaponState in pairs(inventory.Weapons) do
		local weaponDefinition = inventoryConfig.Weapons[weaponId]
		weapons[weaponId] = {
			name = if weaponDefinition ~= nil then weaponDefinition.DisplayName else weaponId,
			magazine = weaponState.Magazine,
			reserve = weaponState.Reserve,
			isReloading = weaponState.IsReloading,
			reloadEndsAt = if weaponState.IsReloading then InventoryService.GetReloadEndsAt(player) else nil,
		}
	end
	local equippedWeaponDefinition = inventoryConfig.Weapons[inventory.EquippedWeaponId]
	return {
		action = "medical_status",
		ok = true,
		character = character,
		health = record.State.Health,
		maxHealth = record.State.MaxHealth,
		wounds = #record.State.Wounds,
		bleedRate = record.State.BleedRate,
		incapacitated = record.State.IsIncapacitated,
		medicalItems = inventory.MedicalItems,
		equippedWeaponId = inventory.EquippedWeaponId,
		weaponName = if equippedWeaponDefinition ~= nil
			then equippedWeaponDefinition.DisplayName
			else inventory.EquippedWeaponId,
		weapons = weapons,
		role = if session ~= nil then session.Role else "Rifleman",
	}
end

function MedicalService.ApplyDamage(humanoid: Humanoid, amount: number): (boolean, string)
	if typeof(humanoid) ~= "Instance" or not humanoid:IsA("Humanoid") or humanoid.Health <= 0 then
		return false, "invalid_target"
	end
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount == math.huge then
		return false, "invalid_damage"
	end
	local character = humanoid.Parent
	if character == nil or not character:IsA("Model") then
		return false, "invalid_target"
	end
	local record = createRecord(character, humanoid)
	if record == nil then
		return false, "medical_state_unavailable"
	end
	syncHealth(record)
	local applied, code = MedicalRules.ApplyDamage(record.State, amount, os.clock(), config)
	if not applied then
		return false, code
	end
	humanoid.Health = record.State.Health
	if record.State.IsIncapacitated then
		setIncapacitated(character, record)
	end
	startBleedLoop(character, record)
	local player = Players:GetPlayerFromCharacter(character)
	if player ~= nil then
		sendStatus(player)
	end
	return true, code
end

function MedicalService.HandleRequest(player: Player, request: any): { [string]: any }
	local allowed, bucket = MedicalRules.TakeRateLimitToken(
		requestBuckets[player],
		os.clock(),
		config.RequestWindowSeconds,
		config.MaxRequestsPerWindow
	)
	requestBuckets[player] = bucket
	if not allowed then
		return { action = "medical_result", ok = false, code = "rate_limited" }
	end
	if type(request) ~= "table" then
		return { action = "medical_result", ok = false, code = "invalid_request" }
	end
	if request.action == "medical_status" then
		return MedicalService.GetStatus(player)
			or { action = "medical_result", ok = false, code = "medical_state_unavailable" }
	elseif request.action == "cancel_treatment" then
		local treatment = pendingByActor[player]
		if treatment == nil then
			return { action = "medical_result", ok = false, code = "no_treatment_in_progress" }
		end
		clearTreatment(treatment, "treatment_cancelled", false)
		return { action = "medical_result", ok = true, code = "treatment_cancelled" }
	elseif request.action == "treat" then
		if
			type(request.itemId) ~= "string"
			or type(request.targetUserId) ~= "number"
			or request.targetUserId % 1 ~= 0
			or request.targetUserId <= 0
		then
			return { action = "medical_result", ok = false, code = "invalid_request" }
		end
		local started, code = beginTreatment(player, request)
		if not started then
			return { action = "medical_result", ok = false, code = code }
		end
		return { action = "medical_result", ok = true, code = code }
	end
	return { action = "medical_result", ok = false, code = "invalid_action" }
end

function MedicalService.Start()
	if isStarted then
		return
	end
	if not MedicalRules.ValidateConfig(config) then
		error("MedicalService: invalid MedicalConfig")
	end
	isStarted = true
	local function addPlayer(player: Player)
		if player.Parent ~= Players or playerConnections[player] ~= nil then
			return
		end
		playerConnections[player] = {
			player.CharacterAdded:Connect(function(character)
				bindCharacter(player, character)
			end),
			player.CharacterRemoving:Connect(clearCharacter),
		}
		if player.Character ~= nil then
			bindCharacter(player, player.Character)
		end
	end
	table.insert(serviceConnections, Players.PlayerAdded:Connect(addPlayer))
	for _, player in ipairs(Players:GetPlayers()) do
		addPlayer(player)
	end
	table.insert(
		serviceConnections,
		Players.PlayerRemoving:Connect(function(player)
			local character = player.Character
			if character ~= nil then
				clearCharacter(character)
			end
			local treatment = pendingByActor[player]
			if treatment ~= nil then
				clearTreatment(treatment, "player_left", false)
			end
			local targetTreatment = pendingByTarget[player]
			if targetTreatment ~= nil then
				clearTreatment(targetTreatment, "target_left", true)
			end
			for _, connection in ipairs(playerConnections[player] or {}) do
				connection:Disconnect()
			end
			playerConnections[player] = nil
			requestBuckets[player] = nil
			lastTreatmentAt[player] = nil
		end)
	)
end

function MedicalService.Stop()
	if not isStarted then
		return
	end
	isStarted = false
	for _, connection in ipairs(serviceConnections) do
		connection:Disconnect()
	end
	table.clear(serviceConnections)
	for player, treatment in pairs(pendingByActor) do
		clearTreatment(treatment, "service_stopped", false)
		pendingByActor[player] = nil
	end
	for character in pairs(records) do
		clearCharacter(character)
	end
	for player, connections in pairs(playerConnections) do
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		playerConnections[player] = nil
	end
	table.clear(requestBuckets)
	table.clear(lastTreatmentAt)
end

return table.freeze(MedicalService)
