--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local logisticsRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CombatRequest") :: RemoteEvent
local playerGui = player:WaitForChild("PlayerGui")
local vehicleId = "Ranger1"
local depotId = "SierraDepot"
local isDriving = false

local screen = Instance.new("ScreenGui")
screen.Name = "SierraLogistics"
screen.ResetOnSpawn = false
screen.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "LogisticsPanel"
panel.AnchorPoint = Vector2.new(1, 1)
panel.Position = UDim2.new(1, -12, 1, -12)
panel.Size = UDim2.new(0.94, 0, 0, 252)
panel.BackgroundColor3 = Color3.fromRGB(22, 29, 31)
panel.BackgroundTransparency = 0.12
panel.BorderSizePixel = 0
panel.Parent = screen
local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MinSize = Vector2.new(280, 252)
sizeLimit.MaxSize = Vector2.new(360, 252)
sizeLimit.Parent = panel
local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 8)
panelCorner.Parent = panel

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "Status"
statusLabel.Position = UDim2.new(0, 10, 0, 8)
statusLabel.Size = UDim2.new(1, -20, 0, 70)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.GothamMedium
statusLabel.TextColor3 = Color3.fromRGB(240, 240, 230)
statusLabel.TextSize = 13
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextYAlignment = Enum.TextYAlignment.Top
statusLabel.TextWrapped = true
statusLabel.Text = "Logistica: consultando suministros..."
statusLabel.Parent = panel

local function request(operation: string, fields: { [string]: any }?)
	local payload: { [string]: any } = {
		action = "logistics",
		operation = operation,
	}
	for key, value in pairs(fields or {}) do
		payload[key] = value
	end
	logisticsRemote:FireServer(payload)
end

local function createButton(name: string, title: string, column: number, row: number, callback: () -> ())
	local button = Instance.new("TextButton")
	button.Name = name
	button.Position = UDim2.new(0, 10 + column * 96, 0, 82 + row * 52)
	button.Size = UDim2.new(0, 90, 0, 44)
	button.BackgroundColor3 = Color3.fromRGB(57, 77, 70)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamSemibold
	button.Text = title
	button.TextColor3 = Color3.fromRGB(255, 255, 245)
	button.TextSize = 12
	button.TextWrapped = true
	button.Parent = panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button
	button.Activated:Connect(callback)
end

local function selectedVehicleId(): string
	return vehicleId
end

createButton("Vehicle", "Entrar / salir", 0, 0, function()
	request(if isDriving then "exit_vehicle" else "enter_vehicle", { vehicleId = selectedVehicleId() })
end)
createButton("Refuel", "Repostar", 1, 0, function()
	request("refuel", { vehicleId = selectedVehicleId(), pointId = depotId })
end)
createButton("LoadAmmo", "Cargar municion", 2, 0, function()
	request("load_cargo", { vehicleId = selectedVehicleId(), resourceId = "Ammo", amount = 1 })
end)
createButton("LoadMedical", "Cargar medicina", 0, 1, function()
	request("load_cargo", { vehicleId = selectedVehicleId(), resourceId = "Medical", amount = 1 })
end)
createButton("Deliver", "Entregar carga", 1, 1, function()
	request("deliver_cargo", { vehicleId = selectedVehicleId() })
end)
createButton("ResupplyAmmo", "Reponer municion", 2, 1, function()
	request("resupply", { pointId = depotId, resourceId = "Ammo", amount = 1 })
end)
createButton("ResupplyMedical", "Reponer medicina", 0, 2, function()
	request("resupply", { pointId = depotId, resourceId = "Medical", amount = 1 })
end)
createButton("ResupplyRations", "Reponer raciones", 1, 2, function()
	request("resupply", { pointId = depotId, resourceId = "Rations", amount = 1 })
end)
createButton("Refresh", "Actualizar", 2, 2, function()
	request("status")
end)

local function bindKey(actionName: string, operation: string, key: Enum.KeyCode, fields: { [string]: any }?)
	ContextActionService:BindAction(actionName, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			if operation == "toggle_vehicle" then
				request(if isDriving then "exit_vehicle" else "enter_vehicle", { vehicleId = selectedVehicleId() })
			else
				local requestFields = table.clone(fields or {})
				if requestFields.vehicleId ~= nil then
					requestFields.vehicleId = selectedVehicleId()
				end
				request(operation, requestFields)
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, key)
end

bindKey("SierraVehicleToggle", "toggle_vehicle", Enum.KeyCode.B)
bindKey("SierraLoadCargo", "load_cargo", Enum.KeyCode.L, {
	vehicleId = selectedVehicleId(),
	resourceId = "Ammo",
	amount = 1,
})
bindKey("SierraDeliverCargo", "deliver_cargo", Enum.KeyCode.V, { vehicleId = selectedVehicleId() })
bindKey("SierraResupply", "resupply", Enum.KeyCode.T, {
	pointId = depotId,
	resourceId = "Ammo",
	amount = 1,
})
bindKey("SierraRefuel", "refuel", Enum.KeyCode.F, {
	vehicleId = selectedVehicleId(),
	pointId = depotId,
})

logisticsRemote.OnClientEvent:Connect(function(message: any)
	if type(message) ~= "table" then
		return
	end
	if message.action == "logistics_status" and message.ok then
		if type(message.nearestVehicleId) == "string" then
			vehicleId = message.nearestVehicleId
		end
		isDriving = message.isDriving == true
		local vehicle = nil
		if type(message.vehicles) == "table" then
			for _, candidate in ipairs(message.vehicles) do
				if candidate.id == vehicleId then
					vehicle = candidate
					break
				end
			end
		end
		local point = if type(message.points) == "table" then message.points[1] else nil
		if vehicle ~= nil then
			statusLabel.Text = string.format(
				"%s | Combustible: %d/%d | Velocidad: %d\nCarga: MUN %d / MED %d / RACIONES %d / COMB %d | %d/%d",
				vehicle.name or vehicle.id,
				math.floor(vehicle.fuel or 0),
				math.floor(vehicle.fuelCapacity or 0),
				math.floor(math.abs(vehicle.speed or 0)),
				vehicle.cargo.Ammo or 0,
				vehicle.cargo.Medical or 0,
				vehicle.cargo.Rations or 0,
				vehicle.cargo.Fuel or 0,
				(vehicle.cargo.Ammo or 0) + (vehicle.cargo.Medical or 0)
					+ (vehicle.cargo.Rations or 0) + (vehicle.cargo.Fuel or 0),
				vehicle.cargoCapacity or 0
			)
		elseif point ~= nil then
			statusLabel.Text = string.format(
				"%s | Stock municion %d, medicina %d, raciones %d, combustible %d",
				point.name or point.id,
				point.stock.Ammo or 0,
				point.stock.Medical or 0,
				point.stock.Rations or 0,
				point.stock.Fuel or 0
			)
		else
			statusLabel.Text = "Acercate a un vehiculo o deposito para ver el estado logistico."
		end
	elseif message.action == "logistics_vehicle_status" and message.ok then
		local vehicle = message.vehicle
		if vehicle ~= nil then
			isDriving = vehicle.isDriver == true
			statusLabel.Text = string.format(
				"%s | Combustible: %d/%d | Velocidad: %d\nCarga MUN %d MED %d RACIONES %d COMB %d",
				vehicle.name or vehicle.id,
				math.floor(vehicle.fuel or 0),
				math.floor(vehicle.fuelCapacity or 0),
				math.floor(math.abs(vehicle.speed or 0)),
				vehicle.cargo.Ammo or 0,
				vehicle.cargo.Medical or 0,
				vehicle.cargo.Rations or 0,
				vehicle.cargo.Fuel or 0
			)
		end
	elseif message.action == "logistics_result" then
		if message.vehicle ~= nil then
			local vehicle = message.vehicle
			isDriving = vehicle.isDriver == true
			vehicleId = vehicle.id or vehicleId
			statusLabel.Text = string.format(
				"%s: %s | Combustible %d/%d",
				vehicle.name or vehicle.id or "Vehiculo",
				message.code or "sin estado",
				math.floor(vehicle.fuel or 0),
				math.floor(vehicle.fuelCapacity or 0)
			)
		else
			statusLabel.Text = `Logistica: {message.code or "respuesta recibida"}`
		end
	end
end)

player.CharacterAdded:Connect(function()
	task.delay(1, function()
		request("status")
	end)
end)
task.delay(1, function()
	request("status")
end)
task.spawn(function()
	while screen.Parent ~= nil do
		task.wait(5)
		request("status")
	end
end)
