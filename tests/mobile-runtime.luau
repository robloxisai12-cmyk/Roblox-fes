--!nocheck
-- Full service modules are injected by scripts/check-mobile.mjs, then executed in a mocked Roblox runtime.
-- These checks verify service behavior, not rendering, touch events, or Roblox replication.
local checks = 0
local function check(value, message)
	assert(value, message)
	checks += 1
end

local function signal()
	local connections = {}
	return {
		Connect = function(_, callback)
			local connection = { Connected = true }
			function connection:Disconnect()
				self.Connected = false
			end
			table.insert(connections, { connection, callback })
			return connection
		end,
		Fire = function(_, ...)
			for _, item in ipairs(table.clone(connections)) do
				if item[1].Connected then
					item[2](...)
				end
			end
		end,
	}
end

local now = 0
local scheduled = {}
local function schedule(delay, callback, ...)
	table.insert(scheduled, { due = now + delay, thread = coroutine.create(callback), args = table.pack(...) })
end
local taskMock = {
	spawn = function(callback, ...)
		schedule(0, callback, ...)
	end,
	delay = function(delay, callback)
		schedule(delay, callback)
	end,
	wait = function(delay)
		return coroutine.yield(delay)
	end,
}
local function advance(seconds)
	local deadline = now + seconds
	for _ = 1, 1000 do
		local index, earliest = nil, math.huge
		for candidate, item in ipairs(scheduled) do
			if item.due <= deadline and item.due < earliest then
				index, earliest = candidate, item.due
			end
		end
		if index == nil then
			now = deadline
			return
		end
		local item = table.remove(scheduled, index)
		now = item.due
		local ok, waitSeconds = coroutine.resume(item.thread, table.unpack(item.args, 1, item.args.n))
		assert(ok, waitSeconds)
		if coroutine.status(item.thread) ~= "dead" then
			item.due = now + (waitSeconds or 0)
			item.args = { n = 0 }
			table.insert(scheduled, item)
		end
	end
	error("Mock scheduler exceeded its work limit")
end

local vectorMeta = {}
local function vector(x, y, z)
	return setmetatable({ X = x, Y = y, Z = z }, vectorMeta)
end
function vectorMeta.__sub(a, b)
	return vector(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
function vectorMeta.__mul(a, b)
	return vector(a.X * b, a.Y * b, a.Z * b)
end
function vectorMeta.__index(value, key)
	if key == "Magnitude" then
		return math.sqrt(value.X ^ 2 + value.Y ^ 2 + value.Z ^ 2)
	elseif key == "Unit" then
		return value * (1 / value.Magnitude)
	end
end

local function instance(className, name)
	local value = { ClassName = className, Name = name or className, children = {}, attributes = {} }
	function value:IsA(class)
		return self.ClassName == class or (class == "BasePart" and self.ClassName == "Part")
	end
	function value:FindFirstChild(childName)
		return self.children[childName]
	end
	function value:WaitForChild(childName)
		return assert(self.children[childName], childName)
	end
	function value:FindFirstChildOfClass(class)
		for _, child in pairs(self.children) do
			if child:IsA(class) then
				return child
			end
		end
		return nil
	end
	function value:IsDescendantOf(ancestor)
		local current = self.Parent
		while current ~= nil do
			if current == ancestor then
				return true
			end
			current = current.Parent
		end
		return false
	end
	function value:SetAttribute(key, item)
		self.attributes[key] = item
	end
	function value:GetAttribute(key)
		return self.attributes[key]
	end
	return value
end
local function attach(parent, child)
	parent.children[child.Name] = child
	child.Parent = parent
	return child
end

local Players = { PlayerAdded = signal(), PlayerRemoving = signal(), list = {} }
function Players:GetPlayers()
	return self.list
end
function Players:GetPlayerFromCharacter(character)
	for _, player in ipairs(self.list) do
		if player.Character == character then
			return player
		end
	end
end
function Players:GetPlayerByUserId(id)
	for _, player in ipairs(self.list) do
		if player.UserId == id then
			return player
		end
	end
end
local Workspace = instance("Workspace")
local rays = {}
function Workspace:Raycast(origin, direction, params)
	table.insert(rays, { origin = origin, direction = direction, params = params })
	return nil
end
function Workspace:GetServerTimeNow()
	return now
end
local storage = instance("ReplicatedStorage")
local shared = attach(storage, instance("Folder", "Shared"))
local configs = attach(shared, instance("Folder", "config"))
local remoteFolder = attach(storage, instance("Folder", "Remotes"))
local remote = attach(remoteFolder, instance("RemoteEvent", "CombatRequest"))
remote.OnServerEvent = signal()
local messages = {}
function remote:FireClient(player, message)
	table.insert(messages, { player = player, message = message })
end
local services = { Players = Players, Workspace = Workspace, ReplicatedStorage = storage }
local gameMock = {
	GetService = function(_, name)
		return assert(services[name], name)
	end,
}
local moduleFolder = {}
for name in pairs(sources) do
	local module = { Name = name, Parent = moduleFolder }
	moduleFolder[name] = module
	if string.find(name, "Config$") then
		configs.children[name] = module
	end
end
local loaded = {
	PlayerDataService = {
		GetSession = function()
			return { Role = "Medic" }
		end,
	},
	LogisticsService = {
		HandleRequest = function()
			return { action = "logistics_result", ok = true }
		end,
	},
}
moduleFolder.PlayerDataService = { Name = "PlayerDataService" }
moduleFolder.LogisticsService = { Name = "LogisticsService" }
local function loadModule(module)
	local name = module.Name
	if loaded[name] ~= nil then
		return loaded[name]
	end
	local chunk, parseError = loadstring(assert(sources[name], name), name)
	assert(chunk, parseError)
	local environment = setmetatable({
		game = gameMock,
		workspace = Workspace,
		script = module,
		require = loadModule,
		task = taskMock,
		os = {
			clock = function()
				return now
			end,
		},
		typeof = function(value)
			return if type(value) == "table" and value.ClassName ~= nil then "Instance" else typeof(value)
		end,
		Vector3 = { new = vector },
		RaycastParams = {
			new = function()
				return {}
			end,
		},
		Enum = { RaycastFilterType = { Exclude = "Exclude" } },
		warn = function() end,
	}, { __index = getfenv() })
	setfenv(chunk, environment)
	loaded[name] = chunk()
	return loaded[name]
end
local Inventory = loadModule(moduleFolder.InventoryService)
local Medical = loadModule(moduleFolder.MedicalService)
local Combat = loadModule(moduleFolder.CombatService)
local function character()
	local model = attach(Workspace, instance("Model", "Character"))
	local humanoid = attach(model, instance("Humanoid"))
	humanoid.Health = 100
	humanoid.MaxHealth = 100
	humanoid.WalkSpeed, humanoid.JumpPower, humanoid.JumpHeight, humanoid.AutoRotate = 16, 50, 7.2, true
	humanoid.Died = signal()
	local head = attach(model, instance("Part", "Head"))
	head.Position = vector(0, 5, 0)
	local root = attach(model, instance("Part", "HumanoidRootPart"))
	root.Position = vector(0, 3, 0)
	return model, humanoid, head
end
local player = { Parent = Players, UserId = 1, CharacterAdded = signal(), CharacterRemoving = signal() }
player.Character = character()
Players.list = { player }
Inventory.Start()
Medical.Start()
Combat.Start()
advance(0)
local function status()
	return assert(Medical.GetStatus(player))
end
local function request(payload)
	local count = #messages
	remote.OnServerEvent:Fire(player, payload)
	check(#messages == count + 1, "request must have one result")
	return messages[#messages].message
end
local function sameSnapshot(actual, expected)
	check(actual.character == expected.character, "snapshot belongs to current character")
	for _, key in ipairs({
		"health",
		"maxHealth",
		"wounds",
		"bleedRate",
		"incapacitated",
		"equippedWeaponId",
		"weaponName",
		"role",
	}) do
		check(actual[key] == expected[key], "snapshot field " .. key)
	end
	for id, weapon in pairs(expected.weapons) do
		for key, value in pairs(weapon) do
			check(actual.weapons[id][key] == value, "weapon field " .. id .. "." .. key)
		end
	end
	for id, count in pairs(expected.medicalItems) do
		check(actual.medicalItems[id] == count, "medical item " .. id)
	end
end

sameSnapshot(messages[#messages].message, status())
local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
humanoid.Health, humanoid.MaxHealth = 67, 150
check(status().health == 67 and status().maxHealth == 150, "native health/max health synchronize")
check(Medical.ApplyDamage(humanoid, 10), "damage is accepted")
check(humanoid.Health == 57, "damage uses current native health")
sameSnapshot(messages[#messages].message, status())
advance(1)
sameSnapshot(messages[#messages].message, status())
check(humanoid.Health == 56.5, "bleeding uses synchronized health")
humanoid.Health, humanoid.MaxHealth = 80, 120
advance(1)
check(
	humanoid.Health == 79.5 and status().maxHealth == 120,
	"bleeding preserves native regeneration and max health changes"
)
local treatment = request({ action = "treat", itemId = "Medkit", targetUserId = player.UserId })
check(treatment.ok and treatment.code == "treatment_started", "self treatment starts")
advance(2)
check(humanoid.Health > 100, "treatment applies to current native health")
local medicalPush = nil
for _, item in ipairs(messages) do
	if item.message.action == "medical_status" then
		medicalPush = item.message
	end
end
sameSnapshot(assert(medicalPush), status())
local shot = request({ action = "shoot", direction = { x = 0, y = 0, z = -1 } })
check(shot.ok and shot.code == "miss", "valid shot accepted")
check(
	#rays == 1 and rays[1].origin == player.Character:FindFirstChild("Head").Position,
	"server-owned head is ray origin"
)
check(rays[1].direction.Magnitude == 500, "server enforces weapon ray range")
sameSnapshot(shot.status, status())
local reloading = request({ action = "reload" })
check(reloading.ok and reloading.status.weapons.Rifle.isReloading, "reload result includes updated snapshot")
check(type(reloading.status.weapons.Rifle.reloadEndsAt) == "number", "reload includes server deadline")
check(Medical.ApplyDamage(humanoid, 200), "lethal damage incapacitates")
check(player.Character:GetAttribute("SierraIncapacitated") == true, "incapacitation attribute is set")
check(not status().weapons.Rifle.isReloading, "incapacitation cancels reload immediately")
local downedInventory = Inventory.GetInventory(player)
for _, payload in ipairs({
	{ action = "shoot", direction = { x = 0, y = 0, z = -1 } },
	{ action = "equip", weaponId = "Sidearm" },
	{ action = "reload" },
}) do
	local response = request(payload)
	check(
		response.ok == false and response.code == "attacker_unavailable",
		"incapacitated " .. payload.action .. " rejected"
	)
	check(
		Inventory.GetInventory(player).Weapons.Rifle.Magazine == downedInventory.Weapons.Rifle.Magazine,
		"rejection preserves ammo"
	)
end
check(#rays == 1, "rejected downed shot does not raycast")
advance(3)
check(status().weapons.Rifle.magazine == downedInventory.Weapons.Rifle.Magazine, "cancelled reload cannot finish")

local oldCharacter = player.Character
player.CharacterRemoving:Fire(oldCharacter)
player.Character = character()
player.CharacterAdded:Fire(player.Character)
advance(0)
check(status().character == player.Character and not status().incapacitated, "respawn starts current healthy snapshot")
local reload = request({ action = "reload" })
check(reload.ok, "reload starts after respawn")
local oldReloadCharacter = player.Character
advance(0.5)
local oldReloadHumanoid = oldReloadCharacter:FindFirstChildOfClass("Humanoid")
oldReloadHumanoid.Health = 0
oldReloadHumanoid.Died:Fire()
player.CharacterRemoving:Fire(oldReloadCharacter)
player.Character = character()
player.CharacterAdded:Fire(player.Character)
advance(0)
check(request({ action = "reload" }).ok, "new life can start a reload while old timer is pending")
advance(1.6)
check(status().weapons.Rifle.isReloading, "old reload timer cannot cancel new life reload")
advance(0.5)
check(
	status().weapons.Rifle.magazine == 30 and not status().weapons.Rifle.isReloading,
	"new life reload completes normally"
)
sameSnapshot(messages[#messages].message.status, status())
check(Inventory.ConsumeAmmo(player), "fixture consumes ammo before final death test")
check(request({ action = "reload" }).ok, "final reload starts")
local beforeDeath = Inventory.GetInventory(player).Weapons.Rifle.Magazine
local dyingHumanoid = player.Character:FindFirstChildOfClass("Humanoid")
dyingHumanoid.Health = 0
dyingHumanoid.Died:Fire()
advance(3)
check(Inventory.GetInventory(player).Weapons.Rifle.Magazine == beforeDeath, "reload cannot complete after death")
check(not Inventory.GetInventory(player).Weapons.Rifle.IsReloading, "death clears reload state")

Combat.Stop()
Medical.Stop()
Inventory.Stop()
print(string.format("Mobile runtime: %d checks passed", checks))
