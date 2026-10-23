--!strict

type WeaponDefinition = {
	MagazineCapacity: number,
	InitialMagazine: number,
	InitialReserve: number,
	ReloadSeconds: number,
}

type WeaponState = {
	Magazine: number,
	Reserve: number,
	IsReloading: boolean,
}

type InventoryState = {
	EquippedWeaponId: string,
	Weapons: { [string]: WeaponState },
	Equipment: { Radio: string },
	MedicalItems: { [string]: number },
	Supplies: { [string]: number },
}

local InventoryRules = {}

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function InventoryRules.Create(config: any, medicalConfig: any?): InventoryState?
	if type(config) ~= "table"
		or type(config.DefaultWeapon) ~= "string"
		or type(config.Weapons) ~= "table"
		or config.Weapons[config.DefaultWeapon] == nil
		or type(config.Radio) ~= "table"
		or type(config.Radio.ItemId) ~= "string"
		or config.Radio.ItemId == ""
	then
		return nil
	end
	if medicalConfig ~= nil and (type(medicalConfig) ~= "table" or type(medicalConfig.Items) ~= "table") then
		return nil
	end

	local weapons: { [string]: WeaponState } = {}
	for weaponId, definition in pairs(config.Weapons) do
		if type(definition) ~= "table" then
			return nil
		end
		local definitionData = definition :: { [string]: any }
		local magazineCapacity = definitionData.MagazineCapacity
		local initialMagazine = definitionData.InitialMagazine
		local initialReserve = definitionData.InitialReserve
		local reloadSeconds = definitionData.ReloadSeconds

		if type(weaponId) ~= "string"
			or not isFiniteNumber(magazineCapacity)
			or not isFiniteNumber(initialMagazine)
			or not isFiniteNumber(initialReserve)
			or not isFiniteNumber(reloadSeconds)
			or magazineCapacity < 1
			or magazineCapacity % 1 ~= 0
			or initialMagazine < 0
			or initialMagazine % 1 ~= 0
			or initialMagazine > magazineCapacity
			or initialReserve < 0
			or initialReserve % 1 ~= 0
			or reloadSeconds <= 0
		then
			return nil
		end

		weapons[weaponId] = {
			Magazine = initialMagazine,
			Reserve = initialReserve,
			IsReloading = false,
		}
	end

	local medicalItems: { [string]: number } = {}
	local medicalDefinitions: { [string]: any } = {}
	if type(medicalConfig) == "table" and type(medicalConfig.Items) == "table" then
		medicalDefinitions = medicalConfig.Items
	end
	for itemId, item in pairs(medicalDefinitions) do
		if type(itemId) ~= "string"
			or type(item) ~= "table"
			or not isFiniteNumber(item.InitialCount)
			or item.InitialCount < 0
			or item.InitialCount % 1 ~= 0
		then
			return nil
		end
		medicalItems[itemId] = item.InitialCount
	end

	return {
		EquippedWeaponId = config.DefaultWeapon,
		Weapons = weapons,
		Equipment = {
			Radio = config.Radio.ItemId,
		},
		MedicalItems = medicalItems,
		Supplies = {},
	}
end

function InventoryRules.Copy(state: InventoryState): InventoryState
	local weapons: { [string]: WeaponState } = {}
	for weaponId, weaponState in pairs(state.Weapons) do
		weapons[weaponId] = {
			Magazine = weaponState.Magazine,
			Reserve = weaponState.Reserve,
			IsReloading = weaponState.IsReloading,
		}
	end

	return {
		EquippedWeaponId = state.EquippedWeaponId,
		Weapons = weapons,
		Equipment = table.clone(state.Equipment),
		MedicalItems = table.clone(state.MedicalItems),
		Supplies = table.clone(state.Supplies),
	}
end

function InventoryRules.AddSupply(state: InventoryState, supplyId: any, amount: any, maximum: any): (number, string)
	if type(supplyId) ~= "string"
		or type(amount) ~= "number"
		or amount <= 0
		or amount % 1 ~= 0
		or type(maximum) ~= "number"
		or maximum < 0
		or maximum % 1 ~= 0
	then
		return 0, "invalid_supply"
	end
	local current = state.Supplies[supplyId] or 0
	local added = math.min(amount, maximum - current)
	if added <= 0 then
		return 0, "supply_capacity_full"
	end
	state.Supplies[supplyId] = current + added
	return added, "supplied"
end

function InventoryRules.AddAmmoReserve(state: InventoryState, weaponId: any, amount: any, maximum: any): (number, string)
	if type(weaponId) ~= "string"
		or type(amount) ~= "number"
		or amount <= 0
		or amount % 1 ~= 0
		or type(maximum) ~= "number"
		or maximum < 0
		or maximum % 1 ~= 0
	then
		return 0, "invalid_ammo"
	end
	local weaponState = state.Weapons[weaponId]
	if weaponState == nil then
		return 0, "invalid_weapon"
	end
	local added = math.min(amount, math.max(0, maximum - weaponState.Reserve))
	if added <= 0 then
		return 0, "ammo_capacity_full"
	end
	weaponState.Reserve += added
	return added, "supplied"
end

function InventoryRules.ConsumeMedicalItem(state: InventoryState, itemId: any, medicalConfig: any): (boolean, string)
	if type(itemId) ~= "string"
		or type(medicalConfig) ~= "table"
		or type(medicalConfig.Items) ~= "table"
		or type(medicalConfig.Items[itemId]) ~= "table"
	then
		return false, "invalid_medical_item"
	end
	local count = state.MedicalItems[itemId]
	if count == nil then
		return false, "medical_item_unavailable"
	end
	if count <= 0 then
		return false, "no_medical_items"
	end
	state.MedicalItems[itemId] = count - 1
	return true, "consumed"
end

function InventoryRules.Equip(state: InventoryState, weaponId: any): (boolean, string)
	if type(weaponId) ~= "string" or state.Weapons[weaponId] == nil then
		return false, "invalid_weapon"
	end
	if state.Weapons[state.EquippedWeaponId].IsReloading then
		return false, "reloading"
	end

	state.EquippedWeaponId = weaponId
	return true, "equipped"
end

function InventoryRules.ConsumeAmmo(state: InventoryState): (boolean, string)
	local weaponState = state.Weapons[state.EquippedWeaponId]
	if weaponState == nil then
		return false, "invalid_weapon"
	end
	if weaponState.IsReloading then
		return false, "reloading"
	end
	if weaponState.Magazine <= 0 then
		return false, "no_ammo"
	end

	weaponState.Magazine -= 1
	return true, "consumed"
end

function InventoryRules.BeginReload(state: InventoryState, config: any): (boolean, string, number?)
	local weaponState = state.Weapons[state.EquippedWeaponId]
	local definition = config.Weapons[state.EquippedWeaponId] :: WeaponDefinition?
	if weaponState == nil or definition == nil then
		return false, "invalid_weapon", nil
	end
	if weaponState.IsReloading then
		return false, "already_reloading", nil
	end
	if weaponState.Magazine >= definition.MagazineCapacity then
		return false, "magazine_full", nil
	end
	if weaponState.Reserve <= 0 then
		return false, "no_reserve_ammo", nil
	end

	weaponState.IsReloading = true
	return true, "reload_started", definition.ReloadSeconds
end

function InventoryRules.CompleteReload(state: InventoryState, config: any): (boolean, number)
	local weaponState = state.Weapons[state.EquippedWeaponId]
	local definition = config.Weapons[state.EquippedWeaponId] :: WeaponDefinition?
	if weaponState == nil or definition == nil or not weaponState.IsReloading then
		return false, 0
	end

	local loaded = math.min(definition.MagazineCapacity - weaponState.Magazine, weaponState.Reserve)
	weaponState.Magazine += loaded
	weaponState.Reserve -= loaded
	weaponState.IsReloading = false
	return true, loaded
end

function InventoryRules.CancelReload(state: InventoryState)
	local weaponState = state.Weapons[state.EquippedWeaponId]
	if weaponState ~= nil then
		weaponState.IsReloading = false
	end
end

return table.freeze(InventoryRules)
