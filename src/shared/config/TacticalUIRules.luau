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
	if health <= 0 and maxHealth > 0 then
		return "MUERTO"
	elseif incapacitated then
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

local combatMessages = {
	no_ammo = "Sin municion. Recarga el arma.",
	no_reserve_ammo = "No queda municion de reserva.",
	magazine_full = "El cargador esta lleno.",
	reloading = "Espera a que termine la recarga.",
	already_reloading = "La recarga ya esta en curso.",
	attacker_unavailable = "No puedes combatir con el personaje en este estado.",
	rate_limited = "Espera un momento antes de volver a intentarlo.",
	reload_started = "Recargando...",
	reload_complete = "Recarga completa.",
	equipped = "Arma equipada.",
}

function TacticalUIRules.GetCombatMessage(code: any, ok: boolean): string
	if type(code) == "string" and combatMessages[code] ~= nil then
		return combatMessages[code]
	end
	return if ok then "" else "No se pudo completar la accion."
end

return table.freeze(TacticalUIRules)
