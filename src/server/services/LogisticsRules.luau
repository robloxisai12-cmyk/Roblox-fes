--!strict

type Cargo = { [string]: number }
type Stock = { [string]: number }

local LogisticsRules = {}

local function isInteger(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge and value % 1 == 0
end

function LogisticsRules.ValidateConfig(config: any): boolean
	if type(config) ~= "table"
		or type(config.Vehicles) ~= "table"
		or type(config.Resources) ~= "table"
		or type(config.SupplyPoints) ~= "table"
		or not isInteger(config.MaxRequestAmount)
		or config.MaxRequestAmount < 1
		or not isInteger(config.MaxRequestsPerWindow)
		or config.MaxRequestsPerWindow < 1
		or type(config.Resupply) ~= "table"
	then
		return false
	end
	local configData = config :: { [string]: any }
	local vehicles = configData.Vehicles :: { [string]: any }
	local resources = configData.Resources :: { [string]: any }
	local supplyPoints = configData.SupplyPoints :: { any }
	for vehicleId, vehicle in pairs(vehicles) do
		local vehicleData = vehicle :: { [string]: any }
		if type(vehicleId) ~= "string"
			or type(vehicleData.AllowedDriverRoles) ~= "table"
			or type(vehicleData.Spawns) ~= "table"
			or type(vehicleData.MaxSpeed) ~= "number"
			or vehicleData.MaxSpeed <= 0
			or type(vehicleData.ReverseSpeed) ~= "number"
			or vehicleData.ReverseSpeed < 0
			or type(vehicleData.TurnRate) ~= "number"
			or vehicleData.TurnRate <= 0
			or type(vehicleData.FuelCapacity) ~= "number"
			or vehicleData.FuelCapacity <= 0
			or type(vehicleData.InitialFuel) ~= "number"
			or vehicleData.InitialFuel < 0
			or vehicleData.InitialFuel > vehicleData.FuelCapacity
			or type(vehicleData.FuelPerStud) ~= "number"
			or vehicleData.FuelPerStud <= 0
			or not isInteger(vehicleData.CargoCapacity)
			or vehicleData.CargoCapacity < 1
		then
			return false
		end
	end
	for resourceId, resource in pairs(resources) do
		local resourceData = resource :: { [string]: any }
		if type(resourceId) ~= "string"
			or type(resourceData.Weight) ~= "number"
			or resourceData.Weight <= 0
		then
			return false
		end
	end
	for _, point in ipairs(supplyPoints) do
		local pointData = point :: { [string]: any }
		if type(pointData.Id) ~= "string"
			or type(pointData.Name) ~= "string"
			or (pointData.Kind ~= "Depot" and pointData.Kind ~= "Delivery")
			or type(pointData.Stock) ~= "table"
			or type(pointData.MaxStock) ~= "table"
			or type(pointData.RestockAmount) ~= "table"
			or type(pointData.RestockSeconds) ~= "number"
			or pointData.RestockSeconds <= 0
			or type(pointData.Radius) ~= "number"
			or pointData.Radius <= 0
		then
			return false
		end
		local pointStock = pointData.Stock :: { [string]: any }
		local pointMaxStock = pointData.MaxStock :: { [string]: any }
		local pointRestock = pointData.RestockAmount :: { [string]: any }
		for resourceId in pairs(resources) do
			if not isInteger(pointStock[resourceId])
				or pointStock[resourceId] < 0
				or not isInteger(pointMaxStock[resourceId])
				or pointMaxStock[resourceId] < pointStock[resourceId]
				or not isInteger(pointRestock[resourceId])
				or pointRestock[resourceId] < 0
			then
				return false
			end
		end
	end
	return true
end

function LogisticsRules.CreateCargo(config: any): Cargo
	local cargo: Cargo = {}
	for resourceId in pairs(config.Resources) do
		cargo[resourceId] = 0
	end
	return cargo
end

function LogisticsRules.CargoWeight(cargo: Cargo, resources: any): number
	local weight = 0
	for resourceId, count in pairs(cargo) do
		local resource = resources[resourceId]
		if resource ~= nil and isInteger(count) and count > 0 then
			weight += count * resource.Weight
		end
	end
	return weight
end

function LogisticsRules.LoadCargo(
	cargo: Cargo,
	stock: Stock,
	resources: any,
	capacity: number,
	resourceId: any,
	amount: any
): (boolean, string)
	if type(resourceId) ~= "string" or resources[resourceId] == nil then
		return false, "invalid_resource"
	end
	if not isInteger(amount) or amount <= 0 then
		return false, "invalid_amount"
	end
	local available = stock[resourceId]
	if not isInteger(available) or amount > available then
		return false, "insufficient_stock"
	end
	local weight = resources[resourceId].Weight
	if LogisticsRules.CargoWeight(cargo, resources) + amount * weight > capacity then
		return false, "cargo_full"
	end
	stock[resourceId] = available - amount
	cargo[resourceId] = (cargo[resourceId] or 0) + amount
	return true, "loaded"
end

function LogisticsRules.DeliverCargo(
	cargo: Cargo,
	stock: Stock,
	maxStock: Stock,
	resources: any,
	resourceId: any?,
	amount: any?
): (boolean, string)
	if resourceId == nil then
		local deliveredAny = false
		for id, count in pairs(cargo) do
			if count > 0 then
				local delivered = math.min(count, math.max(0, maxStock[id] - (stock[id] or 0)))
				if delivered > 0 then
					stock[id] = (stock[id] or 0) + delivered
					cargo[id] -= delivered
					deliveredAny = true
				end
			end
		end
		return deliveredAny, if deliveredAny then "delivered" else "destination_full"
	end
	if type(resourceId) ~= "string" or resources[resourceId] == nil then
		return false, "invalid_resource"
	end
	local delivered = if amount == nil then cargo[resourceId] else amount
	if not isInteger(delivered) or delivered <= 0 or delivered > (cargo[resourceId] or 0) then
		return false, "invalid_amount"
	end
	local accepted = math.min(delivered, math.max(0, maxStock[resourceId] - (stock[resourceId] or 0)))
	if accepted <= 0 then
		return false, "destination_full"
	end
	cargo[resourceId] -= accepted
	stock[resourceId] = (stock[resourceId] or 0) + accepted
	return true, "delivered"
end

function LogisticsRules.TakeStock(stock: Stock, resourceId: any, amount: any): (boolean, string)
	if type(resourceId) ~= "string" or stock[resourceId] == nil then
		return false, "invalid_resource"
	end
	if not isInteger(amount) or amount <= 0 then
		return false, "invalid_amount"
	end
	if stock[resourceId] < amount then
		return false, "insufficient_stock"
	end
	stock[resourceId] -= amount
	return true, "taken"
end

function LogisticsRules.Restock(
	point: { Stock: Stock, MaxStock: Stock, RestockAmount: Stock },
	now: number,
	nextRestockAt: number,
	interval: number
): (number, number)
	if type(now) ~= "number" or now ~= now or type(nextRestockAt) ~= "number" or now < nextRestockAt then
		return 0, nextRestockAt
	end
	for resourceId, amount in pairs(point.RestockAmount) do
		point.Stock[resourceId] = math.min(
			point.MaxStock[resourceId] or math.huge,
			(point.Stock[resourceId] or 0) + amount
		)
	end
	return 1, now + interval
end

function LogisticsRules.CanDrive(fuel: number, isOccupied: boolean, isAuthorized: boolean): (boolean, string)
	if not isOccupied then
		return false, "driver_required"
	end
	if not isAuthorized then
		return false, "driver_unauthorized"
	end
	if not isInteger(math.floor(fuel)) or fuel <= 0 then
		return false, "out_of_fuel"
	end
	return true, "ready"
end

function LogisticsRules.StepVehicle(
	fuel: number,
	throttle: number,
	maxSpeed: number,
	reverseSpeed: number,
	fuelPerStud: number,
	deltaTime: number
): (number, number)
	if type(throttle) ~= "number" or throttle ~= throttle or deltaTime <= 0 then
		return 0, fuel
	end
	local boundedThrottle = math.clamp(throttle, -1, 1)
	local speed = if boundedThrottle >= 0 then boundedThrottle * maxSpeed else boundedThrottle * reverseSpeed
	local distance = math.abs(speed) * deltaTime
	local fuelUsed = math.min(fuel, distance * fuelPerStud)
	if fuelUsed < distance * fuelPerStud then
		speed = speed * (fuelUsed / (distance * fuelPerStud))
	end
	return speed, math.max(0, fuel - fuelUsed)
end

function LogisticsRules.Refuel(fuel: number, capacity: number, stock: Stock, amountPerUnit: number): (number, number, string)
	if not isInteger(amountPerUnit) or amountPerUnit <= 0 then
		return fuel, 0, "invalid_configuration"
	end
	local needed = math.ceil((capacity - fuel) / amountPerUnit)
	if needed <= 0 then
		return fuel, 0, "tank_full"
	end
	if (stock.Fuel or 0) < needed then
		return fuel, 0, "insufficient_fuel"
	end
	local added = math.min(capacity - fuel, needed * amountPerUnit)
	stock.Fuel -= needed
	return fuel + added, needed, "refueled"
end

function LogisticsRules.TakeRateLimitToken(
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

return table.freeze(LogisticsRules)
