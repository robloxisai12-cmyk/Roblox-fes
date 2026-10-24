--!strict
-- Intent expires on the server and belongs to one particular seated humanoid.
local VehicleInputRules = {}

export type Input = { Driver: any, Throttle: number, Steer: number, ReceivedAt: number }

function VehicleInputRules.CanControl(
	alive: boolean,
	incapacitated: boolean,
	occupant: boolean,
	authorized: boolean
): boolean
	return alive and not incapacitated and occupant and authorized
end

function VehicleInputRules.Read(input: Input?, driver: any, now: number, timeout: number): (number, number)
	if input == nil or input.Driver ~= driver or now < input.ReceivedAt or now - input.ReceivedAt >= timeout then
		return 0, 0
	end
	return input.Throttle, input.Steer
end

return table.freeze(VehicleInputRules)
