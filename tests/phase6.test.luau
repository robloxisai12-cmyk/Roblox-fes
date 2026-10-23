--!strict

local InventoryConfig = require("../src/shared/config/InventoryConfig")
local MedicalConfig = require("../src/shared/config/MedicalConfig")
local InventoryRules = require("../src/server/services/InventoryRules")
local MedicalRules = require("../src/server/services/MedicalRules")
local CombatRequestRules = require("../src/server/services/CombatRequestRules")

local checks = 0

local function check(condition: boolean, message: string)
	assert(condition, message)
	checks += 1
end

local function expectRequestFailure(request: any, expectedCode: string)
	local normalized, code = CombatRequestRules.Validate(request, 1)
	check(normalized == nil and code == expectedCode, `expected rejection {expectedCode}, got {code}`)
end

check(MedicalRules.ValidateConfig(MedicalConfig), "medical configuration validates")
local invalidConfig: any = table.clone(MedicalConfig)
invalidConfig.BleedTickSeconds = math.huge
check(not MedicalRules.ValidateConfig(invalidConfig), "non-finite medical timing is rejected")

local state = MedicalRules.Create(100, MedicalConfig)
check(state ~= nil and state.Health == 100 and state.MaxHealth == 100, "medical state starts at full health")
check(state ~= nil and #state.Wounds == 0 and state.BleedRate == 0, "medical state starts without injuries")
local medicalState = state :: any

local damaged, damageCode = MedicalRules.ApplyDamage(medicalState, 18, 10, MedicalConfig)
check(damaged and damageCode == "damaged", "valid damage is applied")
check(medicalState.Health == 82 and #medicalState.Wounds == 1, "damage reduces health and records a wound")
check(medicalState.Wounds[1].Severity == 1 and medicalState.BleedRate == 0.5, "minor wound bleeds at configured rate")
local invalidDamage, invalidDamageCode = MedicalRules.ApplyDamage(medicalState, -1, 10, MedicalConfig)
check(not invalidDamage and invalidDamageCode == "invalid_damage", "negative damage is rejected")
check(medicalState.Health == 82 and #medicalState.Wounds == 1, "invalid damage leaves state unchanged")

local tickDamage, deadAfterTick = MedicalRules.ApplyBleedTick(medicalState, 2, 12, MedicalConfig)
check(tickDamage == 1 and not deadAfterTick and medicalState.Health == 81, "bleeding drains health at its configured rate")
local bandage = MedicalConfig.Items.Bandage
local canBandage, canBandageCode = MedicalRules.CanTreat(medicalState, bandage)
check(canBandage and canBandageCode == "treatment_valid", "valid bandage treats an eligible wound")
local bandaged, bandageCode = MedicalRules.ApplyTreatment(medicalState, bandage)
check(bandaged and bandageCode == "treated", "bandage treatment succeeds")
check(medicalState.BleedRate == 0 and #medicalState.Wounds == 0, "bandage stops minor bleeding and clears its wound")
local duplicateBandage, duplicateBandageCode = MedicalRules.CanTreat(medicalState, bandage)
check(not duplicateBandage and duplicateBandageCode == "no_treatment_needed", "already treated target cannot be treated twice")

local kitState = MedicalRules.Create(100, MedicalConfig) :: any
MedicalRules.ApplyDamage(kitState, 30, 20, MedicalConfig)
local kit = MedicalConfig.Items.Medkit
local canUseKit = MedicalRules.CanTreat(kitState, kit)
check(canUseKit, "medkit can treat moderate wounds")
local kitApplied = MedicalRules.ApplyTreatment(kitState, kit)
check(kitApplied and kitState.Health == 100 and kitState.BleedRate == 0, "medkit heals without exceeding maximum health")
kitState.Health = 90
local secondKit = MedicalRules.ApplyTreatment(kitState, kit)
check(secondKit and kitState.Health == 100, "medical healing remains capped at maximum health")

local inventory = InventoryRules.Create(InventoryConfig, MedicalConfig) :: any
check(inventory.MedicalItems.Bandage == 3 and inventory.MedicalItems.Medkit == 1, "medical inventory initializes configured supplies")
check(InventoryRules.Create(InventoryConfig, { Items = { Bandage = { InitialCount = math.huge } } }) == nil, "invalid medical inventory configuration is rejected")
local consumedBandage, consumedCode = InventoryRules.ConsumeMedicalItem(inventory, "Bandage", MedicalConfig)
check(consumedBandage and consumedCode == "consumed" and inventory.MedicalItems.Bandage == 2, "valid medical item consumes exactly one unit")
local unknownItem, unknownItemCode = InventoryRules.ConsumeMedicalItem(inventory, "Unknown", MedicalConfig)
check(not unknownItem and unknownItemCode == "invalid_medical_item", "unknown medical item is rejected")
check(inventory.MedicalItems.Bandage == 2, "rejected item does not consume inventory")
inventory.MedicalItems.EmergencyKit = 0
local absentItem, absentItemCode = InventoryRules.ConsumeMedicalItem(inventory, "EmergencyKit", MedicalConfig)
check(not absentItem and absentItemCode == "no_medical_items", "empty medical supply cannot be consumed")
local fullHealthState = MedicalRules.Create(100, MedicalConfig) :: any
local noTreatment, noTreatmentCode = MedicalRules.CanTreat(fullHealthState, bandage)
local countBeforeRejectedTreatment = inventory.MedicalItems.Bandage
check(not noTreatment and noTreatmentCode == "no_treatment_needed", "unneeded treatment is rejected")
check(inventory.MedicalItems.Bandage == countBeforeRejectedTreatment, "invalid treatment does not consume a medical item")
local moderateWound = MedicalRules.Create(100, MedicalConfig) :: any
MedicalRules.ApplyDamage(moderateWound, 30, 22, MedicalConfig)
local bandageForModerate, bandageModerateCode = MedicalRules.CanTreat(moderateWound, bandage)
check(not bandageForModerate and bandageModerateCode == "no_treatment_needed", "bandage cannot treat a moderate wound")
check(not MedicalRules.IsWithinRange(13, MedicalConfig.TreatmentRange), "distant target treatment is rejected by server range rule")

local downedState = MedicalRules.Create(100, MedicalConfig) :: any
local lethalApplied, lethalCode, becameIncapacitated =
	MedicalRules.ApplyDamage(downedState, 120, 30, MedicalConfig)
check(lethalApplied and lethalCode == "incapacitated" and becameIncapacitated, "lethal damage enters configured incapacitation")
check(downedState.Health == 1 and downedState.IncapacitatedUntil == 75, "incapacitation preserves a bounded positive health state")
local repeatDownedDamage, repeatDownedCode = MedicalRules.ApplyDamage(downedState, 20, 31, MedicalConfig)
check(not repeatDownedDamage and repeatDownedCode == "incapacitated", "incapacitated target cannot be repeatedly damaged")
local treatDowned, treatDownedCode = MedicalRules.CanTreat(downedState, kit)
check(not treatDowned and treatDownedCode == "target_incapacitated", "ordinary healing cannot replace emergency revive")
local revived, reviveCode = MedicalRules.Revive(downedState, 35, MedicalConfig)
check(revived and reviveCode == "revived" and downedState.Health == 35, "emergency revive restores configured health")
check(not downedState.IsIncapacitated and downedState.IncapacitatedUntil == nil, "revive clears incapacitation")
local duplicateRevive, duplicateReviveCode = MedicalRules.Revive(downedState, 36, MedicalConfig)
check(not duplicateRevive and duplicateReviveCode == "not_incapacitated", "revive cannot be repeated for duplicate health")

local lowHealthState = MedicalRules.Create(1, MedicalConfig) :: any
local lowHealthDamage, lowHealthCode, lowHealthDowned =
	MedicalRules.ApplyDamage(lowHealthState, 1, 40, MedicalConfig)
check(lowHealthDamage and lowHealthCode == "damaged" and not lowHealthDowned, "low-health NPC dies instead of entering invalid incapacitation")
check(lowHealthState.Health == 0, "lethal damage never leaves health negative")

local expiredState = MedicalRules.Create(100, MedicalConfig) :: any
MedicalRules.ApplyDamage(expiredState, 100, 10, MedicalConfig)
local expiredRevive, expiredCode = MedicalRules.Revive(expiredState, 60, MedicalConfig)
check(not expiredRevive and expiredCode == "incapacitation_expired" and expiredState.Health == 0, "expired incapacitation cannot be revived")
local deadAfterExpiry, _ = MedicalRules.ApplyBleedTick(expiredState, 1, 61, MedicalConfig)
check(deadAfterExpiry == 0, "dead state no longer processes bleeding")

local bleedingDownedState = MedicalRules.Create(100, MedicalConfig) :: any
MedicalRules.ApplyDamage(bleedingDownedState, 99, 100, MedicalConfig)
local _, bleedFatal = MedicalRules.ApplyBleedTick(bleedingDownedState, 100, 101, MedicalConfig)
check(not bleedFatal and bleedingDownedState.IsIncapacitated, "fatal bleeding transitions to incapacitation")
local downedBleedDamage = MedicalRules.ApplyBleedTick(bleedingDownedState, 1, 102, MedicalConfig)
check(downedBleedDamage == 0, "bleeding processing pauses while incapacitated")

local firstRequest, requestError = CombatRequestRules.Validate({
	action = "treat",
	itemId = "Bandage",
	targetUserId = 12345,
}, 1)
check(firstRequest ~= nil and requestError == nil, "valid treatment request is accepted")
expectRequestFailure({ action = "treat", itemId = "Bandage", targetUserId = -1 }, "invalid_target")
expectRequestFailure({ action = "treat", itemId = string.rep("x", 33), targetUserId = 123 }, "invalid_medical_item")
expectRequestFailure({ action = "treat", itemId = "Bandage", targetUserId = 123, health = 100 }, "unexpected_field")
expectRequestFailure({ action = "medical_status", health = 100 }, "unexpected_field")
expectRequestFailure({ action = "cancel_treatment", targetUserId = 123 }, "unexpected_field")

local firstToken, firstBucket = MedicalRules.TakeRateLimitToken(nil, 1, 1, 2)
local secondToken, secondBucket = MedicalRules.TakeRateLimitToken(firstBucket, 1.1, 1, 2)
local thirdToken, unchangedBucket = MedicalRules.TakeRateLimitToken(secondBucket, 1.2, 1, 2)
check(firstToken and secondToken and not thirdToken, "medical actions are rate limited")
check(unchangedBucket.Count == secondBucket.Count, "rejected medical request does not extend the limit")
local afterWindow = MedicalRules.TakeRateLimitToken(unchangedBucket, 2.2, 1, 2)
check(afterWindow, "medical request limit resets after its window")
check(MedicalRules.IsWithinRange(12, 12), "target at treatment range is valid")
check(not MedicalRules.IsWithinRange(12.01, 12), "target outside treatment range is rejected")
check(not MedicalRules.IsWithinRange(0 / 0, 12), "invalid treatment distance is rejected")

local respawnState = MedicalRules.Create(100, MedicalConfig) :: any
check(respawnState.Health == 100 and #respawnState.Wounds == 0, "new character receives a clean, independent medical state")
check(respawnState ~= medicalState, "respawn state does not reuse previous character state")

print(`Fase 6: {checks} comprobaciones de reglas médicas e inventario pasaron.`)
