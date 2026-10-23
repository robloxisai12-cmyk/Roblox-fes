--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(script.Parent.PlayerDataService)
local shared = ReplicatedStorage:WaitForChild("Shared")
local configFolder = shared:WaitForChild("config")
local configModule = configFolder:WaitForChild("InventoryConfig") :: ModuleScript
local config = require(configModule)
local medicalConfigModule = configFolder:WaitForChild("MedicalConfig") :: ModuleScript
local medicalConfig = require(medicalConfigModule)
local logisticsConfigModule = configFolder:WaitForChild("LogisticsConfig") :: ModuleScript
local logisticsConfig = require(logisticsConfigModule)
local InventoryRules = require(script.Parent.InventoryRules)

type InventoryState = {
	EquippedWeaponId: string,
	Weapons: { [string]: { Magazine: number, Reserve: number, IsReloading: boolean } },
	Equipment: { Radio: string },
	MedicalItems: { [string]: number },
}

type MedicalReservation = {
	ItemId: string,
}

local inventories: { [Player]: InventoryState } = {}
local medicalReservations: { [Player]: { [number]: MedicalReservation } } = {}
local nextMedicalReservationId = 0
local reloadVersions: { [Player]: number } = {}
local reloadEndsAt: { [Player]: number } = {}
local playerConnections: { [Player]: { RBXScriptConnection } } = {}
local characterDeathConnections: { [Player]: RBXScriptConnection } = {}
local connections: { RBXScriptConnection } = {}
local isStarted = false

local InventoryService = {}

local function nextReloadVersion(player: Player): number
	local version = (reloadVersions[player] or 0) + 1
	reloadVersions[player] = version
	return version
end

function InventoryService.CancelReload(player: Player)
	reloadEndsAt[player] = nil
	local state = inventories[player]
	if state ~= nil then
		InventoryRules.CancelReload(state)
	end
	nextReloadVersion(player)
end

local function bindCharacter(player: Player, character: Model)
	InventoryService.CancelReload(player)
	local previousConnection = characterDeathConnections[player]
	if previousConnection ~= nil then
		previousConnection:Disconnect()
		characterDeathConnections[player] = nil
	end
	local humanoidInstance = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if humanoidInstance == nil or not humanoidInstance:IsA("Humanoid") then
		return
	end
	if inventories[player] == nil or player.Character ~= character then
		return
	end
	characterDeathConnections[player] = humanoidInstance.Died:Connect(function()
		InventoryService.CancelReload(player)
	end)
end

local function addPlayer(player: Player)
	if player.Parent ~= Players or inventories[player] ~= nil or PlayerDataService.GetSession(player) == nil then
		return
	end
	local state = InventoryRules.Create(config, medicalConfig)
	if state == nil then
		error("InventoryService: invalid inventory or medical configuration")
	end
	inventories[player] = state
	medicalReservations[player] = {}
	reloadVersions[player] = 0
	playerConnections[player] = {
		player.CharacterAdded:Connect(function(character)
			bindCharacter(player, character)
		end),
	}
	if player.Character ~= nil then
		bindCharacter(player, player.Character)
	end
end

local function removePlayer(player: Player)
	InventoryService.CancelReload(player)
	inventories[player] = nil
	medicalReservations[player] = nil
	reloadVersions[player] = nil
	local characterConnection = characterDeathConnections[player]
	if characterConnection ~= nil then
		characterConnection:Disconnect()
		characterDeathConnections[player] = nil
	end
	for _, connection in ipairs(playerConnections[player] or {}) do
		connection:Disconnect()
	end
	playerConnections[player] = nil
end

function InventoryService.Start()
	if isStarted then
		return
	end
	isStarted = true
	table.insert(connections, Players.PlayerAdded:Connect(addPlayer))
	table.insert(connections, Players.PlayerRemoving:Connect(removePlayer))
	for _, player in ipairs(Players:GetPlayers()) do
		addPlayer(player)
	end
end

function InventoryService.GetInventory(player: Player): InventoryState?
	local state = inventories[player]
	if state == nil then
		return nil
	end
	local snapshot = InventoryRules.Copy(state)
	local reservedCounts: { [string]: number } = {}
	for _, reservation in pairs(medicalReservations[player] or {}) do
		reservedCounts[reservation.ItemId] = (reservedCounts[reservation.ItemId] or 0) + 1
	end
	for itemId, count in pairs(snapshot.MedicalItems) do
		snapshot.MedicalItems[itemId] = math.max(0, count - (reservedCounts[itemId] or 0))
	end
	return snapshot
end

function InventoryService.HasRadio(player: Player): boolean
	local state = inventories[player]
	return state ~= nil and state.Equipment.Radio == config.Radio.ItemId
end

function InventoryService.GetMedicalItemCount(player: Player, itemId: string): number
	if type(itemId) ~= "string" then
		return 0
	end
	local inventory = InventoryService.GetInventory(player)
	return if inventory ~= nil then inventory.MedicalItems[itemId] or 0 else 0
end

function InventoryService.ConsumeMedicalItem(player: Player, itemId: any): (boolean, string)
	local state = inventories[player]
	if state == nil then
		return false, "inventory_unavailable"
	end
	local availableCount = InventoryService.GetMedicalItemCount(player, itemId)
	if availableCount <= 0 then
		return false, "no_medical_items"
	end
	return InventoryRules.ConsumeMedicalItem(state, itemId, medicalConfig)
end

function InventoryService.ReserveMedicalItem(player: Player, itemId: any): (number?, string)
	if type(itemId) ~= "string" or InventoryService.GetMedicalItemCount(player, itemId) <= 0 then
		return nil, "no_medical_items"
	end
	local reservations = medicalReservations[player]
	if reservations == nil then
		return nil, "inventory_unavailable"
	end
	nextMedicalReservationId += 1
	reservations[nextMedicalReservationId] = { ItemId = itemId }
	return nextMedicalReservationId, "reserved"
end

function InventoryService.ReleaseMedicalItem(player: Player, reservationId: number): boolean
	local reservations = medicalReservations[player]
	if reservations == nil or reservations[reservationId] == nil then
		return false
	end
	reservations[reservationId] = nil
	return true
end

function InventoryService.HasMedicalReservation(player: Player, reservationId: number): boolean
	local reservations = medicalReservations[player]
	return reservations ~= nil and reservations[reservationId] ~= nil
end

function InventoryService.ConsumeReservedMedicalItem(player: Player, reservationId: number): (boolean, string)
	local reservations = medicalReservations[player]
	local state = inventories[player]
	local reservation = if reservations ~= nil then reservations[reservationId] else nil
	if reservations == nil or state == nil or reservation == nil then
		return false, "reservation_unavailable"
	end
	local consumed, code = InventoryRules.ConsumeMedicalItem(state, reservation.ItemId, medicalConfig)
	if consumed then
		reservations[reservationId] = nil
	end
	return consumed, code
end

function InventoryService.AddMedicalItem(player: Player, itemId: string, amount: number): boolean
	local state = inventories[player]
	if
		state == nil
		or type(itemId) ~= "string"
		or type(medicalConfig.Items[itemId]) ~= "table"
		or type(amount) ~= "number"
		or amount <= 0
		or amount % 1 ~= 0
	then
		return false
	end
	local count = state.MedicalItems[itemId]
	if count == nil then
		return false
	end
	state.MedicalItems[itemId] = count + amount
	return true
end

function InventoryService.CanApplyLogisticsSupply(player: Player, resourceId: string, amount: number): boolean
	local state = inventories[player]
	if state == nil or type(amount) ~= "number" or amount <= 0 or amount % 1 ~= 0 then
		return false
	end
	local supply = logisticsConfig.Resupply
	if resourceId == "Ammo" then
		local weaponId = state.EquippedWeaponId
		local weaponState = state.Weapons[weaponId]
		local weaponDefinition = config.Weapons[weaponId]
		if weaponState == nil or weaponDefinition == nil then
			return false
		end
		local maximum = weaponDefinition.InitialReserve * supply.MaxAmmoReserveMultiplier
		return weaponState.Reserve < maximum
	elseif resourceId == "Medical" then
		for itemId, definition in pairs(medicalConfig.Items) do
			local current = state.MedicalItems[itemId]
			local maximum = definition.InitialCount * supply.MedicalCapacityMultiplier
			if current ~= nil and current < maximum then
				return true
			end
		end
		return false
	elseif resourceId == "Rations" then
		return (state.Supplies.Rations or 0) < supply.MaxRations
	end
	return false
end

function InventoryService.ApplyLogisticsSupply(player: Player, resourceId: string, amount: number): (number, string)
	local state = inventories[player]
	if state == nil then
		return 0, "inventory_unavailable"
	end
	if type(amount) ~= "number" or amount <= 0 or amount % 1 ~= 0 then
		return 0, "invalid_amount"
	end
	local supply = logisticsConfig.Resupply
	if resourceId == "Ammo" then
		local weaponId = state.EquippedWeaponId
		local weaponState = state.Weapons[weaponId]
		local weaponDefinition = config.Weapons[weaponId]
		if weaponState == nil or weaponDefinition == nil then
			return 0, "invalid_weapon"
		end
		local maximum = weaponDefinition.InitialReserve * supply.MaxAmmoReserveMultiplier
		local rounds, code = InventoryRules.AddAmmoReserve(state, weaponId, amount * supply.AmmoRoundsPerUnit, maximum)
		if rounds <= 0 then
			return 0, code
		end
		return math.ceil(rounds / supply.AmmoRoundsPerUnit), "supplied"
	elseif resourceId == "Medical" then
		local added = 0
		for itemId, definition in pairs(medicalConfig.Items) do
			local current = state.MedicalItems[itemId]
			local maximum = definition.InitialCount * supply.MedicalCapacityMultiplier
			if current ~= nil and current < maximum then
				state.MedicalItems[itemId] = math.min(maximum, current + amount * supply.MedicalItemsPerUnit)
				added = math.max(added, math.ceil((state.MedicalItems[itemId] - current) / supply.MedicalItemsPerUnit))
			end
		end
		if added <= 0 then
			return 0, "medical_capacity_full"
		end
		return math.min(amount, added), "supplied"
	elseif resourceId == "Rations" then
		local units, code =
			InventoryRules.AddSupply(state, "Rations", amount * supply.RationsPerUnit, supply.MaxRations)
		if units <= 0 then
			return 0, code
		end
		return math.ceil(units / supply.RationsPerUnit), "supplied"
	end
	return 0, "invalid_resource"
end

function InventoryService.EquipWeapon(player: Player, weaponId: any): (boolean, string)
	local state = inventories[player]
	if state == nil then
		return false, "inventory_unavailable"
	end
	return InventoryRules.Equip(state, weaponId)
end

function InventoryService.ConsumeAmmo(player: Player): (boolean, string)
	local state = inventories[player]
	if state == nil then
		return false, "inventory_unavailable"
	end
	return InventoryRules.ConsumeAmmo(state)
end

function InventoryService.BeginReload(player: Player): (boolean, string, number?, number?)
	local state = inventories[player]
	if state == nil then
		return false, "inventory_unavailable", nil, nil
	end
	local ok, code, duration = InventoryRules.BeginReload(state, config)
	if not ok then
		return false, code, nil, nil
	end
	reloadEndsAt[player] = workspace:GetServerTimeNow() + (duration :: number)
	return true, code, duration, nextReloadVersion(player)
end

function InventoryService.GetReloadEndsAt(player: Player): number?
	return reloadEndsAt[player]
end

function InventoryService.CompleteReload(player: Player, version: number): (boolean, number)
	local state = inventories[player]
	if state == nil or reloadVersions[player] ~= version then
		return false, 0
	end
	local character = player.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	if
		humanoid == nil
		or humanoid.Health <= 0
		or character == nil
		or character:GetAttribute("SierraIncapacitated") == true
	then
		InventoryService.CancelReload(player)
		return false, 0
	end
	reloadEndsAt[player] = nil
	return InventoryRules.CompleteReload(state, config)
end

function InventoryService.Stop()
	if not isStarted then
		return
	end
	isStarted = false
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
	for player in pairs(inventories) do
		removePlayer(player)
	end
end

return table.freeze(InventoryService)
