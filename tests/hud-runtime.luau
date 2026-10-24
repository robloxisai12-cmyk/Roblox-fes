--!nocheck
-- Actual HUD/logistics modules with API doubles. This is not Roblox rendering/replication.
local checks = 0
local function check(value, message)
	assert(value, message)
	checks += 1
end
local allSignals = {}
local function signal()
	local listeners = {}
	local value = {}
	function value:Connect(callback)
		local connection = { Connected = true }
		function connection:Disconnect()
			self.Connected = false
		end
		table.insert(listeners, { connection, callback })
		return connection
	end
	function value:Fire(...)
		for _, item in ipairs(table.clone(listeners)) do
			if item[1].Connected then
				item[2](...)
			end
		end
	end
	function value:Count()
		local n = 0
		for _, item in ipairs(listeners) do
			if item[1].Connected then
				n += 1
			end
		end
		return n
	end
	table.insert(allSignals, value)
	return value
end
local function connectionCount()
	local n = 0
	for _, s in ipairs(allSignals) do
		n += s:Count()
	end
	return n
end
local vmeta = {}
local function vec(x, y, z)
	return setmetatable({ X = x, Y = y, Z = z }, vmeta)
end
function vmeta.__add(a, b)
	return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
function vmeta.__sub(a, b)
	return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
function vmeta.__mul(a, b)
	return vec(a.X * b, a.Y * b, a.Z * b)
end
function vmeta.__index(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X ^ 2 + v.Y ^ 2 + v.Z ^ 2)
	end
	if k == "Unit" then
		return v * (1 / v.Magnitude)
	end
end
local cfmeta = {}
local function cf(x, y, z, yaw)
	return setmetatable({ Position = vec(x or 0, y or 0, z or 0), Yaw = yaw or 0 }, cfmeta)
end
function cfmeta.__index(v, k)
	if k == "LookVector" then
		return vec(-math.sin(v.Yaw), 0, -math.cos(v.Yaw))
	end
end
local function rotate(v, yaw)
	return vec(v.X * math.cos(yaw) + v.Z * math.sin(yaw), v.Y, -v.X * math.sin(yaw) + v.Z * math.cos(yaw))
end
function cfmeta.__mul(a, b)
	local p = a.Position + rotate(b.Position, a.Yaw)
	return cf(p.X, p.Y, p.Z, a.Yaw + b.Yaw)
end
function cfmeta.__add(a, b)
	local p = a.Position + b
	return cf(p.X, p.Y, p.Z, a.Yaw)
end
local CFrameMock = {
	new = function(x, y, z)
		if type(x) == "table" then
			return cf(x.X, x.Y, x.Z)
		end
		return cf(x, y, z)
	end,
	Angles = function(_, y, _)
		return cf(0, 0, 0, y)
	end,
}
local enum = setmetatable({}, {
	__index = function(t, k)
		local group = setmetatable({}, {
			__index = function(g, n)
				rawset(g, n, k .. "." .. n)
				return g[n]
			end,
		})
		rawset(t, k, group)
		return group
	end,
})
local methods = {}
local meta = {
	__index = function(t, k)
		if t.ClassName == "ChatWindowConfiguration" and (k == "Position" or k == "Size") then
			error("Invalid ChatWindowConfiguration property: " .. k)
		end
		if methods[k] then
			return methods[k]
		end
		if k == "Position" and rawget(t, "CFrame") then
			return t.CFrame.Position
		end
		if k == "Parent" then
			return rawget(t, "_parent")
		end
		return rawget(t, "children")[k]
	end,
	__newindex = function(t, k, v)
		if k == "Parent" then
			local old = rawget(t, "_parent")
			if old then
				old.children[t.Name] = nil
			end
			rawset(t, "_parent", v)
			if v then
				v.children[t.Name] = t
			end
		else
			rawset(t, k, v)
		end
	end,
}
local function instance(class, name)
	local value = setmetatable({
		ClassName = class,
		Name = name or class,
		children = {},
		attributes = {},
		properties = {},
		Enabled = true,
		Visible = true,
		AbsoluteSize = { X = 1280, Y = 720 },
	}, meta)
	for _, event in ipairs({ "ChildAdded", "AncestryChanged", "Destroying", "Activated", "InputBegan", "Died" }) do
		value[event] = signal()
	end
	return value
end
function methods:IsA(class)
	return self.ClassName == class
		or (class == "BasePart" and (self.ClassName == "Part" or self.ClassName == "VehicleSeat"))
end
function methods:FindFirstChild(name)
	return self.children[name]
end
function methods:WaitForChild(name)
	return assert(self.children[name], name)
end
function methods:FindFirstChildOfClass(class)
	for _, item in pairs(self.children) do
		if item:IsA(class) then
			return item
		end
	end
end
function methods:GetChildren()
	local result = {}
	for _, child in pairs(self.children) do
		table.insert(result, child)
	end
	return result
end
function methods:GetPropertyChangedSignal(name)
	if not self.properties[name] then
		self.properties[name] = signal()
	end
	return self.properties[name]
end
function methods:GetAttributeChangedSignal(name)
	return self:GetPropertyChangedSignal("attr" .. name)
end
function methods:GetAttribute(name)
	return self.attributes[name]
end
function methods:SetAttribute(name, value)
	self.attributes[name] = value
	self:GetAttributeChangedSignal(name):Fire()
end
function methods:IsDescendantOf(ancestor)
	local parent = self.Parent
	while parent do
		if parent == ancestor then
			return true
		end
		parent = parent.Parent
	end
	return false
end
function methods:Destroy()
	self.Destroying:Fire()
	for _, child in ipairs(self:GetChildren()) do
		child:Destroy()
	end
	self.Parent = nil
end
function methods:GetPivot()
	return self._pivot or cf()
end
function methods:PivotTo(target)
	local old = self:GetPivot()
	for _, part in ipairs(self:GetChildren()) do
		if part:IsA("BasePart") then
			local localPosition = rotate(part.CFrame.Position - old.Position, -old.Yaw)
			part.CFrame = target * cf(localPosition.X, localPosition.Y, localPosition.Z, part.CFrame.Yaw - old.Yaw)
		end
	end
	self._pivot = target
end
local function attach(parent, child)
	child.Parent = parent
	return child
end
local function sit(seat, humanoid)
	local old = seat.Occupant
	if old then
		old.SeatPart = nil
		old:GetPropertyChangedSignal("SeatPart"):Fire()
	end
	seat.Occupant = humanoid
	if humanoid then
		humanoid.SeatPart = seat
	end
	seat:GetPropertyChangedSignal("Occupant"):Fire()
	if humanoid then
		humanoid:GetPropertyChangedSignal("SeatPart"):Fire()
	end
end
function methods:Sit(humanoid)
	humanoid.Sit = true
	sit(self, humanoid)
end
local udim2 = {
	new = function(xs, xo, ys, yo)
		return { X = { Scale = xs, Offset = xo }, Y = { Scale = ys, Offset = yo } }
	end,
}
function udim2.fromOffset(x, y)
	return udim2.new(0, x, 0, y)
end
function udim2.fromScale(x, y)
	return udim2.new(x, 0, y, 0)
end
local services = {}
local Workspace = instance("Workspace")
function Workspace:Raycast()
	return nil
end
local camera = instance("Camera")
camera.ViewportSize = { X = 1280, Y = 720 }
Workspace.CurrentCamera = camera
local storage = instance("ReplicatedStorage")
local shared = attach(storage, instance("Folder", "Shared"))
local configs = attach(shared, instance("Folder", "config"))
local remotes = attach(storage, instance("Folder", "Remotes"))
local remote = attach(remotes, instance("RemoteEvent", "CombatRequest"))
remote.OnClientEvent = signal()
local sent, delivered = {}, {}
function remote:FireServer(payload)
	table.insert(sent, payload)
end
function remote:FireClient(player, payload)
	table.insert(delivered, { player, payload })
end
local Players = { PlayerRemoving = signal() }
local heartbeat = signal()
services.ReplicatedStorage, services.Workspace, services.Players, services.RunService =
	storage, Workspace, Players, { Heartbeat = heartbeat }
local gui = instance("PlayerGui")
local nativeTouch = attach(gui, instance("ScreenGui", "TouchGui"))
local player =
	{ Parent = Players, CharacterAdded = signal(), CharacterRemoving = signal(), CameraMode = enum.CameraMode.Classic }
function Players:GetPlayerFromCharacter(character)
	return if player.Character == character then player else nil
end
local role = "Engineer"
local folder = {}
for name in pairs(sources) do
	folder[name] = { Name = name, Parent = folder }
end
for name, module in pairs(folder) do
	if name:match("Config$") then
		configs.children[name] = module
	end
end
shared.children.HUDRules = folder.HUDRules
local loaded = {
	PlayerDataService = {
		GetSession = function()
			return { Role = role }
		end,
	},
	InventoryService = {
		GetInventory = function()
			return { Weapons = {}, MedicalItems = {}, Supplies = { Rations = 7 } }
		end,
	},
}
folder.PlayerDataService = { Name = "PlayerDataService" }
folder.InventoryService = { Name = "InventoryService" }
local now = 0
local function loadModule(module)
	local name = module.Name
	if loaded[name] then
		return loaded[name]
	end
	local chunk, err = loadstring(assert(sources[name], name), name)
	assert(chunk, err)
	setfenv(
		chunk,
		setmetatable({
			script = module,
			require = loadModule,
			game = {
				GetService = function(_, name)
					return assert(services[name], name)
				end,
			},
			Instance = { new = instance },
			Vector3 = { new = vec },
			Vector2 = {
				new = function(x, y)
					return { X = x, Y = y }
				end,
				zero = { X = 0, Y = 0 },
			},
			CFrame = CFrameMock,
			UDim2 = udim2,
			UDim = {
				new = function(s, o)
					return { Scale = s, Offset = o }
				end,
			},
			Color3 = {
				fromRGB = function(r, g, b)
					return { r, g, b }
				end,
			},
			Enum = enum,
			RaycastParams = {
				new = function()
					return {}
				end,
			},
			os = {
				clock = function()
					return now
				end,
			},
		}, { __index = getfenv() })
	)
	loaded[name] = chunk()
	return loaded[name]
end
local Rules = loadModule(folder.HUDRules)
for _, case in ipairs({ { 0, -1, 0, "N" }, { 1, 0, 90, "E" }, { 0, 1, 180, "S" }, { -1, 0, 270, "O" } }) do
	local heading = Rules.Heading(case[1], case[2])
	check(math.abs(heading - case[3]) < 0.001 and Rules.Cardinal(heading) == case[4], "compass cardinal " .. case[4])
end
local x, y = Rules.Project(20, -20, 0, 0, 100, 100)
check(x == 60 and y == 40, "northeast marker projects right and up")
for _, size in ipairs({ { 360, 640 }, { 667, 320 }, { 812, 375 }, { 1024, 768 }, { 1920, 1080 } }) do
	local p = Rules.Profile(size[1], size[2])
	check(p.ButtonSize >= 44 and p.MapSize <= size[2], "effective touch size at " .. size[1])
end
local payloadRules = loadModule(folder.CombatRequestRules)
local function drivePayload(throttle, steer)
	return { action = "logistics", operation = "drive", vehicleId = "Ranger1", throttle = throttle, steer = steer }
end
for _, value in ipairs({ math.huge, -math.huge, 0 / 0, 2, -2, "1" }) do
	check(payloadRules.Validate(drivePayload(value, 0), 1) == nil, "reject invalid throttle")
	check(payloadRules.Validate(drivePayload(0, value), 1) == nil, "reject invalid steer")
end
check(payloadRules.Validate(drivePayload(1, -1), 1) ~= nil, "bounded drive intent accepted")
local extra = drivePayload(1, 0)
extra.speed = 999
check(payloadRules.Validate(extra, 1) == nil, "client cannot set speed")
local function character()
	local model = attach(Workspace, instance("Model", "Character"))
	local humanoid = attach(model, instance("Humanoid"))
	humanoid.Health, humanoid.MaxHealth = 100, 100
	local root = attach(model, instance("Part", "HumanoidRootPart"))
	root.CFrame = cf(-75, 27, -184)
	return model, humanoid
end
player.Character = character()
local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
local Logistics = loadModule(folder.LogisticsService)
local config = loadModule(folder.LogisticsConfig)
Logistics.Start()
Logistics.Start()
local world = Workspace:FindFirstChild("SierraDeGuardiaLogistics")
local ranger = world:FindFirstChild("Ranger1")
local seat = ranger:FindFirstChild("DriverSeat")
local seat2 = world:FindFirstChild("Ranger2"):FindFirstChild("DriverSeat")
check(ranger:GetAttribute("VehicleCategory") == "Pickup", "server emits pickup category")
role = "Rifleman"
local deniedEntry = Logistics.HandleRequest(player, { operation = "enter_vehicle", vehicleId = "Ranger1" })
check(
	not deniedEntry.ok and deniedEntry.code == "driver_unauthorized",
	"actual entry preserves default-role restriction"
)
role = "Engineer"
check(
	Logistics.HandleRequest(player, { operation = "enter_vehicle", vehicleId = "Ranger1" }).ok,
	"actual authorized entry uses server seat"
)
local function serverDrive(id, throttle, steer)
	local raw = drivePayload(throttle, steer)
	raw.vehicleId = id
	return Logistics.HandleRequest(player, assert(payloadRules.Validate(raw, 1)))
end
check(serverDrive("Ranger1", 1, 0).ok, "real service accepts actual authorized occupant")
local before = ranger:GetPivot().Position
now += 0.1
heartbeat:Fire(0.1)
check((ranger:GetPivot().Position - before).Magnitude > 0, "accepted input advances server vehicle")
now += config.DriveInputTimeout
before = ranger:GetPivot().Position
heartbeat:Fire(0.1)
check((ranger:GetPivot().Position - before).Magnitude == 0, "lost input expires and stops movement")
check(not serverDrive("Ranger2", 1, 0).ok, "reject driving a different vehicle")
role = "Rifleman"
check(not serverDrive("Ranger1", 1, 0).ok, "driver role cannot be spoofed")
role = "Engineer"
player.Character:SetAttribute("SierraIncapacitated", true)
check(not serverDrive("Ranger1", 1, 0).ok, "server rejects incapacitated driver")
before = ranger:GetPivot().Position
heartbeat:Fire(0.1)
check(
	(ranger:GetPivot().Position - before).Magnitude == 0 and humanoid.Sit == false,
	"incapacitation stops vehicle and ejects"
)
player.Character:SetAttribute("SierraIncapacitated", false)
sit(seat, humanoid)
now += 1
local rejected = 0
for _ = 1, 13 do
	if not serverDrive("Ranger1", 0, 0).ok then
		rejected += 1
	end
end
check(rejected == 1, "dedicated input rate limit leaves logistics interactions separate")
-- A different, closer truck must not replace the true driver's identity.
player.Character:FindFirstChild("HumanoidRootPart").CFrame = seat2.CFrame
local snapshot = Logistics.HandleRequest(player, { operation = "status" })
check(
	snapshot.drivenVehicleId == "Ranger1" and snapshot.nearestVehicleId == "Ranger2" and snapshot.isDriving,
	"occupied identity differs from nearest"
)
check(
	snapshot.character == player.Character and snapshot.inventory.supplies.Rations == 7,
	"snapshots carry life token and real inventory"
)
now += 1
serverDrive("Ranger1", 1, 0)
sit(seat, nil)
sit(seat, humanoid)
before = ranger:GetPivot().Position
heartbeat:Fire(0.1)
check((ranger:GetPivot().Position - before).Magnitude == 0, "reentry clears old pedal input")
local uis = {
	TouchEnabled = true,
	InputEnded = signal(),
	InputChanged = signal(),
	WindowFocusReleased = signal(),
	focused = nil,
}
function uis:GetFocusedTextBox()
	return self.focused
end
local cas = { bindings = {} }
function cas:BindActionAtPriority(name, callback, _, priority, ...)
	self.bindings[name] = { Callback = callback, Priority = priority }
end
function cas:UnbindAction(name)
	self.bindings[name] = nil
end
local guiService = { MenuIsOpen = false }
local adapterServices = {
	Player = player,
	PlayerGui = gui,
	Workspace = Workspace,
	CombatRemote = remote,
	Heartbeat = heartbeat,
	GuiService = guiService,
	UserInputService = uis,
	ContextActionService = cas,
}
local Adapter = loadModule(folder.GameAdapter)
local adapter = Adapter.new(adapterServices)
local baseline = connectionCount()
adapter:Start()
local startedCount = connectionCount()
adapter:Start()
check(connectionCount() == startedCount, "adapter Start is idempotent")
check(adapter.Mode == "driving" and adapter.VehicleId == "Ranger1", "adapter observes actual seat")
sit(seat, nil)
check(adapter.Mode == "walking", "exit restores walking without waiting for remote")
adapter:Receive({
	action = "logistics_vehicle_status",
	ok = true,
	character = player.Character,
	vehicle = { id = "Ranger1", isDriver = true },
})
check(adapter.Mode == "walking", "stale seated snapshot cannot reenable driving")
sit(seat, humanoid)
player.Character:SetAttribute("SierraIncapacitated", true)
check(
	adapter.Mode == "incapacitated" and not adapter:CanControl(),
	"medical incapacitation blocks controls immediately"
)
player.Character:SetAttribute("SierraIncapacitated", false)
local oldCharacter = player.Character
local oldHumanoid = humanoid
player.CharacterRemoving:Fire(oldCharacter)
check(adapter.Mode == "unavailable" and adapter.Medical == nil, "removing character clears HUD")
player.Character = character()
humanoid = player.Character:FindFirstChildOfClass("Humanoid")
player.CharacterAdded:Fire(player.Character)
adapter:Receive({ action = "medical_status", character = oldCharacter, health = 8 })
adapter:Receive({
	action = "logistics_status",
	ok = true,
	character = oldCharacter,
	inventory = { supplies = { Rations = 999 } },
	vehicles = {},
	nearestVehicleId = "Ranger1",
})
check(
	adapter.Medical == nil and adapter.Inventory == nil and adapter.NearestVehicleId == nil,
	"old-life snapshots discarded"
)
check(oldHumanoid:GetPropertyChangedSignal("SeatPart"):Count() == 0, "old humanoid listeners disconnected")
local liveCount = connectionCount()
for _ = 1, 5 do
	local old = player.Character
	player.CharacterRemoving:Fire(old)
	player.Character = character()
	humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	player.CharacterAdded:Fire(player.Character)
end
check(connectionCount() == liveCount, "five respawns do not grow live connections")
adapter:Stop()
adapter:Stop()
check(connectionCount() == baseline, "adapter Stop releases all owned connections")
adapter:Start()
check(adapter.Mode == "walking", "adapter restarts with current character")
adapter:Stop()
local existingCharacter = player.Character
player.Character = nil
adapter:Start()
local waitingConnections = connectionCount()
for _ = 1, 20 do
	heartbeat:Fire(0.1)
end
check(connectionCount() == waitingConnections, "waiting for character does not accumulate CharacterAdded listeners")
local delayedCharacter = attach(Workspace, instance("Model", "DelayedCharacter"))
player.Character = delayedCharacter
player.CharacterAdded:Fire(delayedCharacter)
check(adapter.Mode == "unavailable", "HUD waits for late humanoid")
local delayedHumanoid = attach(delayedCharacter, instance("Humanoid"))
delayedHumanoid.Health, delayedHumanoid.MaxHealth = 100, 100
delayedCharacter.ChildAdded:Fire(delayedHumanoid)
check(adapter.Mode == "walking", "late humanoid recovers without negative cache")
adapter:Stop()
player.Character = existingCharacter
local screen = attach(gui, instance("ScreenGui", "HUDTest"))
local chatService = instance("TextChatService")
chatService.ChatVersion = enum.ChatVersion.TextChatService
local chatWindow = attach(chatService, instance("ChatWindowConfiguration"))
chatWindow.HorizontalAlignment = enum.HorizontalAlignment.Left
chatWindow.VerticalAlignment = enum.VerticalAlignment.Top
chatWindow.WidthScale, chatWindow.HeightScale = 1, 1
local chatInput = attach(chatService, instance("ChatInputBarConfiguration"))
adapterServices.MapConfig = loadModule(folder.MapConfig)
adapterServices.LogisticsConfig = config
adapterServices.TextChatService = chatService
adapterServices.StarterGui = { SetCore = function() end }
local Controller = loadModule(folder.HUDController)
local opened = nil
local controller = Controller.new(adapterServices, screen, function(id)
	opened = id
end)
local controllerBaseline = connectionCount()
controller:Start()
local controllerStarted = connectionCount()
controller:Start()
check(connectionCount() == controllerStarted, "HUD controller Start is idempotent")
controller.View.NavButtons.radio.Activated:Fire()
check(opened == "radio", "navigation opens existing radio panel")
for _, size in ipairs({ { 360, 640 }, { 667, 320 }, { 812, 375 }, { 1024, 768 }, { 1920, 1080 } }) do
	screen.AbsoluteSize = { X = size[1], Y = size[2] }
	controller:Layout()
	for _, control in pairs(controller.View.DriveButtons) do
		check(
			control.Size.X.Offset >= 44 and control.Size.Y.Offset >= 44,
			"actual touch controls retain effective dimensions"
		)
	end
	controller.View:Render(controller.Adapter:GetState())
	local controlsToCheck = {}
	for _, control in pairs(controller.View.DriveButtons) do
		table.insert(controlsToCheck, control)
	end
	table.insert(controlsToCheck, controller.View.Exit)
	table.insert(controlsToCheck, controller.View.Camera)
	for _, control in ipairs(controlsToCheck) do
		local left = control.Position.X.Scale * size[1] + control.Position.X.Offset
		local top = control.Position.Y.Scale * size[2] + control.Position.Y.Offset
		check(
			left >= 0
				and top >= 0
				and left + control.Size.X.Offset <= size[1]
				and top + control.Size.Y.Offset <= size[2],
			"vehicle control fits usable screen"
		)
	end
end
-- Check the real view consumes server inventory/health and doesn't synthesize telemetry.
controller.Adapter:Receive({
	action = "medical_status",
	character = player.Character,
	equippedWeaponId = "Rifle",
	weaponName = "Fusil",
	weapons = { Rifle = { name = "Fusil", magazine = 12, reserve = 23 } },
	bleedRate = 0,
})
controller.View:Render(controller.Adapter:GetState())
check(string.find(controller.View.Ammo.Text, "12 / 23", 1, true) ~= nil, "HUD renders actual ammo snapshot")
sit(seat, humanoid)
heartbeat:Fire(0.21)
local controls = controller.Controls
check(nativeTouch.Enabled == false, "driving hides native joystick overlay")
check(controls.DrivingId == "Ranger1" and cas.bindings.RobloxFesDriveForward ~= nil, "driving binds keyboard actions")
check(controller.View.Drive.Visible and not controller.View.Hotbar.Visible, "driving replaces on-foot hotbar")
local forward = { UserInputType = enum.UserInputType.Touch }
local right = { UserInputType = enum.UserInputType.Touch }
controller.View.DriveButtons.Forward.InputBegan:Fire(forward)
controller.View.DriveButtons.Right.InputBegan:Fire(right)
heartbeat:Fire(0.21)
check(sent[#sent].throttle == 1 and sent[#sent].steer == 1, "simultaneous touch pedal and steering")
uis.InputEnded:Fire(forward)
heartbeat:Fire(0.21)
check(sent[#sent].throttle == 0 and sent[#sent].steer == 1, "release outside button stops only that touch")
uis.InputEnded:Fire(right)
cas.bindings.RobloxFesDriveForward.Callback(nil, enum.UserInputState.Begin, { KeyCode = enum.KeyCode.W })
cas.bindings.RobloxFesDriveForward.Callback(nil, enum.UserInputState.Begin, { KeyCode = enum.KeyCode.Up })
cas.bindings.RobloxFesDriveForward.Callback(nil, enum.UserInputState.End, { KeyCode = enum.KeyCode.W })
heartbeat:Fire(0.21)
check(sent[#sent].throttle == 1, "releasing W does not release held arrow key")
cas.bindings.RobloxFesDriveForward.Callback(nil, enum.UserInputState.Cancel, { KeyCode = enum.KeyCode.Up })
heartbeat:Fire(0.21)
check(sent[#sent].throttle == 0, "cancelled key is cleared")
controller.View.DriveButtons.Forward.InputBegan:Fire(forward)
local brake = { UserInputType = enum.UserInputType.Touch }
controller.View.DriveButtons.Brake.InputBegan:Fire(brake)
heartbeat:Fire(0.21)
check(sent[#sent].throttle == 0 and sent[#sent].steer == 0, "brake overrides acceleration")
uis.InputEnded:Fire(brake)
uis.focused = {}
heartbeat:Fire(0.21)
check(sent[#sent].throttle == 0 and next(controls.Touches) == nil, "chat focus cancels held touches")
uis.focused = nil
controller.View.DriveButtons.Forward.InputBegan:Fire(forward)
uis.WindowFocusReleased:Fire()
check(sent[#sent].throttle == 0 and next(controls.Touches) == nil, "focus loss sends immediate neutral input")
controller.View.DriveButtons.Forward.InputBegan:Fire(forward)
forward.UserInputState = enum.UserInputState.Cancel
uis.InputChanged:Fire(forward)
heartbeat:Fire(0.21)
check(sent[#sent].throttle == 0, "cancelled touch clears held pedal")
controller.View.Camera.Activated:Fire()
check(player.CameraMode == enum.CameraMode.LockFirstPerson, "camera button uses native first-person")
gui:SetAttribute("SierraMenuOpen", true)
heartbeat:Fire(0.21)
check(sent[#sent].throttle == 0 and not controller.View.Drive.Visible, "menu clears input and hides vehicle buttons")
gui:SetAttribute("SierraMenuOpen", false)
controller.View.Exit.Activated:Fire()
check(
	sent[#sent].operation == "exit_vehicle" and sent[#sent].vehicleId == "Ranger1",
	"exit uses validated server operation"
)
sit(seat, nil)
heartbeat:Fire(0.21)
check(
	next(cas.bindings) == nil and player.CameraMode == enum.CameraMode.Classic,
	"exit unbinds controls and restores camera"
)
check(not controller.View.Drive.Visible, "exit hides all driving buttons")
check(nativeTouch.Enabled == true, "walking restores native touch controls")
sit(seat, humanoid)
heartbeat:Fire(0.21)
controller.View.DriveButtons.Forward.InputBegan:Fire({ UserInputType = enum.UserInputType.Touch })
local previousLife = player.Character
player.CharacterRemoving:Fire(previousLife)
player.Character = character()
humanoid = player.Character:FindFirstChildOfClass("Humanoid")
player.CharacterAdded:Fire(player.Character)
heartbeat:Fire(0.21)
check(
	controls.DrivingId == nil and next(controls.Touches) == nil and nativeTouch.Enabled,
	"respawn clears pedals and restores walking overlay"
)
sit(seat, humanoid)
heartbeat:Fire(0.21)
local oldParent = seat.Parent
seat.Parent = nil
heartbeat:Fire(0.21)
check(controls.DrivingId == nil and next(cas.bindings) == nil, "destroyed seat cancels controls")
seat.Parent = oldParent
sit(seat, nil)
local oldCamera = Workspace.CurrentCamera
for _ = 1, 3 do
	Workspace.CurrentCamera = instance("Camera")
	Workspace.CurrentCamera.ViewportSize = { X = 812, Y = 375 }
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Fire()
	check(oldCamera:GetPropertyChangedSignal("ViewportSize"):Count() == 0, "old camera viewport disconnected")
	oldCamera = Workspace.CurrentCamera
end
remote.OnClientEvent:Fire({
	action = "logistics_result",
	ok = false,
	code = "driver_unauthorized",
	character = player.Character,
})
check(string.find(controller.View.Notice.Text, "permiso", 1, true) ~= nil, "HUD displays actual permission rejection")
heartbeat:Fire(3)
remote.OnClientEvent:Fire({ action = "logistics_result", ok = true, code = "refueled", character = player.Character })
heartbeat:Fire(2)
check(controller.View.Notice.Text == "Combustible repuesto", "replaced notification survives earlier deadline")
heartbeat:Fire(2.1)
check(controller.View.Notice.Text == "", "notification expires without stale delayed callbacks")
local chatEnabled = chatWindow.Enabled
controller.View.Chat.Activated:Fire()
check(chatWindow.Enabled ~= chatEnabled and chatInput.Enabled, "native chat visibility toggle")
controller:Stop()
controller:Stop()
check(next(cas.bindings) == nil, "Stop unbinds all vehicle actions")
check(connectionCount() == controllerBaseline, "Stop releases controller, camera, input and character listeners")
check(
	chatWindow.Enabled == true and chatWindow.WidthScale == 1 and chatWindow.HeightScale == 1,
	"Stop restores native chat configuration"
)
controller:Start()
controller:Stop()
check(connectionCount() == controllerBaseline, "full HUD restart leaves no extra live listeners")
Logistics.Stop()
Logistics.Stop()
check(heartbeat:Count() == 0, "service and HUD heartbeat cleanup")
Logistics.Start()
Logistics.Stop()
check(connectionCount() == 0, "server restart and HUD teardown leave zero live owned connections")
local InputRules = loadModule(folder.VehicleInputRules)
check(
	select(1, InputRules.Read({ Driver = oldHumanoid, Throttle = 1, Steer = 1, ReceivedAt = now }, humanoid, now, 0.65))
		== 0,
	"input cannot cross character identity"
)
print(string.format("HUD/logistics runtime: %d checks passed (API doubles; Studio pending)", checks))
