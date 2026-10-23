--!strict

type Wound = {
	Severity: number,
	BleedRate: number,
}

type MedicalState = {
	Health: number,
	MaxHealth: number,
	Wounds: { Wound },
	BleedRate: number,
	IsIncapacitated: boolean,
	IncapacitatedUntil: number?,
}

local MedicalRules = {}

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function MedicalRules.ValidateConfig(config: any): boolean
	if type(config) ~= "table"
		or type(config.Items) ~= "table"
		or type(config.SeverityThresholds) ~= "table"
		or type(config.BleedRateBySeverity) ~= "table"
		or type(config.IncapacitationEnabled) ~= "boolean"
		or type(config.MedicOnlyForAllyTreatment) ~= "boolean"
	then
		return false
	end
	local configData = config :: { [string]: any }
	local thresholds = configData.SeverityThresholds :: { [string]: any }
	local bleedRates = configData.BleedRateBySeverity :: { [number]: any }
	local items = configData.Items :: { [string]: any }
	if not isFiniteNumber(configData.MaxWounds)
		or configData.MaxWounds < 1
		or configData.MaxWounds % 1 ~= 0
		or not isFiniteNumber(thresholds.ModerateDamage)
		or not isFiniteNumber(thresholds.SevereDamage)
		or thresholds.ModerateDamage <= 0
		or thresholds.SevereDamage <= thresholds.ModerateDamage
		or not isFiniteNumber(configData.MaxBleedDamagePerTick)
		or configData.MaxBleedDamagePerTick <= 0
		or not isFiniteNumber(configData.BleedTickSeconds)
		or configData.BleedTickSeconds <= 0
		or configData.BleedTickSeconds > 10
		or not isFiniteNumber(configData.IncapacitationHealth)
		or configData.IncapacitationHealth <= 0
		or not isFiniteNumber(configData.IncapacitationDuration)
		or configData.IncapacitationDuration <= 0
		or not isFiniteNumber(configData.ReviveHealth)
		or configData.ReviveHealth <= 0
		or not isFiniteNumber(configData.TreatmentRange)
		or configData.TreatmentRange <= 0
		or not isFiniteNumber(configData.TreatmentCooldown)
		or configData.TreatmentCooldown < 0
		or not isFiniteNumber(configData.RequestWindowSeconds)
		or configData.RequestWindowSeconds <= 0
		or not isFiniteNumber(configData.MaxRequestsPerWindow)
		or configData.MaxRequestsPerWindow < 1
		or configData.MaxRequestsPerWindow % 1 ~= 0
	then
		return false
	end
	for severity = 1, 3 do
		if not isFiniteNumber(bleedRates[severity])
			or bleedRates[severity] < 0
			or bleedRates[severity] > configData.MaxBleedDamagePerTick
		then
			return false
		end
	end
	for itemId, item in pairs(items) do
		if type(itemId) ~= "string"
			or type(item) ~= "table"
			or type((item :: { [string]: any }).DisplayName) ~= "string"
			or (item :: { [string]: any }).DisplayName == ""
			or not isFiniteNumber((item :: { [string]: any }).InitialCount)
			or (item :: { [string]: any }).InitialCount < 0
			or (item :: { [string]: any }).InitialCount % 1 ~= 0
			or not isFiniteNumber((item :: { [string]: any }).UseSeconds)
			or (item :: { [string]: any }).UseSeconds <= 0
			or (item :: { [string]: any }).UseSeconds > 10
		then
			return false
		end
		if itemId == "EmergencyKit" then
			continue
		end
		local itemData = item :: { [string]: any }
		if not isFiniteNumber(itemData.HealAmount)
			or itemData.HealAmount < 0
			or not isFiniteNumber(itemData.BleedReduction)
			or itemData.BleedReduction < 0
			or not isFiniteNumber(itemData.MaxSeverity)
			or itemData.MaxSeverity < 1
			or itemData.MaxSeverity > 3
			or itemData.MaxSeverity % 1 ~= 0
			or (itemData.HealAmount == 0 and itemData.BleedReduction == 0)
		then
			return false
		end
	end
	return items.EmergencyKit ~= nil
		and configData.IncapacitationHealth < math.huge
		and (not configData.IncapacitationEnabled or configData.ReviveHealth >= configData.IncapacitationHealth)
end

function MedicalRules.Create(maxHealth: number, config: any): MedicalState?
	if not isFiniteNumber(maxHealth)
		or maxHealth <= 0
		or not MedicalRules.ValidateConfig(config)
	then
		return nil
	end

	return {
		Health = maxHealth,
		MaxHealth = maxHealth,
		Wounds = {},
		BleedRate = 0,
		IsIncapacitated = false,
		IncapacitatedUntil = nil,
	}
end

function MedicalRules.Copy(state: MedicalState): MedicalState
	local wounds: { Wound } = {}
	for index, wound in ipairs(state.Wounds) do
		wounds[index] = {
			Severity = wound.Severity,
			BleedRate = wound.BleedRate,
		}
	end
	return {
		Health = state.Health,
		MaxHealth = state.MaxHealth,
		Wounds = wounds,
		BleedRate = state.BleedRate,
		IsIncapacitated = state.IsIncapacitated,
		IncapacitatedUntil = state.IncapacitatedUntil,
	}
end

function MedicalRules.ApplyDamage(state: MedicalState, amount: number, now: number, config: any): (boolean, string, boolean)
	if not isFiniteNumber(amount) or amount <= 0 or not isFiniteNumber(now) then
		return false, "invalid_damage", false
	end
	if state.Health <= 0 then
		return false, "dead", false
	end
	if state.IsIncapacitated then
		return false, "incapacitated", false
	end

	local thresholds = config.SeverityThresholds
	local severity = if amount >= thresholds.SevereDamage then 3
		elseif amount >= thresholds.ModerateDamage then 2
		else 1
	local bleedRates = config.BleedRateBySeverity
	local woundBleedRate = bleedRates[severity]
	if not isFiniteNumber(woundBleedRate) or woundBleedRate < 0 then
		return false, "invalid_configuration", false
	end

	if #state.Wounds < config.MaxWounds then
		table.insert(state.Wounds, {
			Severity = severity,
			BleedRate = woundBleedRate,
		})
		state.BleedRate = math.min(state.BleedRate + woundBleedRate, config.MaxBleedDamagePerTick)
	end

	local remainingHealth = math.max(0, state.Health - amount)
	if remainingHealth <= 0
		and config.IncapacitationEnabled == true
		and config.IncapacitationHealth < state.MaxHealth
	then
		state.Health = math.min(config.IncapacitationHealth, state.MaxHealth)
		state.IsIncapacitated = true
		state.IncapacitatedUntil = now + config.IncapacitationDuration
		return true, "incapacitated", true
	end

	state.Health = remainingHealth
	return true, "damaged", false
end

function MedicalRules.ApplyBleedTick(state: MedicalState, deltaSeconds: number, now: number, config: any): (number, boolean)
	if not isFiniteNumber(deltaSeconds) or deltaSeconds <= 0 or not isFiniteNumber(now) then
		return 0, false
	end
	if state.Health <= 0 then
		return 0, true
	end
	if state.IsIncapacitated then
		if state.IncapacitatedUntil ~= nil and now >= state.IncapacitatedUntil then
			state.Health = 0
			return 0, true
		end
		return 0, false
	end
	if state.BleedRate <= 0 then
		return 0, false
	end

	local damage = math.min(state.BleedRate * deltaSeconds, config.MaxBleedDamagePerTick, state.Health)
	state.Health = math.max(0, state.Health - damage)
	if state.Health <= 0 and config.IncapacitationEnabled == true then
		state.Health = math.min(config.IncapacitationHealth, state.MaxHealth)
		state.IsIncapacitated = true
		state.IncapacitatedUntil = now + config.IncapacitationDuration
		return damage, false
	end
	return damage, state.Health <= 0
end

function MedicalRules.CanTreat(state: MedicalState, item: any): (boolean, string)
	if type(item) ~= "table" then
		return false, "invalid_item"
	end
	if state.Health <= 0 then
		return false, "target_dead"
	end
	if state.IsIncapacitated then
		return false, "target_incapacitated"
	end

	local hasEligibleWound = false
	for _, wound in ipairs(state.Wounds) do
		if wound.Severity <= item.MaxSeverity then
			hasEligibleWound = true
			break
		end
	end
	local canHeal = isFiniteNumber(item.HealAmount)
		and item.HealAmount > 0
		and state.Health < state.MaxHealth
	local canReduceBleeding = isFiniteNumber(item.BleedReduction)
		and item.BleedReduction > 0
		and state.BleedRate > 0
		and hasEligibleWound
	if canHeal or canReduceBleeding then
		return true, "treatment_valid"
	end
	return false, "no_treatment_needed"
end

function MedicalRules.ApplyTreatment(state: MedicalState, item: any): (boolean, string)
	local canTreat, code = MedicalRules.CanTreat(state, item)
	if not canTreat then
		return false, code
	end

	local healing = if isFiniteNumber(item.HealAmount) then math.max(0, item.HealAmount) else 0
	state.Health = math.min(state.MaxHealth, state.Health + healing)

	local remainingWounds: { Wound } = {}
	local removedBleedRate = 0
	for _, wound in ipairs(state.Wounds) do
		if wound.Severity <= item.MaxSeverity then
			removedBleedRate += wound.BleedRate
		else
			table.insert(remainingWounds, wound)
		end
	end
	state.Wounds = remainingWounds
	state.BleedRate = math.max(0, math.min(state.BleedRate - removedBleedRate, state.BleedRate - item.BleedReduction))
	return true, "treated"
end

function MedicalRules.Revive(state: MedicalState, now: number, config: any): (boolean, string)
	if not state.IsIncapacitated or state.Health <= 0 then
		return false, "not_incapacitated"
	end
	if state.IncapacitatedUntil == nil or now >= state.IncapacitatedUntil then
		state.Health = 0
		return false, "incapacitation_expired"
	end
	if not isFiniteNumber(config.ReviveHealth) or config.ReviveHealth <= 0 then
		return false, "invalid_configuration"
	end

	state.Health = math.min(state.MaxHealth, config.ReviveHealth)
	state.IsIncapacitated = false
	state.IncapacitatedUntil = nil
	return true, "revived"
end

function MedicalRules.TakeRateLimitToken(
	bucket: { WindowStartedAt: number, Count: number }?,
	now: number,
	windowSeconds: number,
	maxRequests: number
): (boolean, { WindowStartedAt: number, Count: number })
	if bucket == nil or now - bucket.WindowStartedAt >= windowSeconds then
		return true, { WindowStartedAt = now, Count = 1 }
	end
	if bucket.Count >= maxRequests then
		return false, bucket
	end
	return true, { WindowStartedAt = bucket.WindowStartedAt, Count = bucket.Count + 1 }
end

function MedicalRules.IsWithinRange(distance: number, maxRange: number): boolean
	return isFiniteNumber(distance) and distance >= 0 and isFiniteNumber(maxRange) and maxRange > 0 and distance <= maxRange
end

return table.freeze(MedicalRules)
