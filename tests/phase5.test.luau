--!strict

local InventoryConfig = require("../src/shared/config/InventoryConfig")
local InventoryRules = require("../src/server/services/InventoryRules")
local CombatRequestRules = require("../src/server/services/CombatRequestRules")
local CombatRules = require("../src/server/services/CombatRules")

local checks = 0

local function check(condition: boolean, message: string)
	assert(condition, message)
	checks += 1
end

local function expectRequestFailure(request: any, argumentCount: number, expectedCode: string)
	local normalized, code = CombatRequestRules.Validate(request, argumentCount)
	check(normalized == nil and code == expectedCode, `expected request rejection: {expectedCode}, got {code}`)
end

local first = InventoryRules.Create(InventoryConfig)
local second = InventoryRules.Create(InventoryConfig)
check(first ~= nil and first.EquippedWeaponId == "Rifle", "default authorized equipment must be assigned")
check(second ~= nil and second.EquippedWeaponId == "Rifle", "each player gets a new inventory")

local inventoryA = first :: any
local inventoryB = second :: any
local originalAmmunition = inventoryA.Weapons.Rifle.Magazine
local equipped, equippedCode = InventoryRules.Equip(inventoryA, "Sidearm")
check(equipped and equippedCode == "equipped", "configured weapons may be equipped")
local beforeUnknown = InventoryRules.Copy(inventoryA)
local unknownEquipped, unknownCode = InventoryRules.Equip(inventoryA, "ArbitraryWeapon")
check(not unknownEquipped and unknownCode == "invalid_weapon", "unknown weapons must be rejected")
check(inventoryA.EquippedWeaponId == beforeUnknown.EquippedWeaponId, "rejected equip must not change the selected weapon")
check(inventoryB.EquippedWeaponId == "Rifle", "player inventories must not share equipped state")

local snapshot = InventoryRules.Copy(inventoryA)
snapshot.Weapons.Sidearm.Magazine = 0
check(inventoryA.Weapons.Sidearm.Magazine == InventoryConfig.Weapons.Sidearm.InitialMagazine, "inventory snapshots must be defensive")

local consumed, consumeCode = InventoryRules.ConsumeAmmo(inventoryA)
check(consumed and consumeCode == "consumed", "a valid shot consumes exactly one round")
check(inventoryA.Weapons.Sidearm.Magazine == InventoryConfig.Weapons.Sidearm.InitialMagazine - 1, "one round must be consumed")
check(inventoryB.Weapons.Rifle.Magazine == originalAmmunition, "ammo changes must remain isolated per player")

inventoryA.Weapons.Sidearm.Magazine = 0
local emptySnapshot = InventoryRules.Copy(inventoryA)
local emptyConsumed, emptyCode = InventoryRules.ConsumeAmmo(inventoryA)
check(not emptyConsumed and emptyCode == "no_ammo", "empty magazines reject shots")
check(inventoryA.Weapons.Sidearm.Magazine == emptySnapshot.Weapons.Sidearm.Magazine, "empty shot rejection leaves ammo unchanged")

inventoryA.Weapons.Sidearm.Magazine = InventoryConfig.Weapons.Sidearm.MagazineCapacity - 2
inventoryA.Weapons.Sidearm.Reserve = 3
local reloadStarted, reloadCode, reloadSeconds = InventoryRules.BeginReload(inventoryA, InventoryConfig)
check(reloadStarted and reloadCode == "reload_started", "reload with missing rounds and reserve must start")
check(reloadSeconds == InventoryConfig.Weapons.Sidearm.ReloadSeconds, "reload uses configured duration")
local duplicateReload, duplicateCode = InventoryRules.BeginReload(inventoryA, InventoryConfig)
check(not duplicateReload and duplicateCode == "already_reloading", "simultaneous reload requests must be rejected")
local whileReloading = InventoryRules.Copy(inventoryA)
local shotDuringReload, shotDuringReloadCode = InventoryRules.ConsumeAmmo(inventoryA)
check(not shotDuringReload and shotDuringReloadCode == "reloading", "firing during reload must be rejected")
check(inventoryA.Weapons.Sidearm.Magazine == whileReloading.Weapons.Sidearm.Magazine, "rejected shot must not change ammo")
local reloadCompleted, loaded = InventoryRules.CompleteReload(inventoryA, InventoryConfig)
check(reloadCompleted and loaded == 2, "reload is capped to magazine capacity")
check(inventoryA.Weapons.Sidearm.Magazine == InventoryConfig.Weapons.Sidearm.MagazineCapacity, "magazine must not exceed configured capacity")
check(inventoryA.Weapons.Sidearm.Reserve == 1, "reload consumes only the rounds transferred")
local noOpCompletion, noOpLoaded = InventoryRules.CompleteReload(inventoryA, InventoryConfig)
check(not noOpCompletion and noOpLoaded == 0, "a completed reload cannot complete twice")

local fullMagazine = InventoryRules.Copy(inventoryA)
local fullReload, fullReloadCode = InventoryRules.BeginReload(inventoryA, InventoryConfig)
check(not fullReload and fullReloadCode == "magazine_full", "full magazines reject reloads")
check(inventoryA.Weapons.Sidearm.Reserve == fullMagazine.Weapons.Sidearm.Reserve, "full reload rejection leaves reserve unchanged")
inventoryA.Weapons.Sidearm.Magazine -= 1
inventoryA.Weapons.Sidearm.Reserve = 0
local noReserve, noReserveCode = InventoryRules.BeginReload(inventoryA, InventoryConfig)
check(not noReserve and noReserveCode == "no_reserve_ammo", "reload without reserve ammunition is rejected")
check(not inventoryA.Weapons.Sidearm.IsReloading, "invalid reload does not set reload state")
inventoryA.Weapons.Sidearm.Reserve = 2
local cancelStarted = InventoryRules.BeginReload(inventoryA, InventoryConfig)
check(cancelStarted, "reload can start after a valid state is restored")
InventoryRules.CancelReload(inventoryA)
check(not inventoryA.Weapons.Sidearm.IsReloading, "death or respawn cancellation clears reload state")

local shootRequest = { action = "shoot", direction = { x = 0, y = 0, z = -1 } }
local normalizedShot, shotError = CombatRequestRules.Validate(shootRequest, 1)
check(normalizedShot ~= nil and shotError == nil, "well-formed shot request is accepted")
check(
	normalizedShot ~= nil
		and normalizedShot.action == "shoot"
		and normalizedShot.direction.z == -1,
	"valid direction is normalized"
)
expectRequestFailure(shootRequest, 2, "invalid_argument_count")
expectRequestFailure({ action = "shoot", direction = { x = 0, y = 0, z = 0 } }, 1, "invalid_direction")
expectRequestFailure({ action = "shoot", direction = { x = 1, y = 0, z = 0, extra = 1 } }, 1, "invalid_direction")
expectRequestFailure({ action = "shoot", direction = { x = 1, y = 0, z = 0 }, damage = 999 }, 1, "unexpected_field")
expectRequestFailure({ action = "shoot", direction = { x = 0 / 0, y = 0, z = 1 } }, 1, "invalid_direction")
expectRequestFailure({ action = "reload", weaponId = "Rifle" }, 1, "unexpected_field")
expectRequestFailure({ action = "equip", weaponId = string.rep("x", 33) }, 1, "invalid_weapon")
expectRequestFailure({ action = "teleport" }, 1, "invalid_action")
expectRequestFailure(setmetatable({ action = "reload" }, {}), 1, "invalid_request")

local canFire, readyCode = CombatRules.CanFire(nil, 10, 0.1, 2, false, true)
check(canFire and readyCode == "ready", "valid player with ammunition may fire")
local tooSoon, tooSoonCode = CombatRules.CanFire(10, 10.05, 0.1, 2, false, true)
check(not tooSoon and tooSoonCode == "rate_limited", "shots inside minimum cadence are rejected")
local noAmmo, noAmmoCode = CombatRules.CanFire(nil, 10, 0.1, 0, false, true)
check(not noAmmo and noAmmoCode == "no_ammo", "server-side empty magazine rejects fire")
local reloading, reloadingCode = CombatRules.CanFire(nil, 10, 0.1, 2, true, true)
check(not reloading and reloadingCode == "reloading", "server-side reload state rejects fire")
local dead, deadCode = CombatRules.CanFire(nil, 10, 0.1, 2, false, false)
check(not dead and deadCode == "attacker_unavailable", "dead attackers cannot fire")

local firstToken, firstBucket = CombatRules.TakeRateLimitToken(nil, 1, 1, 2)
local secondToken, secondBucket = CombatRules.TakeRateLimitToken(firstBucket, 1.1, 1, 2)
local thirdToken, unchangedBucket = CombatRules.TakeRateLimitToken(secondBucket, 1.2, 1, 2)
check(firstToken and secondToken and not thirdToken, "request rate limit caps requests within its window")
check(unchangedBucket.Count == secondBucket.Count, "rate-limit rejection does not increase the bucket further")
local afterWindow = CombatRules.TakeRateLimitToken(unchangedBucket, 2.2, 1, 2)
check(afterWindow, "rate limit resets after its window")

check(CombatRules.IsWithinRange(100, 100), "target at configured range is valid")
check(not CombatRules.IsWithinRange(100.01, 100), "target beyond configured range is invalid")
check(not CombatRules.IsWithinRange(0 / 0, 100), "non-finite target distance is invalid")
local attacker = {}
local target = {}
check(CombatRules.CanDamageTarget(attacker, target, true, true, 50), "living character with Humanoid and root is a valid target")
check(not CombatRules.CanDamageTarget(attacker, attacker, true, true, 50), "self damage is rejected")
check(not CombatRules.CanDamageTarget(attacker, target, true, true, 0), "dead target damage is rejected")
check(not CombatRules.CanDamageTarget(attacker, target, false, true, 50), "objects without Humanoid are rejected")
check(not CombatRules.CanDamageTarget(attacker, target, true, false, 50), "objects without root part are rejected")
check(CombatRules.CalculateDamage(50, 22) == 22, "damage uses configured server amount")
check(CombatRules.CalculateDamage(10, 22) == 10, "damage cannot exceed remaining health")
check(CombatRules.CalculateDamage(0, 22) == 0, "dead targets receive no damage")
check(CombatRules.CalculateDamage(50, math.huge) == 0, "invalid damage values are rejected")

print(`Fase 5: {checks} comprobaciones de inventario y reglas de combate pasaron.`)
