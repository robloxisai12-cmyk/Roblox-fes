--!strict
local Cleanup = require(script.Parent.Cleanup)
local Rules = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("HUDRules"))

local GameAdapter = {}
GameAdapter.__index = GameAdapter

function GameAdapter.new(services: any)
	return setmetatable({
		Services = services,
		Scope = Cleanup.new(),
		CharacterScope = Cleanup.new(),
		HumanoidScope = Cleanup.new(),
		Started = false,
		Character = nil,
		Humanoid = nil,
		VehicleId = nil,
		Mode = "unavailable",
		Medical = nil,
		Inventory = nil,
		Vehicles = {},
		NearestVehicleId = nil,
		PollElapsed = 0,
	}, GameAdapter)
end

function GameAdapter:Reconcile()
	local character, humanoid = self.Character, self.Humanoid
	local alive = character ~= nil and character.Parent ~= nil and humanoid ~= nil and humanoid.Health > 0
	local seat = if alive then humanoid.SeatPart else nil
	local model = if seat ~= nil then seat.Parent else nil
	local pickup = seat ~= nil
		and seat:IsA("VehicleSeat")
		and seat.Name == "DriverSeat"
		and model ~= nil
		and model:IsA("Model")
		and model.Parent ~= nil
		and model:GetAttribute("VehicleCategory") == "Pickup"
		and type(model:GetAttribute("VehicleId")) == "string"
		and seat.Occupant == humanoid
	local down = character ~= nil
		and (
			character:GetAttribute("SierraIncapacitated") == true
			or (self.Medical ~= nil and self.Medical.incapacitated == true)
		)
	self.Mode = Rules.Mode(alive, down, pickup == true)
	self.VehicleId = if self.Mode == "driving" then model:GetAttribute("VehicleId") else nil
end

function GameAdapter:BindCharacter(character: any)
	self.CharacterScope:Clean()
	self.HumanoidScope:Clean()
	self.Character, self.Humanoid = character, nil
	self.Medical, self.Inventory = nil, nil
	self.Vehicles, self.NearestVehicleId = {}, nil
	self:Reconcile()
	if character == nil then
		return
	end
	local function bindHumanoid()
		if self.Character ~= character then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid == nil or self.Humanoid == humanoid then
			return
		end
		self.HumanoidScope:Clean()
		self.Humanoid = humanoid
		for _, property in ipairs({ "Health", "MaxHealth", "SeatPart" }) do
			self.HumanoidScope:Connect(humanoid:GetPropertyChangedSignal(property), function()
				self:Reconcile()
			end)
		end
		self.HumanoidScope:Connect(humanoid.Died, function()
			self:Reconcile()
		end)
		self:Reconcile()
		self.Services.CombatRemote:FireServer({ action = "medical_status" })
		self.Services.CombatRemote:FireServer({ action = "logistics", operation = "status" })
	end
	self.CharacterScope:Connect(character.ChildAdded, bindHumanoid)
	self.CharacterScope:Connect(character.AncestryChanged, function()
		self:Reconcile()
	end)
	self.CharacterScope:Connect(character:GetAttributeChangedSignal("SierraIncapacitated"), function()
		self:Reconcile()
	end)
	bindHumanoid()
end

function GameAdapter:Receive(message: any)
	if type(message) ~= "table" then
		return
	end
	local token = message.character or (type(message.status) == "table" and message.status.character)
	if token ~= nil and token ~= self.Character then
		return
	end
	local medical = if message.action == "medical_status" then message else message.status
	if type(medical) == "table" and medical.character == self.Character and self.Character ~= nil then
		self.Medical = medical
	end
	if message.ok and message.action == "logistics_status" and token == self.Character and self.Character ~= nil then
		self.Inventory = message.inventory
		self.NearestVehicleId = message.nearestVehicleId
		self.Vehicles = {}
		for _, vehicle in ipairs(message.vehicles or {}) do
			self.Vehicles[vehicle.id] = vehicle
		end
	elseif message.ok and type(message.vehicle) == "table" and token == self.Character and self.Character ~= nil then
		self.Vehicles[message.vehicle.id] = message.vehicle
	end
	-- Remote snapshots supply telemetry; only the current native seat selects driving mode.
	self:Reconcile()
end

function GameAdapter:IsBlocked(): boolean
	local s = self.Services
	return s.PlayerGui:GetAttribute("SierraMenuOpen") == true
		or s.GuiService.MenuIsOpen
		or s.UserInputService:GetFocusedTextBox() ~= nil
end

function GameAdapter:CanControl(): boolean
	self:Reconcile()
	return self.Mode == "driving" and not self:IsBlocked()
end

function GameAdapter:GetState()
	self:Reconcile()
	local root = if self.Character ~= nil then self.Character:FindFirstChild("HumanoidRootPart") else nil
	local seat = if self.Humanoid ~= nil then self.Humanoid.SeatPart else nil
	return {
		Mode = self.Mode,
		Character = self.Character,
		Humanoid = self.Humanoid,
		Health = if self.Humanoid ~= nil then self.Humanoid.Health else nil,
		MaxHealth = if self.Humanoid ~= nil then self.Humanoid.MaxHealth else nil,
		Medical = self.Medical,
		Inventory = self.Inventory,
		VehicleId = self.VehicleId,
		Vehicle = self.Vehicles[self.VehicleId],
		NearestVehicleId = self.NearestVehicleId,
		Root = root,
		Seat = seat,
		Blocked = self:IsBlocked(),
	}
end

function GameAdapter:Start()
	if self.Started then
		return
	end
	self.Started = true
	self.PollElapsed = 0
	local s = self.Services
	self.Scope:Connect(s.Player.CharacterAdded, function(character)
		self:BindCharacter(character)
	end)
	self.Scope:Connect(s.Player.CharacterRemoving, function(character)
		if self.Character == character then
			self:BindCharacter(nil)
		end
	end)
	self.Scope:Connect(s.CombatRemote.OnClientEvent, function(message)
		self:Receive(message)
	end)
	self.Scope:Connect(s.Heartbeat, function(dt)
		self:Reconcile()
		self.PollElapsed += dt
		if self.PollElapsed >= 3 then
			self.PollElapsed = 0
			if self.Character ~= nil then
				s.CombatRemote:FireServer({ action = "logistics", operation = "status" })
			end
		end
	end)
	self:BindCharacter(s.Player.Character)
end

function GameAdapter:Stop()
	self.Started = false
	self.Scope:Clean()
	self:BindCharacter(nil)
end

return GameAdapter
