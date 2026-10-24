--!strict
local HUDRules = {}

-- North is world -Z; east is +X. The map stays north-up.
function HUDRules.Heading(x: number, z: number): number
	return (math.deg(math.atan2(x, -z)) + 360) % 360
end

function HUDRules.Cardinal(heading: number): string
	local names = { "N", "NE", "E", "SE", "S", "SO", "O", "NO" }
	return names[math.floor((heading + 22.5) / 45) % 8 + 1]
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

function HUDRules.Profile(width: number, height: number)
	local compact = width < 700 or height < 540
	return {
		Compact = compact,
		MapSize = if compact then 100 else 152,
		StatusWidth = math.min(if compact then 174 else 250, math.max(150, width * 0.34)),
		ButtonSize = 48,
		-- No root UIScale or forced aspect ratio: these are effective pixels.
		ShowHotbar = not compact,
		ShowNavigation = width >= 700 and height >= 650,
		ShowMap = width >= 480,
	}
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
