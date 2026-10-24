--!strict
local HUDRules = {}

local function finite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

-- North is world -Z; east is +X. The map stays north-up.
function HUDRules.Heading(x: number, z: number): number
	return (math.deg(math.atan2(x, -z)) + 360) % 360
end

function HUDRules.Cardinal(heading: number): string
	local names = { "N", "NE", "E", "SE", "S", "SO", "O", "NO" }
	return names[math.floor((heading + 22.5) / 45) % 8 + 1]
end

-- Signed angular distance (-180, 180] from the player's heading to a compass mark.
function HUDRules.CompassOffset(angle: number, heading: number): number
	local offset = (angle - heading) % 360
	if offset > 180 then
		offset -= 360
	end
	return offset
end

function HUDRules.Project(
	x: number,
	z: number,
	centerX: number,
	centerZ: number,
	range: number,
	size: number
): (number, number)
	return size / 2 + (x - centerX) * size / (2 * range), size / 2 + (z - centerZ) * size / (2 * range)
end

-- Name of the real configured place that contains the position. The most specific zone wins:
-- logistics points, then the spawn plaza, then the town, then the map itself.
function HUDRules.Zone(x: number, z: number, mapConfig: any, logisticsConfig: any): string
	local function inside(center: any, radius: number): boolean
		return (x - center.X) ^ 2 + (z - center.Z) ^ 2 <= radius ^ 2
	end
	local best: string? = nil
	local bestRadius = math.huge
	local points: { any } = if logisticsConfig ~= nil and type(logisticsConfig.SupplyPoints) == "table"
		then logisticsConfig.SupplyPoints
		else {}
	for _, point in ipairs(points) do
		if inside(point, point.Radius) and point.Radius < bestRadius then
			best, bestRadius = point.Name, point.Radius
		end
	end
	if best ~= nil then
		return best
	end
	if mapConfig.SpawnZone ~= nil and inside(mapConfig.SpawnZone.Center, mapConfig.SpawnZone.Radius) then
		return mapConfig.SpawnZone.Name
	end
	if mapConfig.Town ~= nil and inside(mapConfig.Town.Center, mapConfig.Town.Radius) then
		return mapConfig.Town.Name
	end
	return mapConfig.Name
end

function HUDRules.Fraction(value: number?, maximum: number?): number
	if value == nil or maximum == nil or not finite(value) or not finite(maximum) or maximum <= 0 then
		return 0
	end
	return math.clamp(value / maximum, 0, 1)
end

-- Text and tone ("ok" | "warn" | "danger" | "neutral") for the character condition. It only reads the
-- real medical snapshot: nothing is shown as healthy before the server has answered.
function HUDRules.Condition(mode: string, health: number?, maxHealth: number?, medical: any?): (string, string)
	if mode == "unavailable" then
		return "SIN PERSONAJE ACTIVO", "neutral"
	end
	if mode == "incapacitated" then
		return "INCAPACITADO", "danger"
	end
	if medical == nil then
		return "SINCRONIZANDO", "neutral"
	end
	local bleedRate = if type(medical.bleedRate) == "number" then medical.bleedRate else 0
	if bleedRate > 0 then
		return string.format("SANGRANDO %.1f/s", bleedRate), "warn"
	end
	local wounds = if type(medical.wounds) == "number" then medical.wounds else 0
	if wounds > 0 then
		return string.format("HERIDAS %d", math.floor(wounds)), "warn"
	end
	if health ~= nil and maxHealth ~= nil and maxHealth > 0 and health < maxHealth then
		return "HERIDO", "neutral"
	end
	return "ESTABLE", "ok"
end

function HUDRules.Mode(alive: boolean, incapacitated: boolean, seatedPickup: boolean): string
	if not alive then
		return "unavailable"
	end
	if incapacitated then
		return "incapacitated"
	end
	return if seatedPickup then "driving" else "walking"
end

function HUDRules.Axes(held: { [string]: boolean }): (number, number)
	if held.Brake then
		return 0, 0
	end
	local throttle = (if held.Forward then 1 else 0) - (if held.Reverse then 1 else 0)
	local steer = (if held.Right then 1 else 0) - (if held.Left then 1 else 0)
	return throttle, steer
end

return table.freeze(HUDRules)
