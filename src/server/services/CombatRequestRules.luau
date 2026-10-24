--!strict

type ValidRequest =
	{ action: "shoot", direction: { x: number, y: number, z: number } }
	| { action: "reload" }
	| { action: "equip", weaponId: string }
	| { action: "treat", itemId: string, targetUserId: number }
	| { action: "medical_status" }
	| { action: "cancel_treatment" }
	| LogisticsRequest

type LogisticsRequest = {
	action: "logistics",
	operation: string,
	vehicleId: string?,
	pointId: string?,
	resourceId: string?,
	amount: number?,
	throttle: number?,
	steer: number?,
}

local CombatRequestRules = {}

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function hasOnlyFields(value: { [any]: any }, allowedFields: { [string]: boolean }): boolean
	for key in pairs(value) do
		if type(key) ~= "string" or allowedFields[key] ~= true then
			return false
		end
	end
	return true
end

function CombatRequestRules.Validate(value: any, argumentCount: number): (ValidRequest?, string?)
	if argumentCount ~= 1 then
		return nil, "invalid_argument_count"
	end
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return nil, "invalid_request"
	end

	local action = value.action
	if action == "shoot" then
		if not hasOnlyFields(value, { action = true, direction = true }) then
			return nil, "unexpected_field"
		end
		local direction = value.direction
		if type(direction) ~= "table" or getmetatable(direction) ~= nil then
			return nil, "invalid_direction"
		end
		if
			not hasOnlyFields(direction, { x = true, y = true, z = true })
			or not isFiniteNumber(direction.x)
			or not isFiniteNumber(direction.y)
			or not isFiniteNumber(direction.z)
		then
			return nil, "invalid_direction"
		end

		local magnitude = math.sqrt(direction.x ^ 2 + direction.y ^ 2 + direction.z ^ 2)
		if magnitude < 0.9 or magnitude > 1.1 then
			return nil, "invalid_direction"
		end
		local normalizedDirection: { x: number, y: number, z: number } = {
			x = direction.x / magnitude,
			y = direction.y / magnitude,
			z = direction.z / magnitude,
		}
		return {
			action = "shoot",
			direction = normalizedDirection,
		}, nil
	elseif action == "reload" then
		if not hasOnlyFields(value, { action = true }) then
			return nil, "unexpected_field"
		end
		return { action = "reload" }, nil
	elseif action == "equip" then
		if not hasOnlyFields(value, { action = true, weaponId = true }) then
			return nil, "unexpected_field"
		end
		local weaponId = value.weaponId
		if type(weaponId) ~= "string" or #weaponId < 1 or #weaponId > 32 then
			return nil, "invalid_weapon"
		end
		return {
			action = "equip",
			weaponId = weaponId,
		}, nil
	elseif action == "treat" then
		if not hasOnlyFields(value, { action = true, itemId = true, targetUserId = true }) then
			return nil, "unexpected_field"
		end
		local itemId = value.itemId
		local targetUserId = value.targetUserId
		if type(itemId) ~= "string" or #itemId < 1 or #itemId > 32 then
			return nil, "invalid_medical_item"
		end
		if not isFiniteNumber(targetUserId) or targetUserId <= 0 or targetUserId % 1 ~= 0 then
			return nil, "invalid_target"
		end
		return {
			action = "treat",
			itemId = itemId,
			targetUserId = targetUserId,
		}, nil
	elseif action == "medical_status" or action == "cancel_treatment" then
		if not hasOnlyFields(value, { action = true }) then
			return nil, "unexpected_field"
		end
		if action == "medical_status" then
			return { action = "medical_status" }, nil
		end
		return { action = "cancel_treatment" }, nil
	elseif action == "logistics" then
		local operation: string = value.operation
		if type(operation) ~= "string" then
			return nil, "invalid_operation"
		end
		local allowedFields: { [string]: boolean } = { action = true, operation = true }
		local normalized: LogisticsRequest = {
			action = "logistics",
			operation = operation,
			vehicleId = nil,
			pointId = nil,
			resourceId = nil,
			amount = nil,
		}
		if operation == "status" then
			if not hasOnlyFields(value, allowedFields) then
				return nil, "unexpected_field"
			end
			return normalized, nil
		elseif operation == "drive" then
			allowedFields.vehicleId = true
			allowedFields.throttle = true
			allowedFields.steer = true
			if
				type(value.vehicleId) ~= "string"
				or #value.vehicleId < 1
				or #value.vehicleId > 32
				or not isFiniteNumber(value.throttle)
				or math.abs(value.throttle) > 1
				or not isFiniteNumber(value.steer)
				or math.abs(value.steer) > 1
			then
				return nil, "invalid_drive_input"
			end
			normalized.vehicleId = value.vehicleId
			normalized.throttle = value.throttle
			normalized.steer = value.steer
		elseif operation == "enter_vehicle" or operation == "exit_vehicle" or operation == "deliver_cargo" then
			allowedFields.vehicleId = true
			local vehicleId = value.vehicleId
			if type(vehicleId) ~= "string" or #vehicleId < 1 or #vehicleId > 32 then
				return nil, "invalid_vehicle"
			end
			normalized.vehicleId = vehicleId :: string
		elseif operation == "load_cargo" then
			allowedFields.vehicleId = true
			allowedFields.resourceId = true
			allowedFields.amount = true
			local vehicleId = value.vehicleId
			local resourceId = value.resourceId
			local amount = value.amount
			if
				type(vehicleId) ~= "string"
				or #vehicleId < 1
				or #vehicleId > 32
				or type(resourceId) ~= "string"
				or #resourceId < 1
				or #resourceId > 32
				or type(amount) ~= "number"
				or not isFiniteNumber(amount)
				or amount < 1
				or amount > 8
				or amount % 1 ~= 0
			then
				return nil, "invalid_logistics_request"
			end
			normalized.vehicleId = vehicleId :: string
			normalized.resourceId = resourceId :: string
			normalized.amount = amount :: number
		elseif operation == "resupply" then
			allowedFields.pointId = true
			allowedFields.resourceId = true
			allowedFields.amount = true
			local pointId = value.pointId
			local resourceId = value.resourceId
			local amount = value.amount
			if
				type(pointId) ~= "string"
				or #pointId < 1
				or #pointId > 32
				or type(resourceId) ~= "string"
				or #resourceId < 1
				or #resourceId > 32
				or type(amount) ~= "number"
				or not isFiniteNumber(amount)
				or amount < 1
				or amount > 8
				or amount % 1 ~= 0
			then
				return nil, "invalid_logistics_request"
			end
			normalized.pointId = pointId :: string
			normalized.resourceId = resourceId :: string
			normalized.amount = amount :: number
		elseif operation == "refuel" then
			allowedFields.vehicleId = true
			allowedFields.pointId = true
			local vehicleId = value.vehicleId
			local pointId = value.pointId
			if
				type(vehicleId) ~= "string"
				or #vehicleId < 1
				or #vehicleId > 32
				or type(pointId) ~= "string"
				or #pointId < 1
				or #pointId > 32
			then
				return nil, "invalid_logistics_request"
			end
			normalized.vehicleId = vehicleId :: string
			normalized.pointId = pointId :: string
		else
			return nil, "invalid_operation"
		end
		if not hasOnlyFields(value, allowedFields) then
			return nil, "unexpected_field"
		end
		return normalized, nil
	end

	return nil, "invalid_action"
end

return table.freeze(CombatRequestRules)
