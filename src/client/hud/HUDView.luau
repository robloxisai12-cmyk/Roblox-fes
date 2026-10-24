--!strict
-- Open-world HUD view. It owns only instances; every number it shows comes from GameAdapter state
-- (Humanoid + server snapshots) and every rectangle comes from HUDLayout, so nothing here invents data.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local sharedRoot = ReplicatedStorage:WaitForChild("Shared")
local Rules = require(sharedRoot:WaitForChild("HUDRules"))
local HUDLayout = require(sharedRoot:WaitForChild("HUDLayout"))
local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)
local Color = Theme.Color

local HUDView = {}
HUDView.__index = HUDView

local COMPASS_FOV = 150
local MAP_RANGE = 220
local CARDINALS: { [number]: string } = { [0] = "N", [45] = "NE", [90] = "E", [135] = "SE", [180] = "S", [225] = "SO", [270] = "O", [315] = "NO" }
local ROLE_NAMES: { [string]: string } = {
	Rifleman = "Fusilero",
	Medic = "Médico",
	Engineer = "Ingeniero",
	SquadLeader = "Líder de escuadrón",
	Commander = "Comandante",
}
local NAV: { [string]: { Icon: string, Label: string } } = {
	squad = { Icon = "squad", Label = "Facciones" },
	inventory = { Icon = "backpack", Label = "Inventario" },
	logistics = { Icon = "truck", Label = "Vehículos" },
	mission = { Icon = "clipboard", Label = "Misiones" },
}
local SLOT_SPECS: { [string]: { Icon: string, Key: string? } } = {
	Rifle = { Icon = "rifle", Key = "1" },
	Sidearm = { Icon = "pistol", Key = "2" },
	Bandage = { Icon = "bandage", Key = "3" },
	Medkit = { Icon = "medkit", Key = "4" },
	Inventory = { Icon = "backpack", Key = nil },
}
local DRIVE_SPECS: { [string]: { Icon: string, Caption: string, Tint: Color3 } } = {
	Forward = { Icon = "chevronUp", Caption = "Acelerar", Tint = Color.Accent },
	Reverse = { Icon = "chevronDown", Caption = "Reversa", Tint = Color.Text },
	Left = { Icon = "chevronLeft", Caption = "Izquierda", Tint = Color.Text },
	Right = { Icon = "chevronRight", Caption = "Derecha", Tint = Color.Text },
	Brake = { Icon = "stop", Caption = "Freno", Tint = Color.Warning },
}

local function put(gui: GuiObject, r: any)
	gui.Position = UDim2.fromOffset(r.X, r.Y)
	gui.Size = UDim2.fromOffset(r.W, r.H)
end

local function at(gui: GuiObject, x: number, y: number, w: number, h: number)
	gui.Position = UDim2.fromOffset(x, y)
	gui.Size = UDim2.fromOffset(w, h)
end

local function holder(parent: Instance, name: string, kind: string, color: Color3, cut: Color3?): Frame
	local box = Instance.new("Frame")
	box.Name = name
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Parent = parent
	Icons.Draw(box, kind, color, cut or Color.Panel)
	return box
end

local function setText(label: TextLabel, text: string)
	if label.Text ~= text then
		label.Text = text
	end
end

local function strokeOf(gui: Instance): UIStroke?
	local stroke = gui:FindFirstChildOfClass("UIStroke")
	if stroke ~= nil and stroke:IsA("UIStroke") then
		return stroke
	end
	return nil
end

local function track(parent: Instance, name: string, color: Color3): (Frame, Frame)
	local back = Theme.Box(parent, name .. "Track", Color.Track)
	Theme.Round(back)
	local bar = Theme.Box(back, name .. "Bar", color)
	bar.Size = UDim2.fromScale(0, 1)
	Theme.Round(bar)
	return back, bar
end

local function toneColor(tone: string): Color3
	if tone == "ok" then
		return Color.Accent
	elseif tone == "warn" then
		return Color.Warning
	elseif tone == "danger" then
		return Color.Health
	end
	return Color.Muted
end

function HUDView.new(parent: Instance, mapConfig: any, logisticsConfig: any)
	local self: any = setmetatable({
		MapConfig = mapConfig,
		LogisticsConfig = logisticsConfig,
		Lines = {},
		Markers = {},
		Profile = nil,
		Geometry = nil,
		GeometryMode = "walking",
		GeometryChat = nil,
		Mode = "walking",
		Width = 0,
		Height = 0,
		Touch = false,
		ChatExpanded = nil,
		FirstPerson = false,
		MapKey = "",
		CompassKey = "",
		StyleKey = {},
	}, HUDView)

	local root = Instance.new("Frame")
	root.Name, root.Size, root.BackgroundTransparency, root.BorderSizePixel = "OpenWorldHUD", UDim2.fromScale(1, 1), 1, 0
	root.Parent = parent
	self.Root = root

	-- Top-left: chat + main menu -------------------------------------------------------------
	self.Chat = Theme.Button(root, "Chat")
	self.ChatIcon = holder(self.Chat, "Icon", "chat", Color.Text)
	self.MenuButton = Theme.Button(root, "MenuToggle")
	self.MenuIcon = holder(self.MenuButton, "MenuIcon", "menu", Color.Text)
	self.CloseIcon = holder(self.MenuButton, "CloseIcon", "close", Color.Accent)
	self.CloseIcon.Visible = false

	-- Left menu (regular screens) / shortcut row (phones) ----------------------------------------
	self.NavButtons = {}
	self.NavEntries = {}
	local function navEntry(id: string, icon: string, label: string)
		local button = Theme.Button(root, "Nav_" .. id)
		local entry = {
			Button = button,
			Icon = holder(button, "Icon", icon, Color.Text),
			Label = Theme.Label(button, "Label", label, 14, Color.Text, Enum.Font.GothamBold),
		}
		self.NavButtons[id] = button
		self.NavEntries[id] = entry
	end
	for _, id in ipairs(HUDLayout.MenuColumn) do
		navEntry(id, NAV[id].Icon, NAV[id].Label)
	end
	navEntry("radio", "radio", "Radio")

	-- Top-centre: compass + zone ----------------------------------------------------------------
	self.Compass = Theme.Panel(root, "Compass", 8)
	self.Compass.ClipsDescendants = true
	self.CompassMarks = {}
	for angle = 0, 345, 15 do
		local name = CARDINALS[angle]
		local mark: GuiObject
		if name ~= nil then
			local label = Theme.Label(
				self.Compass,
				"Mark" .. angle,
				name,
				if #name == 1 then 17 else 14,
				if name == "N" then Color.Accent else Color.Text,
				Enum.Font.GothamBold,
				Enum.TextXAlignment.Center
			)
			label.Size = UDim2.fromOffset(32, 26)
			mark = label
		else
			local tick = Theme.Box(self.Compass, "Tick" .. angle, Color.Muted)
			tick.Size = UDim2.fromOffset(2, 8)
			mark = tick
		end
		mark.AnchorPoint = Vector2.new(0.5, 0.5)
		table.insert(self.CompassMarks, { UI = mark, Angle = angle })
	end
	self.HeadingPill = Theme.Panel(self.Compass, "HeadingPill", 6)
	self.HeadingPill.ZIndex = 5
	self.HeadingPill.BackgroundTransparency = 0.05
	local pillStroke = strokeOf(self.HeadingPill)
	if pillStroke ~= nil then
		pillStroke.Color, pillStroke.Transparency = Color.Accent, 0.1
	end
	self.Heading = Theme.Label(self.HeadingPill, "Heading", "N 000°", 14, Color.Text, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
	self.Heading.ZIndex = 6
	self.Heading.Size = UDim2.fromScale(1, 1)

	self.Zone = Theme.Panel(root, "Zone", 8)
	self.ZoneIcon = holder(self.Zone, "Pin", "pin", Color.Accent)
	self.Location = Theme.Label(self.Zone, "Location", self.MapConfig.Name, 14, Color.Text, Enum.Font.GothamMedium)

	-- Top-right: character status ---------------------------------------------------------------
	self.Status = Theme.Panel(root, "PlayerStatus")
	self.HeartIcon = holder(self.Status, "Heart", "heart", Color.Health)
	self.HealthTrack, self.HealthBar = track(self.Status, "Health", Color.Health)
	self.Health = Theme.Label(self.Status, "Health", "-- / --", 15, Color.Text, Enum.Font.GothamBold, Enum.TextXAlignment.Right)
	self.Condition = Theme.Label(self.Status, "Condition", "SINCRONIZANDO", 12, Color.Muted, Enum.Font.GothamBold)
	self.Role = Theme.Label(self.Status, "Role", "", 12, Color.Muted, Enum.Font.GothamMedium, Enum.TextXAlignment.Right)

	-- Right: equipped weapon + quick slots --------------------------------------------------------
	self.Weapon = Theme.Panel(root, "Weapon")
	self.WeaponIcons = {
		Rifle = holder(self.Weapon, "RifleIcon", "rifle", Color.Text),
		Sidearm = holder(self.Weapon, "SidearmIcon", "pistol", Color.Text),
	}
	self.WeaponIcons.Sidearm.Visible = false
	self.WeaponName = Theme.Label(self.Weapon, "WeaponName", "ARMA", 12, Color.Muted, Enum.Font.GothamBold)
	self.AmmoState = Theme.Label(self.Weapon, "AmmoState", "", 12, Color.Warning, Enum.Font.GothamBold)
	self.Ammo = Theme.Label(self.Weapon, "Ammo", "-- / --", 24, Color.Text, Enum.Font.GothamBold, Enum.TextXAlignment.Right)

	self.Hotbar = Instance.new("Frame")
	self.Hotbar.Name, self.Hotbar.BackgroundTransparency, self.Hotbar.BorderSizePixel = "QuickInventory", 1, 0
	self.Hotbar.Parent = root
	self.Weapons, self.Items, self.Slots, self.SlotEntries = {}, {}, {}, {}
	for _, id in ipairs(HUDLayout.SlotsRegular) do
		local spec = SLOT_SPECS[id]
		local button = Theme.Button(self.Hotbar, "Slot_" .. id)
		local entry: any = { Button = button, Stroke = strokeOf(button), Icon = holder(button, "Icon", spec.Icon, Color.Text) }
		entry.Icon.Position, entry.Icon.Size = UDim2.fromOffset(22, 22), UDim2.fromOffset(26, 26)
		if spec.Key ~= nil then
			entry.Key = Theme.Label(button, "Key", spec.Key, 12, Color.Muted, Enum.Font.GothamBold)
			at(entry.Key, 5, 2, 14, 14)
		end
		if id == "Bandage" or id == "Medkit" then
			entry.Count = Theme.Label(button, "Count", "0", 12, Color.Accent, Enum.Font.GothamBold, Enum.TextXAlignment.Right)
			at(entry.Count, 18, 28, 22, 14)
			self.Items[id] = button
		elseif id == "Rifle" or id == "Sidearm" then
			self.Weapons[id] = button
		end
		self.Slots[id] = button
		self.SlotEntries[id] = entry
	end

	-- Vehicle telemetry (replaces weapon + quick slots while driving) -------------------------------
	self.Vehicle = Theme.Panel(root, "VehicleTelemetry")
	self.VehicleIcon = holder(self.Vehicle, "Truck", "truck", Color.Accent)
	self.VehicleName = Theme.Label(self.Vehicle, "Name", "Ranger", 14, Color.Text, Enum.Font.GothamBold)
	self.Speed = Theme.Label(self.Vehicle, "Speed", "-- studs/s", 24, Color.Text, Enum.Font.GothamBold, Enum.TextXAlignment.Left)
	self.FuelIcon = holder(self.Vehicle, "FuelIcon", "fuel", Color.Accent)
	self.FuelTrack, self.FuelBar = track(self.Vehicle, "Fuel", Color.Accent)
	self.Fuel = Theme.Label(self.Vehicle, "Fuel", "-- / --", 13, Color.Text, Enum.Font.GothamBold, Enum.TextXAlignment.Right)

	-- Bottom-left: minimap ---------------------------------------------------------------------
	self.Map = Theme.Panel(root, "Minimap")
	self.Map.ClipsDescendants = true
	local mapCorner = self.Map:FindFirstChildOfClass("UICorner")
	if mapCorner ~= nil and mapCorner:IsA("UICorner") then
		mapCorner.CornerRadius = UDim.new(0.5, 0)
	end
	local ring = strokeOf(self.Map)
	if ring ~= nil then
		ring.Color, ring.Thickness, ring.Transparency = Color.Accent, 2, 0.15
	end
	self.North = Theme.Label(self.Map, "North", "N", 12, Color.Accent, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
	self.North.ZIndex = 4
	self.Arrow = Theme.Label(self.Map, "Player", "▲", 20, Color.Accent, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
	self.Arrow.AnchorPoint, self.Arrow.Size, self.Arrow.Position = Vector2.new(0.5, 0.5), UDim2.fromOffset(24, 24), UDim2.fromScale(0.5, 0.5)
	self.Arrow.ZIndex = 5
	-- Subdivide real configured roads so circular clipping does not erase long segments.
	for _, road in ipairs(mapConfig.Roads) do
		for index = 2, #road.Points do
			local a, b = road.Points[index - 1], road.Points[index]
			local count = math.max(1, math.ceil(math.sqrt((b.X - a.X) ^ 2 + (b.Z - a.Z) ^ 2) / 10))
			for step = 1, count do
				local t0, t1 = (step - 1) / count, step / count
				local part = Theme.Box(self.Map, road.Id, Color.Road)
				part.AnchorPoint = Vector2.new(0.5, 0.5)
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
		local depot = point.Kind == "Depot"
		local marker = Theme.Label(self.Map, point.Id, if depot then "D" else "L", 11, Color.Panel, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
		marker.BackgroundTransparency, marker.BackgroundColor3 = 0, if depot then Color.Warning else Color.Accent
		marker.AnchorPoint, marker.Size, marker.ZIndex = Vector2.new(0.5, 0.5), UDim2.fromOffset(18, 18), 3
		Theme.Round(marker)
		table.insert(self.Markers, { UI = marker, X = point.X, Z = point.Z })
	end

	-- Driving controls -------------------------------------------------------------------------
	self.Drive = Instance.new("Frame")
	self.Drive.Name, self.Drive.Size, self.Drive.BackgroundTransparency, self.Drive.BorderSizePixel =
		"VehicleActions", UDim2.fromScale(1, 1), 1, 0
	self.Drive.Parent = root
	self.DriveButtons, self.DriveEntries = {}, {}
	local function driveButton(parent_: Instance, name: string, icon: string, caption: string, tint: Color3)
		local button = Theme.Button(parent_, name)
		local entry = {
			Button = button,
			Icon = holder(button, "Icon", icon, tint),
			Caption = Theme.Label(button, "Caption", caption, 12, Color.Text, Enum.Font.GothamBold, Enum.TextXAlignment.Center),
		}
		at(entry.Icon, 32, 19, 26, 26)
		at(entry.Caption, 0, 37, 64, 16)
		return button, entry
	end
	for _, name in ipairs({ "Forward", "Reverse", "Left", "Right", "Brake" }) do
		local spec = DRIVE_SPECS[name]
		local button, entry = driveButton(self.Drive, name, spec.Icon, spec.Caption, spec.Tint)
		self.DriveButtons[name] = button
		self.DriveEntries[name] = entry
	end
	local exit, exitEntry = driveButton(root, "ExitVehicle", "exit", "Salir", Color.Health)
	local camera, cameraEntry = driveButton(root, "VehicleCamera", "camera", "Cabina", Color.Text)
	self.Exit, self.Camera, self.CameraCaption = exit, camera, cameraEntry.Caption
	self.DriveEntries.Exit, self.DriveEntries.Camera = exitEntry, cameraEntry

	self.Notice = Theme.Label(root, "Notice", "", 14, Color.Text, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
	self.Notice.BackgroundColor3, self.Notice.BackgroundTransparency, self.Notice.TextWrapped = Color.Panel, 1, true
	Theme.Corner(self.Notice, 8)
	return self
end

function HUDView:SetMenuOpen(open: boolean)
	self.MenuIcon.Visible = not open
	self.CloseIcon.Visible = open
end

function HUDView:Layout(width: number, height: number, touch: boolean)
	self.Width, self.Height, self.Touch = width, height, touch
	self:Relayout()
end

function HUDView:Relayout()
	if self.Width <= 0 or self.Height <= 0 then
		return
	end
	local g = HUDLayout.Compute(self.Width, self.Height, {
		Mode = self.Mode,
		ChatExpanded = self.ChatExpanded,
		Touch = self.Touch,
	})
	self.Geometry, self.Profile = g, g.Profile
	self.GeometryMode, self.GeometryChat = self.Mode, self.ChatExpanded
	local compact = g.Profile.Compact

	put(self.Chat, g.ChatButton)
	at(self.ChatIcon, 22, 22, 26, 26)
	put(self.MenuButton, g.MenuButton)
	at(self.MenuIcon, 22, 22, 26, 26)
	at(self.CloseIcon, 22, 22, 22, 22)

	-- Left menu column or phone shortcut row; radio hugs the minimap.
	for _, entry in pairs(self.NavEntries) do
		entry.Button.Visible = false
	end
	for _, item in ipairs(g.MenuItems) do
		local entry = self.NavEntries[item.Id]
		put(entry.Button, item.Rect)
		at(entry.Icon, 22, item.Rect.H / 2, 22, 22)
		entry.Label.Visible = true
		at(entry.Label, 42, 0, item.Rect.W - 48, item.Rect.H)
		entry.Button.Visible = true
	end
	for _, item in ipairs(g.Shortcuts) do
		local entry = self.NavEntries[item.Id]
		put(entry.Button, item.Rect)
		at(entry.Icon, item.Rect.W / 2, item.Rect.H / 2, 24, 24)
		entry.Label.Visible = false
		entry.Button.Visible = true
	end
	local radio = self.NavEntries.radio
	put(radio.Button, g.Radio)
	at(radio.Icon, g.Radio.W / 2, g.Radio.H / 2, 24, 24)
	radio.Label.Visible = false
	self.NavLayout = {}
	for _, item in ipairs(g.MenuItems) do
		self.NavLayout[item.Id] = true
	end
	for _, item in ipairs(g.Shortcuts) do
		self.NavLayout[item.Id] = true
	end
	self.NavLayout.radio = true

	put(self.Compass, g.Compass)
	put(self.Zone, g.Zone)
	at(self.HeadingPill, (g.Compass.W - 84) / 2, 2, 84, 22)
	at(self.ZoneIcon, 16, g.Zone.H / 2, 14, 14)
	at(self.Location, 28, 0, g.Zone.W - 36, g.Zone.H)
	self.Location.TextSize = if compact then 13 else 14
	self.CompassKey = ""

	-- Status: heart + bar + number, then condition (+ role on regular screens).
	put(self.Status, g.Status)
	local sw = g.Status.W
	if compact then
		at(self.HeartIcon, 18, 15, 16, 16)
		at(self.HealthTrack, 32, 11, sw - 32 - 76, 8)
		at(self.Health, sw - 72, 3, 64, 24)
		self.Health.TextSize = 14
		at(self.Condition, 10, 28, sw - 20, 16)
		self.Role.Visible = false
	else
		at(self.HeartIcon, 22, 19, 22, 22)
		at(self.HealthTrack, 40, 14, sw - 40 - 96, 10)
		at(self.Health, sw - 92, 6, 82, 26)
		self.Health.TextSize = 16
		at(self.Condition, 12, 34, sw * 0.58, 18)
		at(self.Role, sw * 0.58, 34, sw * 0.42 - 12, 18)
		self.Role.Visible = true
	end
	self.Condition.TextSize = if compact then 12 else 13

	-- Weapon + hotbar.
	put(self.Weapon, g.Weapon)
	local ww, wh = g.Weapon.W, g.Weapon.H
	if compact then
		for _, icon in pairs(self.WeaponIcons) do
			at(icon, 22, wh / 2, 28, 28)
		end
		at(self.WeaponName, 42, 0, ww * 0.34, wh)
		at(self.AmmoState, 42, 0, ww * 0.34, wh)
		at(self.Ammo, ww * 0.40, 0, ww * 0.60 - 10, wh)
		self.Ammo.TextSize = 20
	else
		for _, icon in pairs(self.WeaponIcons) do
			at(icon, 34, wh / 2, 44, 44)
		end
		at(self.WeaponName, 66, 8, ww - 74, 18)
		at(self.AmmoState, 66, 40, ww - 74, 16)
		at(self.Ammo, ww - 130, 8, 120, 48)
		self.Ammo.TextSize = 28
	end
	put(self.Hotbar, g.Hotbar)
	for _, id in ipairs(HUDLayout.SlotsRegular) do
		self.SlotEntries[id].Button.Visible = false
	end
	for index, slot in ipairs(g.Slots) do
		local entry = self.SlotEntries[g.SlotIds[index]]
		at(entry.Button, slot.X - g.Hotbar.X, 0, slot.W, slot.H)
		entry.Button.Visible = true
	end

	-- Vehicle telemetry.
	put(self.Vehicle, g.Vehicle)
	local vw = g.Vehicle.W
	if compact then
		at(self.VehicleIcon, 18, 15, 18, 18)
		at(self.VehicleName, 32, 5, vw * 0.38, 20)
		self.VehicleName.TextSize = 13
		at(self.Speed, vw * 0.36, 2, vw * 0.64 - 8, 26)
		self.Speed.TextSize, self.Speed.TextXAlignment = 17, Enum.TextXAlignment.Right
		at(self.FuelIcon, 18, 43, 16, 16)
		at(self.FuelTrack, 32, 39, vw - 32 - 72, 8)
		at(self.Fuel, vw - 68, 32, 60, 22)
	else
		at(self.VehicleIcon, 24, 19, 22, 22)
		at(self.VehicleName, 40, 8, vw - 50, 22)
		self.VehicleName.TextSize = 15
		at(self.Speed, 12, 32, vw - 24, 34)
		self.Speed.TextSize, self.Speed.TextXAlignment = 26, Enum.TextXAlignment.Left
		at(self.FuelIcon, 22, 77, 18, 18)
		at(self.FuelTrack, 36, 72, vw - 36 - 92, 10)
		at(self.Fuel, vw - 86, 64, 76, 26)
	end

	-- Minimap.
	put(self.Map, g.Map)
	at(self.North, 0, 2, g.Map.W, 16)
	self.MapKey = ""

	-- Driving buttons.
	for name, button in pairs(self.DriveButtons) do
		put(button, g.Drive[name])
	end
	put(self.Exit, g.Drive.Exit)
	put(self.Camera, g.Drive.Camera)
	put(self.Notice, g.Notice)
end

function HUDView:UpdateCompass(heading: number)
	local g = self.Geometry
	local key = string.format("%d|%d", math.floor(heading * 2), g.Compass.W)
	if key == self.CompassKey then
		return
	end
	self.CompassKey = key
	local half, mid = g.Compass.W / 2, g.Compass.H / 2
	local pillHalf = 48
	for _, mark in ipairs(self.CompassMarks) do
		local offset = Rules.CompassOffset(mark.Angle, heading)
		local x = half + offset / (COMPASS_FOV / 2) * half
		local show = math.abs(offset) <= COMPASS_FOV / 2 and math.abs(x - half) >= pillHalf
		mark.UI.Visible = show
		if show then
			mark.UI.Position = UDim2.fromOffset(x, mid)
		end
	end
end

function HUDView:UpdateMap(position: any, heading: number)
	local g = self.Geometry
	local size = g.Map.W
	local key = string.format("%d|%d|%d", math.floor(position.X * 2), math.floor(position.Z * 2), size)
	if key == self.MapKey then
		return
	end
	self.MapKey = key
	local range = MAP_RANGE
	for _, line in ipairs(self.Lines) do
		local x1, y1 = Rules.Project(line.X1, line.Z1, position.X, position.Z, range, size)
		local x2, y2 = Rules.Project(line.X2, line.Z2, position.X, position.Z, range, size)
		local x, y = (x1 + x2) / 2, (y1 + y2) / 2
		local visible = (x - size / 2) ^ 2 + (y - size / 2) ^ 2 < (size / 2 - 8) ^ 2
		line.UI.Visible = visible
		if visible then
			line.UI.Position = UDim2.fromOffset(x, y)
			line.UI.Size = UDim2.fromOffset(math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2) + 1, math.max(2, line.Width * size / (2 * range)))
			line.UI.Rotation = math.deg(math.atan2(y2 - y1, x2 - x1))
		end
	end
	for _, marker in ipairs(self.Markers) do
		local x, y = Rules.Project(marker.X, marker.Z, position.X, position.Z, range, size)
		marker.UI.Position = UDim2.fromOffset(x, y)
		marker.UI.Visible = (x - size / 2) ^ 2 + (y - size / 2) ^ 2 < (size / 2 - 14) ^ 2
	end
end

function HUDView:Render(state: any)
	if self.Geometry == nil then
		return
	end
	local mode = state.Mode
	self.Mode = mode
	if mode ~= self.GeometryMode or self.ChatExpanded ~= self.GeometryChat then
		self:Relayout()
	end
	local g = self.Geometry
	local blocked = state.Blocked
	local shown = not blocked
	local driving = mode == "driving"
	local medical = state.Medical
	local root = state.Root
	local hasRoot = root ~= nil
	local hasCharacter = mode ~= "unavailable"

	-- Visibility (everything except the menu button hides while a panel or the Roblox menu is open).
	self.Chat.Visible = shown
	self.MenuButton.Visible = true
	self.Status.Visible = shown
	self.Compass.Visible = shown and hasRoot
	self.Zone.Visible = shown and hasRoot
	self.Weapon.Visible = shown and g.Visible.Weapon and hasCharacter
	self.Hotbar.Visible = shown and g.Visible.Hotbar and hasCharacter
	self.Vehicle.Visible = shown and driving and g.Visible.Vehicle
	self.Map.Visible = shown and hasRoot and g.Visible.Map
	self.NavEntries.radio.Button.Visible = shown and g.Visible.Radio
	for id, entry in pairs(self.NavEntries) do
		if id ~= "radio" then
			entry.Button.Visible = shown and self.NavLayout[id] == true
		end
	end
	self.Drive.Visible = driving and shown and self.Touch
	self.Exit.Visible, self.Camera.Visible = driving and shown, driving and shown
	self.CameraCaption.Text = if self.FirstPerson then "Exterior" else "Cabina"

	local chatStroke = strokeOf(self.Chat)
	if chatStroke ~= nil then
		local active = g.ChatExpanded
		chatStroke.Color = if active then Color.Accent else Color.Border
		chatStroke.Transparency = if active then 0.1 else 0.86
	end

	-- Health and condition: only the Humanoid and the server's medical snapshot feed these.
	local health, maxHealth = state.Health, state.MaxHealth
	setText(self.Health, if health ~= nil and maxHealth ~= nil then string.format("%d / %d", math.ceil(health), math.floor(maxHealth)) else "-- / --")
	self.HealthBar.Size = UDim2.fromScale(Rules.Fraction(health, maxHealth), 1)
	local conditionText, tone = Rules.Condition(mode, health, maxHealth, medical)
	setText(self.Condition, conditionText)
	self.Condition.TextColor3 = toneColor(tone)
	local role = if medical ~= nil and type(medical.role) == "string" then medical.role else nil
	setText(self.Role, if role ~= nil then (ROLE_NAMES[role] or role) else "")

	-- Weapon and quick slots.
	local weaponId = if medical ~= nil and type(medical.equippedWeaponId) == "string" then medical.equippedWeaponId else nil
	local weapons = if medical ~= nil and type(medical.weapons) == "table" then medical.weapons else {}
	local weapon = if weaponId ~= nil then weapons[weaponId] else nil
	local reloading = weapon ~= nil and weapon.isReloading == true
	self.Ammo.Text = if weapon ~= nil then string.format("%d / %d", weapon.magazine, weapon.reserve) else "-- / --"
	self.Ammo.TextColor3 = if weapon ~= nil and weapon.magazine <= 0 then Color.Health else Color.Text
	setText(self.WeaponName, if weapon ~= nil then string.upper(tostring(weapon.name or weaponId)) else "SIN ARMA")
	local stateText = ""
	if reloading then
		stateText = "RECARGANDO"
	elseif weapon ~= nil and weapon.magazine <= 0 then
		stateText = if weapon.reserve > 0 then "RECARGA [R]" else "SIN MUNICIÓN"
	end
	setText(self.AmmoState, stateText)
	self.AmmoState.Visible = stateText ~= ""
	self.WeaponName.Visible = stateText == "" or not g.Profile.Compact
	self.WeaponIcons.Rifle.Visible = weaponId ~= "Sidearm"
	self.WeaponIcons.Sidearm.Visible = weaponId == "Sidearm"

	local canAct = mode == "walking" and not blocked
	local items = if medical ~= nil and type(medical.medicalItems) == "table" then medical.medicalItems else {}
	for id, entry in pairs(self.SlotEntries) do
		local button = entry.Button
		local owned = true
		local interactable = canAct
		if id == "Rifle" or id == "Sidearm" then
			owned = weapons[id] ~= nil
			interactable = canAct and owned and not reloading
			local selected = weaponId == id
			if entry.Stroke ~= nil then
				entry.Stroke.Color = if selected then Color.Accent else Color.Border
				entry.Stroke.Thickness = if selected then 2 else 1
				entry.Stroke.Transparency = if selected then 0 else 0.86
			end
		elseif id == "Bandage" or id == "Medkit" then
			local count = if type(items[id]) == "number" then items[id] else 0
			owned = count > 0
			interactable = canAct and owned and not (medical ~= nil and medical.incapacitated == true)
			setText(entry.Count, tostring(count))
			entry.Count.TextColor3 = if owned then Color.Accent else Color.Muted
		end
		button.Interactable = interactable
		button.BackgroundTransparency = if owned then 0.18 else 0.55
	end

	-- Vehicle telemetry (real snapshot values only).
	if driving then
		local vehicle = state.Vehicle
		setText(self.VehicleName, if vehicle ~= nil then tostring(vehicle.name) else tostring(state.VehicleId))
		setText(
			self.Speed,
			if vehicle ~= nil then string.format("%s%.0f studs/s", if vehicle.speed < 0 then "R " else "", math.abs(vehicle.speed)) else "-- studs/s"
		)
		local fraction = if vehicle ~= nil then Rules.Fraction(vehicle.fuel, vehicle.fuelCapacity) else 0
		self.FuelBar.Size = UDim2.fromScale(fraction, 1)
		self.FuelBar.BackgroundColor3 = if fraction < 0.25 then Color.Warning else Color.Accent
		setText(self.Fuel, if vehicle ~= nil then string.format("%.0f / %.0f", vehicle.fuel, vehicle.fuelCapacity) else "-- / --")
	end

	-- Compass, zone and minimap from the character (or the vehicle seat while driving).
	if hasRoot and root:IsA("BasePart") then
		local subject = if driving and state.Seat ~= nil then state.Seat else root
		local position, look = subject.Position, subject.CFrame.LookVector
		local heading = Rules.Heading(look.X, look.Z)
		setText(self.Heading, string.format("%s %03d°", Rules.Cardinal(heading), math.floor(heading + 0.5) % 360))
		setText(self.Location, Rules.Zone(position.X, position.Z, self.MapConfig, self.LogisticsConfig))
		self.Arrow.Rotation = heading
		if self.Compass.Visible then
			self:UpdateCompass(heading)
		end
		if self.Map.Visible then
			self:UpdateMap(position, heading)
		end
	end

	-- Notice bubble only exists while there is text.
	local hasNotice = self.Notice.Text ~= ""
	self.Notice.BackgroundTransparency = if hasNotice then 0.25 else 1
end

function HUDView:Destroy()
	self.Root:Destroy()
end

return HUDView
