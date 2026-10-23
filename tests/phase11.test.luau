--!strict

local InventoryConfig = require("../src/shared/config/InventoryConfig")
local LogisticsConfig = require("../src/shared/config/LogisticsConfig")
local MapConfig = require("../src/shared/config/MapConfig")
local MedicalConfig = require("../src/shared/config/MedicalConfig")
local MissionConfig = require("../src/shared/config/MissionConfig")
local RadioConfig = require("../src/shared/config/RadioConfig")
local TacticalUIRules = require("../src/shared/config/TacticalUIRules")
local CombatRequestRules = require("../src/server/services/CombatRequestRules")
local InventoryRules = require("../src/server/services/InventoryRules")
local LogisticsRules = require("../src/server/services/LogisticsRules")
local MapLayoutGenerator = require("../src/server/services/MapLayoutGenerator")
local MatchRules = require("../src/server/services/MatchRules")
local MedicalRules = require("../src/server/services/MedicalRules")
local RadioRules = require("../src/server/services/RadioRules")
local SquadRequestRules = require("../src/server/services/SquadRequestRules")

local checks = 0

local function check(condition: boolean, message: string)
	assert(condition, message)
	checks += 1
end

check(MapLayoutGenerator.ValidateConfig(MapConfig), "map config validates across the integrated project")
check(InventoryRules.Create(InventoryConfig, MedicalConfig) ~= nil, "inventory and medical config initialize together")
check(MedicalRules.ValidateConfig(MedicalConfig), "medical config validates")
check(LogisticsRules.ValidateConfig(LogisticsConfig), "logistics config validates")
check(RadioRules.IsValidConfig(RadioConfig), "radio config validates")
check(MatchRules.ValidateConfig(MissionConfig), "mission config validates")
check(TacticalUIRules.GetProfile(390, 844).TouchTargetSize >= 44, "mobile interface retains touch target bounds")

local shot = CombatRequestRules.Validate({
	action = "shoot",
	direction = { x = 0, y = 0, z = -1 },
}, 1)
check(shot ~= nil, "combat intent validates for server-authoritative processing")
local malformedShot = CombatRequestRules.Validate({
	action = "shoot",
	direction = { x = 100, y = 0, z = 0 },
}, 1)
check(malformedShot == nil, "malformed combat direction is rejected")

local assignableRoles = {
	Medic = true,
	Rifleman = true,
	Engineer = true,
}
local squadList = SquadRequestRules.ValidateCall({ action = "list" }, 1, assignableRoles)
check(squadList ~= nil, "squad read request validates")
local forgedSquadRequest = SquadRequestRules.ValidateCall({
	action = "join",
	squadId = "SQD-0001",
	role = "Commander",
}, 1, assignableRoles)
check(forgedSquadRequest == nil, "unexpected squad permission fields are rejected")

local radioState = RadioRules.ValidateCall({ action = "state" }, 1, RadioConfig.MaxMessageBytes)
check(radioState ~= nil, "radio read request validates")
local missionState = MatchRules.ValidateRequest({ action = "state" }, 1)
check(missionState == true, "mission read request validates")
local forgedMissionAction = MatchRules.ValidateRequest({ action = "complete_objective" }, 1)
check(forgedMissionAction == false, "client objective completion is rejected")

local createInventory = InventoryRules.Create(InventoryConfig, MedicalConfig) :: any
local initialMagazine = createInventory.Weapons.Rifle.Magazine
InventoryRules.ConsumeAmmo(createInventory)
check(
	createInventory.Weapons.Rifle.Magazine == initialMagazine - 1,
	"inventory rule state changes only through its validated rule operation"
)

print(`Fase 11: {checks} comprobaciones de integración pasaron.`)
