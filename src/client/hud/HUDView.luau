--!strict
local Rules = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("HUDRules"))
local HUDView = {}
HUDView.__index = HUDView
local COLOR = {
	Panel = Color3.fromRGB(19, 26, 29),
	Text = Color3.fromRGB(243, 240, 226),
	Accent = Color3.fromRGB(185, 205, 145),
	Muted = Color3.fromRGB(167, 181, 180),
}
local function frame(parent: Instance, name: string): Frame
	local item = Instance.new("Frame")
	item.Name, item.BackgroundColor3, item.BackgroundTransparency = name, COLOR.Panel, 0.18
	item.BorderSizePixel, item.Parent = 0, parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius, corner.Parent = UDim.new(0, 9), item
	return item
end
local function label(parent: Instance, name: string, text: string, y: number, height: number): TextLabel
	local item = Instance.new("TextLabel")
	item.Name, item.BackgroundTransparency = name, 1
	item.Position, item.Size = UDim2.fromOffset(8, y), UDim2.new(1, -16, 0, height)
	item.Font, item.TextSize, item.TextColor3 = Enum.Font.GothamMedium, 14, COLOR.Text
	item.Text, item.TextXAlignment, item.TextWrapped = text, Enum.TextXAlignment.Left, true
	item.Parent = parent
	return item
end
local function button(parent: Instance, name: string, text: string, width: number?): TextButton
	local item = Instance.new("TextButton")
	item.Name, item.Text = name, text
	item.Size = UDim2.fromOffset(width or 64, 48)
	item.Font, item.TextSize, item.TextColor3 = Enum.Font.GothamBold, 14, COLOR.Text
	item.BackgroundColor3, item.BackgroundTransparency, item.BorderSizePixel = COLOR.Panel, 0.12, 0
	item.TextWrapped, item.Parent = true, parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius, corner.Parent = UDim.new(0, 9), item
	return item
end

function HUDView.new(parent: Instance, mapConfig: any, logisticsConfig: any)
	local self: any = setmetatable(
		{ MapConfig = mapConfig, LogisticsConfig = logisticsConfig, Lines = {}, Markers = {}, Profile = nil },
		HUDView
	)
	self.Root = Instance.new("Frame")
	self.Root.Name, self.Root.Size, self.Root.BackgroundTransparency, self.Root.Parent =
		"DrivingHUD", UDim2.fromScale(1, 1), 1, parent
	self.Status = frame(self.Root, "PlayerStatus")
	self.Status.AnchorPoint = Vector2.new(1, 0)
	self.Status.Position = UDim2.new(1, -12, 0, 8)
	self.Health = label(self.Status, "Health", "SALUD --", 4, 24)
	self.Condition = label(self.Status, "Condition", "Sincronizando", 29, 20)
	self.Ammo = label(self.Status, "Ammo", "MUNICION --", 51, 30)
	self.HealthBar = frame(self.Status, "HealthBar")
	self.HealthBar.Position, self.HealthBar.Size, self.HealthBar.BackgroundColor3 =
		UDim2.new(0, 8, 1, -7), UDim2.new(1, -16, 0, 3), COLOR.Accent
	self.Compass = frame(self.Root, "Compass")
	self.Compass.AnchorPoint = Vector2.new(0.5, 0)
	self.Compass.Position, self.Compass.Size = UDim2.new(0.5, 0, 0, 8), UDim2.fromOffset(200, 60)
	self.Heading = label(self.Compass, "Heading", "N 000°", 0, 26)
	self.Heading.TextXAlignment = Enum.TextXAlignment.Center
	self.Location = label(self.Compass, "Location", "Roblox-Fes", 27, 28)
	self.Location.TextXAlignment, self.Location.TextSize = Enum.TextXAlignment.Center, 12
	self.Map = frame(self.Root, "Minimap")
	self.Map.ClipsDescendants = true
	self.Map:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0.5, 0)
	self.North = label(self.Map, "North", "N", 2, 16)
	self.North.TextXAlignment, self.North.TextColor3, self.North.ZIndex = Enum.TextXAlignment.Center, COLOR.Accent, 4
	self.Arrow = label(self.Map, "Player", "▲", 0, 24)
	self.Arrow.AnchorPoint, self.Arrow.Size, self.Arrow.Position =
		Vector2.new(0.5, 0.5), UDim2.fromOffset(24, 24), UDim2.fromScale(0.5, 0.5)
	self.Arrow.TextColor3, self.Arrow.TextSize, self.Arrow.TextXAlignment, self.Arrow.ZIndex =
		COLOR.Accent, 22, Enum.TextXAlignment.Center, 5
	-- Subdivide real configured roads so circular clipping does not erase long segments.
	for _, road in ipairs(mapConfig.Roads) do
		for index = 2, #road.Points do
			local a, b = road.Points[index - 1], road.Points[index]
			local count = math.max(1, math.ceil(math.sqrt((b.X - a.X) ^ 2 + (b.Z - a.Z) ^ 2) / 10))
			for step = 1, count do
				local t0, t1 = (step - 1) / count, step / count
				local part = Instance.new("Frame")
				part.Name, part.BorderSizePixel, part.BackgroundColor3, part.AnchorPoint =
					road.Id, 0, Color3.fromRGB(108, 118, 109), Vector2.new(0.5, 0.5)
				part.Parent = self.Map
				table.insert(self.Lines, {
					UI = part,
					X1 = a.X + (b.X - a.X) * t0,
					Z1 = a.Z + (b.Z - a.Z) * t0,
					X2 = a.X + (b.X - a.X) * t1,
					Z2 = a.Z + (b.Z - a.Z) * t1,
					Width = road.Width,
				})
			end
		end
	end
	for _, point in ipairs(logisticsConfig.SupplyPoints) do
		local marker = label(self.Map, point.Id, if point.Kind == "Depot" then "D" else "L", 0, 18)
		marker.Size, marker.AnchorPoint, marker.ZIndex, marker.TextXAlignment =
			UDim2.fromOffset(18, 18), Vector2.new(0.5, 0.5), 3, Enum.TextXAlignment.Center
		table.insert(self.Markers, { UI = marker, X = point.X, Z = point.Z })
	end
	self.Nav = frame(self.Root, "Navigation")
	self.Nav.BackgroundTransparency, self.Nav.Size = 1, UDim2.fromOffset(208, 48)
	self.NavButtons = {}
	for index, item in ipairs({ { "radio", "Radio" }, { "mission", "Mision" }, { "logistics", "Carga" } }) do
		local control = button(self.Nav, item[1], item[2])
		control.Position = UDim2.fromOffset((index - 1) * 72, 0)
		self.NavButtons[item[1]] = control
	end
	self.Chat = button(self.Root, "Chat", "Chat", 60)
	self.Hotbar = frame(self.Root, "QuickInventory")
	self.Hotbar.BackgroundTransparency, self.Hotbar.AnchorPoint, self.Hotbar.Position, self.Hotbar.Size =
		1, Vector2.new(1, 0), UDim2.new(1, -12, 0, 108), UDim2.fromOffset(250, 48)
	self.Weapons = {}
	for index, entry in ipairs({ { "Rifle", "1  Fusil" }, { "Sidearm", "2  Pistola" } }) do
		local control = button(self.Hotbar, entry[1], entry[2], 121)
		control.Position = UDim2.fromOffset((index - 1) * 129, 0)
		self.Weapons[entry[1]] = control
	end
	self.Vehicle = frame(self.Root, "VehicleTelemetry")
	self.Vehicle.AnchorPoint, self.Vehicle.Position = Vector2.new(1, 0), UDim2.new(1, -12, 0, 108)
	self.VehicleName = label(self.Vehicle, "Name", "Ranger", 4, 22)
	self.Speed = label(self.Vehicle, "Speed", "-- studs/s", 28, 27)
	self.Fuel = label(self.Vehicle, "Fuel", "Combustible --", 57, 22)
	self.Drive = Instance.new("Frame")
	self.Drive.Name, self.Drive.Size, self.Drive.BackgroundTransparency, self.Drive.Parent =
		"VehicleActions", UDim2.fromScale(1, 1), 1, self.Root
	self.DriveButtons = {}
	for _, name in ipairs({ "Forward", "Reverse", "Left", "Right", "Brake" }) do
		local captions = { Forward = "Acelerar", Reverse = "Reversa", Left = "◀", Right = "▶", Brake = "Freno" }
		local control = button(self.Drive, name, captions[name], 64)
		control.Size = UDim2.fromOffset(64, 56)
		self.DriveButtons[name] = control
	end
	self.DriveButtons.Left.Position = UDim2.new(0, 16, 1, -100)
	self.DriveButtons.Right.Position = UDim2.new(0, 88, 1, -100)
	self.DriveButtons.Forward.Position = UDim2.new(1, -80, 1, -148)
	self.DriveButtons.Reverse.Position = UDim2.new(1, -80, 1, -84)
	self.DriveButtons.Brake.Position = UDim2.new(1, -152, 1, -84)
	self.Exit, self.Camera =
		button(self.Root, "ExitVehicle", "Salir", 64), button(self.Root, "VehicleCamera", "Camara", 64)
	self.Exit.Position, self.Camera.Position = UDim2.new(1, -224, 1, -148), UDim2.new(1, -224, 1, -84)
	self.Notice = label(self.Root, "Notice", "", 0, 40)
	self.Notice.AnchorPoint, self.Notice.Position, self.Notice.Size =
		Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -12), UDim2.new(0.5, 0, 0, 40)
	return self
end

function HUDView:Layout(width: number, height: number, touch: boolean)
	local p = Rules.Profile(width, height)
	self.Profile, self.Touch = p, touch
	self.Status.Size, self.Vehicle.Size = UDim2.fromOffset(p.StatusWidth, 94), UDim2.fromOffset(p.StatusWidth, 86)
	self.Compass.Size = UDim2.fromOffset(if p.Compact then 140 else 200, 60)
	self.Map.Size = UDim2.fromOffset(p.MapSize, p.MapSize)
	self.Map.Position = UDim2.fromOffset(12, if p.Compact then 72 else 254)
	self.Nav.Position = UDim2.fromOffset(12, 254 + p.MapSize + 8)
	self.Chat.Position = UDim2.fromOffset(12, if p.Compact then 8 else 194)
	self.Compass.Position = if width < 600 then UDim2.fromOffset(82, 68) else UDim2.new(0.5, 0, 0, 8)
	if p.Compact then
		self.Vehicle.Size = UDim2.fromOffset(p.StatusWidth, 74)
		self.VehicleName.Position, self.Speed.Position, self.Fuel.Position =
			UDim2.fromOffset(8, 0), UDim2.fromOffset(8, 22), UDim2.fromOffset(8, 48)
	else
		self.VehicleName.Position, self.Speed.Position, self.Fuel.Position =
			UDim2.fromOffset(8, 4), UDim2.fromOffset(8, 28), UDim2.fromOffset(8, 57)
	end
	self.Exit.Position = if width < 480 then UDim2.new(0, 12, 1, -196) else UDim2.new(1, -224, 1, -148)
	self.Camera.Position = if width < 480 then UDim2.new(0, 84, 1, -196) else UDim2.new(1, -224, 1, -84)
	self.Nav.Visible = p.ShowNavigation
	self.Map.Visible = p.ShowMap
end

function HUDView:Render(state: any)
	if self.Profile == nil then
		return
	end
	local menu = state.Blocked
	local driving = state.Mode == "driving"
	local medical = state.Medical
	self.Status.Size = UDim2.fromOffset(self.Profile.StatusWidth, if driving and self.Profile.Compact then 60 else 94)
	self.Vehicle.Position = UDim2.new(1, -12, 0, if driving and self.Profile.Compact then 76 else 108)
	self.Ammo.Visible = not (driving and self.Profile.Compact)
	self.Health.Text = if state.Health ~= nil
		then string.format("SALUD %d / %d", state.Health, state.MaxHealth)
		else "SALUD --"
	local healthFraction = if state.MaxHealth ~= nil and state.MaxHealth > 0
		then math.clamp(state.Health / state.MaxHealth, 0, 1)
		else 0
	self.HealthBar.Size = UDim2.new(healthFraction, -16 * healthFraction, 0, 3)
	self.Condition.Text = if state.Mode == "unavailable"
		then "Sin personaje activo"
		elseif state.Mode == "incapacitated" then "INCAPACITADO"
		elseif medical == nil then "Sincronizando estado"
		elseif (medical.bleedRate or 0) > 0 then "Sangrado activo"
		elseif (medical.wounds or 0) > 0 then "Heridas activas"
		elseif state.Health < state.MaxHealth then "Herido"
		else "Operativo"
	local weaponId = if medical ~= nil then medical.equippedWeaponId else nil
	local weapon = if medical ~= nil and type(medical.weapons) == "table" then medical.weapons[weaponId] else nil
	self.Ammo.Text = if weapon ~= nil
		then string.format(
			"%s  %d / %d%s",
			weapon.name or weaponId,
			weapon.magazine,
			weapon.reserve,
			if weapon.isReloading then " · Recargando" else ""
		)
		else "MUNICION --"
	self.Hotbar.Visible = self.Profile.ShowHotbar and not driving and not menu
	for id, control in pairs(self.Weapons) do
		local owned = medical ~= nil and type(medical.weapons) == "table" and medical.weapons[id] ~= nil
		control.Visible = owned
		control.Interactable = owned and state.Mode == "walking" and (weapon == nil or not weapon.isReloading)
		control.BackgroundColor3 = if weaponId == id then Color3.fromRGB(51, 77, 66) else COLOR.Panel
	end
	self.Vehicle.Visible, self.Drive.Visible = driving and not menu, driving and not menu and self.Touch
	self.Exit.Visible, self.Camera.Visible = driving and not menu, driving and not menu
	self.Camera.Text = if self.FirstPerson then "Exterior" else "Cabina" -- native first-person, no scripted camera takeover
	if driving then
		local vehicle = state.Vehicle
		self.VehicleName.Text = if vehicle ~= nil then vehicle.name else state.VehicleId
		self.Speed.Text = if vehicle ~= nil
			then string.format("%s%.0f studs/s", if vehicle.speed < 0 then "R  " else "", math.abs(vehicle.speed))
			else "Velocidad --"
		self.Fuel.Text = if vehicle ~= nil
			then string.format("Combustible %.1f / %.0f", vehicle.fuel, vehicle.fuelCapacity)
			else "Combustible --"
	end
	local root = state.Root
	if root ~= nil and root:IsA("BasePart") then
		local subject = if driving and state.Seat ~= nil then state.Seat else root
		local position, look = subject.Position, subject.CFrame.LookVector
		local heading = Rules.Heading(look.X, look.Z)
		self.Heading.Text = string.format("%s   %03d°", Rules.Cardinal(heading), math.floor(heading + 0.5) % 360)
		local town = self.MapConfig.Town
		local inTown = (position.X - town.Center.X) ^ 2 + (position.Z - town.Center.Z) ^ 2 <= town.Radius ^ 2
		self.Location.Text = if inTown then town.Name else "Valle · Roblox-Fes"
		self.Arrow.Rotation = heading
		local size, range = self.Profile.MapSize, 220
		for _, line in ipairs(self.Lines) do
			local x1, y1 = Rules.Project(line.X1, line.Z1, position.X, position.Z, range, size)
			local x2, y2 = Rules.Project(line.X2, line.Z2, position.X, position.Z, range, size)
			local x, y = (x1 + x2) / 2, (y1 + y2) / 2
			line.UI.Visible = (x - size / 2) ^ 2 + (y - size / 2) ^ 2 < (size / 2 - 8) ^ 2
			if line.UI.Visible then
				line.UI.Position = UDim2.fromOffset(x, y)
				line.UI.Size = UDim2.fromOffset(
					math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2) + 1,
					math.max(2, line.Width * size / (2 * range))
				)
				line.UI.Rotation = math.deg(math.atan2(y2 - y1, x2 - x1))
			end
		end
		for _, marker in ipairs(self.Markers) do
			local x, y = Rules.Project(marker.X, marker.Z, position.X, position.Z, range, size)
			marker.UI.Position = UDim2.fromOffset(x, y)
			marker.UI.Visible = (x - size / 2) ^ 2 + (y - size / 2) ^ 2 < (size / 2 - 14) ^ 2
		end
	end
	self.Map.Visible = self.Profile.ShowMap
		and root ~= nil
		and not menu
		and not (self.Profile.Compact and self.ChatExpanded)
	self.Compass.Visible = root ~= nil and not menu
	self.Status.Visible = not menu
	self.Nav.Visible = self.Profile.ShowNavigation and not menu
end

function HUDView:Destroy()
	self.Root:Destroy()
end
return HUDView
