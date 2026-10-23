--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local InventoryService = require(script.Parent.InventoryService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local LogisticsRules = require(script.Parent.LogisticsRules)
local VehicleRules = require(script.Parent.VehicleRules)

local configFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("config")
local configModule = configFolder:WaitForChild("LogisticsConfig") :: ModuleScript
local config = require(configModule)
local requestRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CombatRequest") :: RemoteEvent

local WORLD_FOLDER_NAME = "SierraDeGuardiaLogistics"
local INTERACTION_WINDOW_SECONDS = config.RequestWindowSeconds
local MAX_INTERACTIONS_PER_WINDOW = config.MaxRequestsPerWindow

type SupplyPoint = {
	Definition: any,
	Stock: { [string]: number },
	MaxStock: { [string]: number },
	RestockAmount: { [string]: number },
	NextRestockAt: number,
	Part: BasePart?,
}

type VehicleRecord = {
	Id: string,
	Definition: any,
	Model: Model,
	Chassis: BasePart,
	Seat: VehicleSeat,
	Fuel: number,
	Cargo: { [string]: number },
	Speed: number,
	NextStatusAt: number,
}

type RequestBucket = {
	WindowStartedAt: number,
	Count: number,
}

local supplyPoints: { [string]: SupplyPoint } = {}
local vehicles: { [string]: VehicleRecord } = {}
local deliveryTotals: { [string]: { [string]: number } } = {}
local requestBuckets: { [Player]: RequestBucket } = {}
local connections: { RBXScriptConnection } = {}
local isStarted = false
local worldFolder: Folder? = nil
local LogisticsService = {}

local function getCharacter(player: Player): (Model?, Humanoid?, BasePart?)
	if player.Parent ~= Players then
		return nil, nil, nil
	end
	local character = player.Character
	if character == nil or character.Parent == nil or not character:IsDescendantOf(Workspace) then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil
		or humanoid.Health <= 0
		or root == nil
		or not root:IsA("BasePart")
		or character:GetAttribute("SierraIncapacitated") == true
	then
		return nil, nil, nil
	end
	return character, humanoid, root
end

local function getGroundPosition(x: number, z: number): Vector3
	local result = Workspace:Raycast(
		Vector3.new(x, 350, z),
		Vector3.new(0, -650, 0),
		RaycastParams.new()
	)
	return Vector3.new(x, if result ~= nil then result.Position.Y else 24, z)
end

local function createPart(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	canCollide: boolean
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = canCollide
	part.CanTouch = false
	part.CanQuery = canCollide
	part.Material = material
	part.Color = color
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function addPointLabel(part: BasePart, name: string)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PointLabel"
	billboard.Size = UDim2.fromOffset(180, 42)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(22, 29, 31)
	label.BackgroundTransparency = 0.15
	label.TextColor3 = Color3.fromRGB(245, 240, 220)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = name
	label.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label
end

local function createSupplyMarker(pointId: string, point: SupplyPoint, parent: Folder)
	local position = getGroundPosition(point.Definition.X, point.Definition.Z)
	local marker = createPart(
		parent,
		pointId,
		Vector3.new(7, 0.35, 7),
		CFrame.new(position + Vector3.new(0, 0.2, 0)),
		if point.Definition.Kind == "Depot" then Color3.fromRGB(177, 137, 63) else Color3.fromRGB(66, 131, 106),
		Enum.Material.Metal,
		false
	)
	marker:SetAttribute("LogisticsPointId", pointId)
	marker:SetAttribute("LogisticsPointKind", point.Definition.Kind)
	addPointLabel(marker, point.Definition.Name)
	point.Part = marker
end

local function createVehicle(vehicleId: string, definition: any, spawn: any, parent: Folder): VehicleRecord
	local model = Instance.new("Model")
	model.Name = vehicleId
	model:SetAttribute("VehicleId", vehicleId)
	model:SetAttribute("VehicleType", vehicleId:gsub("%d+$", ""))
	model.Parent = parent

	local ground = getGroundPosition(spawn.X, spawn.Z)
	local pivot = CFrame.new(ground + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, math.rad(spawn.Yaw or 0), 0)
	local chassis = createPart(
		model,
		"Chassis",
		Vector3.new(5.5, 1.5, 8),
		CFrame.new(0, 0, 0),
		Color3.fromRGB(75, 91, 70),
		Enum.Material.Metal,
		true
	)
	model.PrimaryPart = chassis
	createPart(
		model,
		"Cabin",
		Vector3.new(4.8, 2, 3.2),
		chassis.CFrame * CFrame.new(0, 1.55, 0.65),
		Color3.fromRGB(92, 104, 83),
		Enum.Material.Metal,
		false
	)
	for _, wheelOffset in ipairs({
		Vector3.new(-2.9, -0.2, -2.5),
		Vector3.new(2.9, -0.2, -2.5),
		Vector3.new(-2.9, -0.2, 2.5),
		Vector3.new(2.9, -0.2, 2.5),
	}) do
		local wheel = createPart(
			model,
			"Wheel",
			Vector3.new(1.25, 2, 2),
			chassis.CFrame * CFrame.new(wheelOffset) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(35, 37, 34),
			Enum.Material.Rubber,
			false
		)
		wheel.Shape = Enum.PartType.Cylinder
	end
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 1, 2)
	seat.CFrame = chassis.CFrame * CFrame.new(0, 1.45, -0.45)
	seat.Anchored = true
	seat.CanCollide = true
	seat.CanTouch = false
	seat.MaxSpeed = definition.MaxSpeed
	seat.Torque = 0
	seat.TurnSpeed = 0
	seat.Color = Color3.fromRGB(54, 63, 48)
	seat.Parent = model
	local record: VehicleRecord = {
		Id = vehicleId,
		Definition = definition,
		Model = model,
		Chassis = chassis,
		Seat = seat,
		Fuel = definition.InitialFuel,
		Cargo = LogisticsRules.CreateCargo(config),
		Speed = 0,
		NextStatusAt = 0,
	}
	model:PivotTo(pivot)
	table.insert(connections, seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = seat.Occupant
		if occupant == nil then
			return
		end
		local occupantCharacter = occupant.Parent
		local player = if occupantCharacter ~= nil then Players:GetPlayerFromCharacter(occupantCharacter) else nil
		if player == nil or not LogisticsService.IsAuthorizedDriver(player, record) then
			occupant.Sit = false
			if player ~= nil then
				requestRemote:FireClient(player, { action = "logistics_result", ok = false, code = "driver_unauthorized" })
			end
		end
	end))
	return record
end

local function getPointPosition(point: SupplyPoint): Vector3
	local marker = point.Part
	if marker ~= nil and marker.Parent ~= nil then
		return marker.Position
	end
	return getGroundPosition(point.Definition.X, point.Definition.Z)
end

local function getVehicle(request: any): VehicleRecord?
	if type(request.vehicleId) ~= "string" then
		return nil
	end
	return vehicles[request.vehicleId]
end

local function getPoint(request: any): SupplyPoint?
	if type(request.pointId) ~= "string" then
		return nil
	end
	return supplyPoints[request.pointId]
end

local function getNearestPoint(position: Vector3, kind: string): (string?, SupplyPoint?, number)
	local nearestId: string? = nil
	local nearest: SupplyPoint? = nil
	local nearestDistance = math.huge
	for pointId, point in pairs(supplyPoints) do
		if point.Definition.Kind == kind then
			local distance = (position - getPointPosition(point)).Magnitude
			if distance < nearestDistance then
				nearestId = pointId
				nearest = point
				nearestDistance = distance
			end
		end
	end
	return nearestId, nearest, nearestDistance
end

local function isVehicleNearPlayer(player: Player, vehicle: VehicleRecord): boolean
	local _, humanoid, root = getCharacter(player)
	if humanoid == nil or root == nil then
		return false
	end
	if vehicle.Seat.Occupant == humanoid then
		return true
	end
	return VehicleRules.IsSafeInteraction((root.Position - vehicle.Chassis.Position).Magnitude, config.InteractionRange, true)
end

function LogisticsService.IsAuthorizedDriver(player: Player, vehicle: VehicleRecord): boolean
	local session = PlayerDataService.GetSession(player)
	return session ~= nil and vehicle.Definition.AllowedDriverRoles[session.Role] == true
end

local function takeRequestToken(player: Player): boolean
	local now = os.clock()
	local bucket = requestBuckets[player]
	if bucket == nil or now - bucket.WindowStartedAt >= INTERACTION_WINDOW_SECONDS then
		requestBuckets[player] = { WindowStartedAt = now, Count = 1 }
		return true
	end
	if bucket.Count >= MAX_INTERACTIONS_PER_WINDOW then
		return false
	end
	bucket.Count += 1
	return true
end

local function getVehicleSnapshot(vehicle: VehicleRecord, player: Player?)
	local character = if player ~= nil then player.Character else nil
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	return {
		id = vehicle.Id,
		name = vehicle.Definition.DisplayName,
		fuel = vehicle.Fuel,
		fuelCapacity = vehicle.Definition.FuelCapacity,
		speed = vehicle.Speed,
		cargo = table.clone(vehicle.Cargo),
		cargoCapacity = vehicle.Definition.CargoCapacity,
		occupied = vehicle.Seat.Occupant ~= nil,
		isDriver = humanoid ~= nil and vehicle.Seat.Occupant == humanoid,
	}
end

local function getPointSnapshot(pointId: string, point: SupplyPoint)
	return {
		id = pointId,
		name = point.Definition.Name,
		kind = point.Definition.Kind,
		stock = table.clone(point.Stock),
	}
end

local function makeStatus(player: Player)
	local _, humanoid, root = getCharacter(player)
	if humanoid == nil or root == nil then
		return { action = "logistics_status", ok = false, code = "player_unavailable" }
	end
	local vehicleSnapshots = {}
	local nearestVehicleDistance = math.huge
	local nearestVehicle: VehicleRecord? = nil
	for _, vehicle in pairs(vehicles) do
		local distance = (root.Position - vehicle.Chassis.Position).Magnitude
		if distance < nearestVehicleDistance then
			nearestVehicleDistance = distance
			nearestVehicle = vehicle
		end
		if distance <= 100 or vehicle.Seat.Occupant == humanoid then
			table.insert(vehicleSnapshots, getVehicleSnapshot(vehicle, player))
		end
	end
	local nearbyPoints = {}
	for pointId, point in pairs(supplyPoints) do
		if (root.Position - getPointPosition(point)).Magnitude <= 100 then
			table.insert(nearbyPoints, getPointSnapshot(pointId, point))
		end
	end
	local inventory = InventoryService.GetInventory(player)
	local nearestVehicleIsOccupiedByPlayer = nearestVehicle ~= nil and nearestVehicle.Seat.Occupant == humanoid
	return {
		action = "logistics_status",
		ok = true,
		vehicles = vehicleSnapshots,
		points = nearbyPoints,
		inventory = if inventory ~= nil then {
			weapons = inventory.Weapons,
			medicalItems = inventory.MedicalItems,
			supplies = inventory.Supplies,
		} else {},
		nearestVehicleId = if nearestVehicle ~= nil and nearestVehicleDistance <= config.VehicleEnterRange
			then nearestVehicle.Id
			else nil,
		isDriving = nearestVehicleIsOccupiedByPlayer,
	}
end

local function sendVehicleStatus(vehicle: VehicleRecord)
	local occupant = vehicle.Seat.Occupant
	if occupant == nil or occupant.Parent == nil then
		return
	end
	local player = Players:GetPlayerFromCharacter(occupant.Parent)
	if player ~= nil then
		requestRemote:FireClient(player, {
			action = "logistics_vehicle_status",
			ok = true,
			vehicle = getVehicleSnapshot(vehicle, player),
		})
	end
end

local function sendVehicleStatusIfDue(vehicle: VehicleRecord)
	local now = os.clock()
	if now >= vehicle.NextStatusAt then
		vehicle.NextStatusAt = now + config.VehicleStatusInterval
		sendVehicleStatus(vehicle)
	end
end

local function findHumanoidPlayer(vehicle: VehicleRecord): Player?
	local occupant = vehicle.Seat.Occupant
	local character = if occupant ~= nil then occupant.Parent else nil
	return if character ~= nil then Players:GetPlayerFromCharacter(character) else nil
end

local function processVehicleMovement(vehicle: VehicleRecord, deltaTime: number)
	local player = findHumanoidPlayer(vehicle)
	local occupant = vehicle.Seat.Occupant
	if player == nil or occupant == nil then
		vehicle.Speed = 0
		return
	end
	local character = player.Character
	if character == nil or character:GetAttribute("SierraIncapacitated") == true then
		occupant.Sit = false
		vehicle.Speed = 0
		return
	end
	local canDrive = LogisticsRules.CanDrive(vehicle.Fuel, true, LogisticsService.IsAuthorizedDriver(player, vehicle))
	if not canDrive then
		vehicle.Speed = 0
		if not LogisticsService.IsAuthorizedDriver(player, vehicle) then
			occupant.Sit = false
		end
		sendVehicleStatusIfDue(vehicle)
		return
	end
	local throttle = vehicle.Seat.ThrottleFloat
	local speed, remainingFuel = LogisticsRules.StepVehicle(
		vehicle.Fuel,
		throttle,
		vehicle.Definition.MaxSpeed,
		vehicle.Definition.ReverseSpeed,
		vehicle.Definition.FuelPerStud,
		deltaTime
	)
	local currentPivot = vehicle.Model:GetPivot()
	local turnDirection = if speed < 0 then -1 else 1
	local steering = vehicle.Seat.SteerFloat
	local turnedPivot = currentPivot * CFrame.Angles(0, -steering * vehicle.Definition.TurnRate * deltaTime * turnDirection, 0)
	local displacement = turnedPivot.LookVector * speed * deltaTime
	if displacement.Magnitude > 0 then
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = { vehicle.Model, character }
		local obstruction = Workspace:Raycast(vehicle.Chassis.Position + Vector3.new(0, 1, 0), displacement.Unit * (displacement.Magnitude + 3), rayParams)
		if obstruction == nil then
			vehicle.Model:PivotTo(turnedPivot + displacement)
			vehicle.Fuel = remainingFuel
			vehicle.Chassis:SetAttribute("Fuel", math.floor(vehicle.Fuel * 10) / 10)
		else
			speed = 0
		end
	end
	vehicle.Speed = speed
	sendVehicleStatusIfDue(vehicle)
end

local function step(deltaTime: number)
	local now = os.clock()
	for _, vehicle in pairs(vehicles) do
		processVehicleMovement(vehicle, math.min(deltaTime, 0.1))
	end
	for _, point in pairs(supplyPoints) do
		local restocked, nextRestockAt = LogisticsRules.Restock(
			point,
			now,
			point.NextRestockAt,
			point.Definition.RestockSeconds
		)
		if restocked > 0 then
			point.NextRestockAt = nextRestockAt
		end
	end
end

local function enterVehicle(player: Player, vehicle: VehicleRecord): (boolean, string)
	local character, humanoid, root = getCharacter(player)
	if character == nil or humanoid == nil or root == nil then
		return false, "player_unavailable"
	end
	if not VehicleRules.IsSafeInteraction((root.Position - vehicle.Chassis.Position).Magnitude, config.VehicleEnterRange, true) then
		return false, "out_of_range"
	end
	local allowed, code = VehicleRules.CanEnter(true, vehicle.Seat.Occupant ~= nil, LogisticsService.IsAuthorizedDriver(player, vehicle))
	if not allowed then
		return false, code
	end
	vehicle.Seat:Sit(humanoid)
	return vehicle.Seat.Occupant == humanoid, if vehicle.Seat.Occupant == humanoid then "entered_vehicle" else "seat_unavailable"
end

local function exitVehicle(player: Player, vehicle: VehicleRecord): (boolean, string)
	local _, humanoid = getCharacter(player)
	if humanoid == nil then
		return false, "player_unavailable"
	end
	local allowed, code = VehicleRules.CanExit(vehicle.Seat.Occupant == humanoid)
	if not allowed then
		return false, code
	end
	humanoid.Sit = false
	return true, "exited_vehicle"
end

local function handleLoadCargo(player: Player, request: any, vehicle: VehicleRecord): (boolean, string)
	if not isVehicleNearPlayer(player, vehicle) then
		return false, "vehicle_out_of_range"
	end
	if vehicle.Seat.Occupant ~= nil and vehicle.Seat.Occupant ~= (player.Character and player.Character:FindFirstChildOfClass("Humanoid")) then
		return false, "vehicle_occupied"
	end
	local pointId, point = getNearestPoint(vehicle.Chassis.Position, "Depot")
	if pointId == nil or point == nil or not VehicleRules.IsSafeInteraction(
		(vehicle.Chassis.Position - getPointPosition(point)).Magnitude,
		point.Definition.Radius,
		true
	) then
		return false, "depot_out_of_range"
	end
	local loaded, code = LogisticsRules.LoadCargo(
		vehicle.Cargo,
		point.Stock,
		config.Resources,
		vehicle.Definition.CargoCapacity,
		request.resourceId,
		request.amount
	)
	return loaded, code
end

local function handleDelivery(player: Player, vehicle: VehicleRecord): (boolean, string)
	if not isVehicleNearPlayer(player, vehicle) then
		return false, "vehicle_out_of_range"
	end
	local _, point = getNearestPoint(vehicle.Chassis.Position, "Delivery")
	if point == nil or not VehicleRules.IsSafeInteraction(
		(vehicle.Chassis.Position - getPointPosition(point)).Magnitude,
		point.Definition.Radius,
		true
	) then
		return false, "delivery_out_of_range"
	end
	local previousStock = table.clone(point.Stock)
	local delivered, code =
		LogisticsRules.DeliverCargo(vehicle.Cargo, point.Stock, point.MaxStock, config.Resources, nil, nil)
	if delivered then
		local totals = deliveryTotals[point.Definition.Id]
		if totals == nil then
			totals = {}
			deliveryTotals[point.Definition.Id] = totals
		end
		for resourceId, stock in pairs(point.Stock) do
			local acceptedAmount = stock - (previousStock[resourceId] or 0)
			if acceptedAmount > 0 then
				totals[resourceId] = (totals[resourceId] or 0) + acceptedAmount
			end
		end
	end
	return delivered, code
end

local function handleResupply(player: Player, request: any, point: SupplyPoint): (boolean, string)
	if point.Definition.Kind ~= "Depot" then
		return false, "not_a_depot"
	end
	local _, _, root = getCharacter(player)
	if root == nil or not VehicleRules.IsSafeInteraction(
		(root.Position - getPointPosition(point)).Magnitude,
		point.Definition.Radius,
		true
	) then
		return false, "depot_out_of_range"
	end
	if not InventoryService.CanApplyLogisticsSupply(player, request.resourceId, request.amount) then
		return false, "inventory_capacity_full"
	end
	local available = point.Stock[request.resourceId]
	if available == nil or available <= 0 then
		return false, "insufficient_stock"
	end
	local requestedAmount = math.min(request.amount, available)
	local supplied, code = InventoryService.ApplyLogisticsSupply(player, request.resourceId, requestedAmount)
	if supplied <= 0 then
		return false, code
	end
	local consumed, stockCode = LogisticsRules.TakeStock(point.Stock, request.resourceId, supplied)
	if not consumed then
		return false, stockCode
	end
	return true, "resupplied"
end

local function handleRefuel(player: Player, request: any, vehicle: VehicleRecord, point: SupplyPoint): (boolean, string)
	if point.Definition.Kind ~= "Depot" then
		return false, "not_a_depot"
	end
	if not isVehicleNearPlayer(player, vehicle) then
		return false, "vehicle_out_of_range"
	end
	if not VehicleRules.IsSafeInteraction(
		(vehicle.Chassis.Position - getPointPosition(point)).Magnitude,
		point.Definition.Radius,
		true
	) then
		return false, "depot_out_of_range"
	end
	local fuel, used, code = LogisticsRules.Refuel(
		vehicle.Fuel,
		vehicle.Definition.FuelCapacity,
		point.Stock,
		config.Resupply.FuelPerUnit
	)
	if used <= 0 then
		return false, code
	end
	vehicle.Fuel = fuel
	vehicle.Chassis:SetAttribute("Fuel", math.floor(fuel * 10) / 10)
	return true, "refueled"
end

function LogisticsService.HandleRequest(player: Player, request: any): { [string]: any }
	if player.Parent ~= Players then
		return { action = "logistics_result", ok = false, code = "invalid_player" }
	end
	if not takeRequestToken(player) then
		return { action = "logistics_result", ok = false, code = "rate_limited" }
	end
	if type(request) ~= "table" then
		return { action = "logistics_result", ok = false, code = "invalid_request" }
	end
	if request.operation == "status" then
		return makeStatus(player)
	end
	if request.operation == "exit_vehicle" then
		local vehicle = getVehicle(request)
		if vehicle == nil then
			return { action = "logistics_result", ok = false, code = "invalid_vehicle" }
		end
		local ok, code = exitVehicle(player, vehicle)
		return { action = "logistics_result", ok = ok, code = code, vehicle = getVehicleSnapshot(vehicle, player) }
	end
	if request.operation == "enter_vehicle" then
		local vehicle = getVehicle(request)
		if vehicle == nil then
			return { action = "logistics_result", ok = false, code = "invalid_vehicle" }
		end
		local ok, code = enterVehicle(player, vehicle)
		return { action = "logistics_result", ok = ok, code = code, vehicle = getVehicleSnapshot(vehicle, player) }
	end
	if request.operation == "load_cargo" then
		local vehicle = getVehicle(request)
		if vehicle == nil then
			return { action = "logistics_result", ok = false, code = "invalid_vehicle" }
		end
		local ok, code = handleLoadCargo(player, request, vehicle)
		return { action = "logistics_result", ok = ok, code = code, vehicle = getVehicleSnapshot(vehicle, player) }
	end
	if request.operation == "deliver_cargo" then
		local vehicle = getVehicle(request)
		if vehicle == nil then
			return { action = "logistics_result", ok = false, code = "invalid_vehicle" }
		end
		local ok, code = handleDelivery(player, vehicle)
		return { action = "logistics_result", ok = ok, code = code, vehicle = getVehicleSnapshot(vehicle, player) }
	end
	if request.operation == "resupply" then
		local point = getPoint(request)
		if point == nil then
			return { action = "logistics_result", ok = false, code = "invalid_point" }
		end
		local ok, code = handleResupply(player, request, point)
		return { action = "logistics_result", ok = ok, code = code, point = getPointSnapshot(request.pointId, point) }
	end
	if request.operation == "refuel" then
		local vehicle = getVehicle(request)
		local point = getPoint(request)
		if vehicle == nil or point == nil then
			return { action = "logistics_result", ok = false, code = "invalid_vehicle_or_point" }
		end
		local ok, code = handleRefuel(player, request, vehicle, point)
		return {
			action = "logistics_result",
			ok = ok,
			code = code,
			vehicle = getVehicleSnapshot(vehicle, player),
			point = getPointSnapshot(request.pointId, point),
		}
	end
	return { action = "logistics_result", ok = false, code = "invalid_operation" }
end

function LogisticsService.GetDeliveredAmount(pointId: string, resourceId: string): number
	if type(pointId) ~= "string" or type(resourceId) ~= "string" then
		return 0
	end
	return deliveryTotals[pointId] and deliveryTotals[pointId][resourceId] or 0
end

function LogisticsService.ConsumeDeliveredStock(pointId: string, resourceId: string, amount: number): boolean
	local point = supplyPoints[pointId]
	if point == nil
		or point.Definition.Kind ~= "Delivery"
		or type(resourceId) ~= "string"
		or type(amount) ~= "number"
		or amount <= 0
		or amount % 1 ~= 0
	then
		return false
	end
	local current = point.Stock[resourceId]
	if current == nil or current < amount then
		return false
	end
	point.Stock[resourceId] = current - amount
	return true
end

function LogisticsService.Start()
	if isStarted then
		return
	end
	if not LogisticsRules.ValidateConfig(config) then
		error("LogisticsService: invalid LogisticsConfig")
	end
	isStarted = true
	local existing = Workspace:FindFirstChild(WORLD_FOLDER_NAME)
	if existing ~= nil then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = WORLD_FOLDER_NAME
	folder.Parent = Workspace
	worldFolder = folder

	for _, definition in ipairs(config.SupplyPoints) do
		local point: SupplyPoint = {
			Definition = definition,
			Stock = table.clone(definition.Stock),
			MaxStock = table.clone(definition.MaxStock),
			RestockAmount = table.clone(definition.RestockAmount),
			NextRestockAt = os.clock() + definition.RestockSeconds,
			Part = nil,
		}
		supplyPoints[definition.Id] = point
		createSupplyMarker(definition.Id, point, folder)
	end
	for _, vehicleDefinition in pairs(config.Vehicles) do
		for _, spawn in ipairs(vehicleDefinition.Spawns) do
			if vehicles[spawn.Id] ~= nil then
				error(`LogisticsService: duplicate vehicle id {spawn.Id}`)
			end
			vehicles[spawn.Id] = createVehicle(spawn.Id, vehicleDefinition, spawn, folder)
		end
	end
	table.insert(connections, RunService.Heartbeat:Connect(step))
	table.insert(connections, Players.PlayerRemoving:Connect(function(player)
		requestBuckets[player] = nil
	end))
end

function LogisticsService.Stop()
	if not isStarted then
		return
	end
	isStarted = false
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(requestBuckets)
	table.clear(deliveryTotals)
	table.clear(vehicles)
	table.clear(supplyPoints)
	if worldFolder ~= nil then
		worldFolder:Destroy()
		worldFolder = nil
	end
end

return table.freeze(LogisticsService)
