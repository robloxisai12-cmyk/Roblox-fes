--!strict
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Cleanup = require(script.Parent:WaitForChild("hud"):WaitForChild("Cleanup"))
local scope = Cleanup.new()
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CombatRequest") :: RemoteEvent
local nearestId: string? = nil
local depotId: string? = nil
local vehicles: { [string]: any } = {}
local feedback = ""

local screen = Instance.new("ScreenGui")
screen.Name, screen.ResetOnSpawn, screen.Parent = "SierraLogistics", false, playerGui
local panel = Instance.new("Frame")
panel.Name, panel.AnchorPoint = "LogisticsPanel", Vector2.new(0.5, 0.5)
panel.Position, panel.Size = UDim2.fromScale(0.5, 0.5), UDim2.new(0.94, 0, 0, 272)
panel.BackgroundColor3, panel.BackgroundTransparency, panel.BorderSizePixel = Color3.fromRGB(22, 29, 31), 0.12, 0
panel.Parent = screen
local limit = Instance.new("UISizeConstraint")
limit.MaxSize, limit.Parent = Vector2.new(380, 272), panel
local corner = Instance.new("UICorner")
corner.CornerRadius, corner.Parent = UDim.new(0, 8), panel
local status = Instance.new("TextLabel")
status.Name, status.Position, status.Size = "Status", UDim2.fromOffset(10, 8), UDim2.new(1, -20, 0, 96)
status.BackgroundTransparency, status.Font, status.TextSize = 1, Enum.Font.GothamMedium, 13
status.TextColor3, status.TextXAlignment, status.TextYAlignment, status.TextWrapped =
	Color3.fromRGB(240, 240, 230), Enum.TextXAlignment.Left, Enum.TextYAlignment.Top, true
status.Text, status.Parent = "Sincronizando logistica...", panel

local function currentVehicle(): (string?, boolean)
	local character = player.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	local seat = if humanoid ~= nil then humanoid.SeatPart else nil
	if seat ~= nil and seat:IsA("VehicleSeat") and seat.Occupant == humanoid and seat.Parent ~= nil then
		local id = seat.Parent:GetAttribute("VehicleId")
		if type(id) == "string" then
			return id, true
		end
	end
	return nearestId, false
end
local function available(): boolean
	local character = player.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	return humanoid ~= nil
		and humanoid.Health > 0
		and character ~= nil
		and character:GetAttribute("SierraIncapacitated") ~= true
end
local function render()
	local id, driving = currentVehicle()
	local vehicle = if id ~= nil then vehicles[id] else nil
	if vehicle == nil then
		local lines = {}
		for _, nearby in pairs(vehicles) do
			table.insert(
				lines,
				string.format(
					"%s · combustible %.1f/%.0f · %s",
					nearby.name,
					nearby.fuel,
					nearby.fuelCapacity,
					if nearby.canDrive then "con permiso" else "rol sin permiso"
				)
			)
		end
		table.sort(lines)
		table.insert(lines, "Acercate a un vehiculo o deposito. " .. feedback)
		status.Text = table.concat(lines, "\n")
		return
	end
	local cargo = vehicle.cargo
	status.Text = string.format(
		"%s · %s · %s\nCombustible %.1f/%.0f · %.0f studs/s\nCarga MUN %d MED %d RAC %d COMB %d\n%s",
		vehicle.name,
		if driving then "Conduciendo" else "Cercano",
		if vehicle.canDrive then "Permiso valido" else "Rol sin permiso",
		vehicle.fuel,
		vehicle.fuelCapacity,
		math.abs(vehicle.speed),
		cargo.Ammo,
		cargo.Medical,
		cargo.Rations,
		cargo.Fuel,
		feedback
	)
end
local function request(operation: string, fields: any?)
	if operation ~= "status" and not available() then
		return
	end
	local id, driving = currentVehicle()
	if operation == "toggle_vehicle" then
		operation = if driving then "exit_vehicle" else "enter_vehicle"
	end
	local payload: any = { action = "logistics", operation = operation }
	for key, value in pairs(fields or {}) do
		payload[key] = value
	end
	if
		operation == "enter_vehicle"
		or operation == "exit_vehicle"
		or operation == "load_cargo"
		or operation == "deliver_cargo"
		or operation == "refuel"
	then
		if id == nil then
			feedback = "No hay un vehiculo al alcance"
			render()
			return
		end
		payload.vehicleId = id
	end
	if operation == "refuel" or operation == "resupply" then
		if depotId == nil then
			feedback = "No hay un deposito cercano"
			render()
			return
		end
		payload.pointId = depotId
	end
	remote:FireServer(payload)
end
local items = {
	{ "Vehicle", "Entrar / salir", "toggle_vehicle" },
	{ "Refuel", "Repostar", "refuel" },
	{ "LoadAmmo", "Cargar municion", "load_cargo", { resourceId = "Ammo", amount = 1 } },
	{ "LoadMedical", "Cargar medicina", "load_cargo", { resourceId = "Medical", amount = 1 } },
	{ "Deliver", "Entregar carga", "deliver_cargo" },
	{ "ResupplyAmmo", "Reponer municion", "resupply", { resourceId = "Ammo", amount = 1 } },
	{ "ResupplyMedical", "Reponer medicina", "resupply", { resourceId = "Medical", amount = 1 } },
	{ "ResupplyRations", "Reponer raciones", "resupply", { resourceId = "Rations", amount = 1 } },
	{ "Refresh", "Actualizar", "status" },
}
for index, item in ipairs(items) do
	local button = Instance.new("TextButton")
	button.Name, button.Text = item[1], item[2]
	local column, row = (index - 1) % 3, math.floor((index - 1) / 3)
	button.Position, button.Size = UDim2.new(column / 3, 8, 0, 108 + row * 52), UDim2.new(1 / 3, -12, 0, 44)
	button.BackgroundColor3, button.TextColor3, button.Font, button.TextSize =
		Color3.fromRGB(57, 77, 70), Color3.fromRGB(255, 255, 245), Enum.Font.GothamSemibold, 12
	button.TextWrapped, button.Parent = true, panel
	scope:Connect(button.Activated, function()
		request(item[3], item[4])
	end)
end
local bindings = {
	{ "SierraVehicleToggle", "toggle_vehicle", Enum.KeyCode.B },
	{ "SierraLoadCargo", "load_cargo", Enum.KeyCode.L, { resourceId = "Ammo", amount = 1 } },
	{ "SierraDeliverCargo", "deliver_cargo", Enum.KeyCode.V },
	{ "SierraResupply", "resupply", Enum.KeyCode.T, { resourceId = "Ammo", amount = 1 } },
	{ "SierraRefuel", "refuel", Enum.KeyCode.F },
}
for _, binding in ipairs(bindings) do
	ContextActionService:BindAction(binding[1], function(_, state)
		if
			UserInputService:GetFocusedTextBox() ~= nil
			or GuiService.MenuIsOpen
			or playerGui:GetAttribute("SierraMenuOpen") == true
			or not available()
		then
			return Enum.ContextActionResult.Pass
		end
		if state == Enum.UserInputState.Begin then
			request(binding[2], binding[4])
		end
		return Enum.ContextActionResult.Sink
	end, false, binding[3])
	scope:Add(function()
		ContextActionService:UnbindAction(binding[1])
	end)
end
scope:Connect(remote.OnClientEvent, function(message)
	if type(message) ~= "table" then
		return
	end
	local token = message.character or (type(message.status) == "table" and message.status.character)
	if token ~= nil and token ~= player.Character then
		return
	end
	if message.action == "logistics_status" and message.ok and token == player.Character then
		nearestId, depotId, vehicles = message.nearestVehicleId, nil, {}
		for _, vehicle in ipairs(message.vehicles) do
			vehicles[vehicle.id] = vehicle
		end
		for _, point in ipairs(message.points) do
			if point.kind == "Depot" then
				depotId = point.id
				break
			end
		end
	elseif message.action == "logistics_result" then
		feedback = message.code or "Respuesta recibida"
	end
	if type(message.vehicle) == "table" and token == player.Character then
		vehicles[message.vehicle.id] = message.vehicle
	end
	if
		message.action == "logistics_status"
		or message.action == "logistics_result"
		or message.action == "logistics_vehicle_status"
	then
		render()
	end
end)
scope:Connect(player.CharacterAdded, function()
	nearestId, depotId, vehicles, feedback = nil, nil, {}, ""
	render()
end)
scope:Connect(screen:GetPropertyChangedSignal("Enabled"), function()
	if screen.Enabled then
		request("status")
	end
end)
scope:Connect(screen.Destroying, function()
	scope:Clean()
end)
scope:Connect(script.Destroying, function()
	scope:Clean()
	screen:Destroy()
end)
request("status")
