--!strict

local TacticalUIRules = {}

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

function TacticalUIRules.GetProfile(width: number, height: number)
	if not isFinite(width) or not isFinite(height) or width <= 0 or height <= 0 then
		width = 1280
		height = 720
	end

	local scale = math.clamp(math.min(width / 430, height / 520), 0.9, 1.2)
	return {
		IsCompact = width < 720,
		Scale = scale,
		PanelWidth = math.max(1, math.min(width - 24, 460)),
		PanelHeight = math.max(1, math.min(height - 96, 520)),
		TouchTargetSize = 48,
	}
end

function TacticalUIRules.GetCondition(
	health: number,
	maxHealth: number,
	wounds: number,
	bleedRate: number,
	incapacitated: boolean
): string
	if incapacitated then
		return "INCAPACITADO"
	elseif bleedRate > 0 then
		return string.format("SANGRANDO %.1f/s", bleedRate)
	elseif wounds > 0 then
		return string.format("HERIDAS %d", math.floor(wounds))
	elseif maxHealth > 0 and health < maxHealth then
		return "HERIDO"
	end
	return "ESTABLE"
end

function TacticalUIRules.GetAmmoText(magazine: number, reserve: number, isReloading: boolean): string
	if isReloading then
		return "RECARGANDO"
	end
	return string.format("%d  |  %d", math.max(0, math.floor(magazine)), math.max(0, math.floor(reserve)))
end

return table.freeze(TacticalUIRules)
