--!strict

local VehicleRules = {}

function VehicleRules.CanEnter(isAlive: boolean, isOccupied: boolean, isAuthorized: boolean): (boolean, string)
	if not isAlive then
		return false, "player_unavailable"
	end
	if not isAuthorized then
		return false, "driver_unauthorized"
	end
	if isOccupied then
		return false, "vehicle_occupied"
	end
	return true, "ready"
end

function VehicleRules.CanExit(isOccupant: boolean): (boolean, string)
	if not isOccupant then
		return false, "not_vehicle_occupant"
	end
	return true, "ready"
end

function VehicleRules.IsSafeInteraction(distance: number, maximumDistance: number, isAlive: boolean): boolean
	return isAlive
		and type(distance) == "number"
		and distance == distance
		and distance >= 0
		and distance < math.huge
		and type(maximumDistance) == "number"
		and maximumDistance > 0
		and distance <= maximumDistance
end

return table.freeze(VehicleRules)
