--!strict
local Cleanup = require(script.Parent.Cleanup)
local Rules = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("HUDRules"))
local VehicleControls = {}
VehicleControls.__index = VehicleControls

function VehicleControls.new(services: any, adapter: any, view: any, config: any)
	return setmetatable({
		Services = services,
		Adapter = adapter,
		View = view,
		Config = config,
		Scope = Cleanup.new(),
		DriveScope = Cleanup.new(),
		Started = false,
		Held = {},
		Touches = {},
		DrivingId = nil,
		Elapsed = 0,
		CameraMode = "Default",
		CameraSaved = nil,
	}, VehicleControls)
end

function VehicleControls:Reset()
	self.Held, self.Touches = {}, {}
end

function VehicleControls:Send(id: string, throttle: number, steer: number)
	self.Services.CombatRemote:FireServer({
		action = "logistics",
		operation = "drive",
		vehicleId = id,
		throttle = throttle,
		steer = steer,
	})
end

function VehicleControls:RestoreCamera()
	local saved = self.CameraSaved
	if saved ~= nil then
		-- Respect changes made by another camera owner while this mode was active.
		if self.Services.Player.CameraMode == Enum.CameraMode.LockFirstPerson then
			self.Services.Player.CameraMode = saved
		end
	end
	self.CameraSaved, self.CameraMode = nil, "Default"
end

function VehicleControls:ToggleCamera()
	if not self.Adapter:CanControl() then
		return
	end
	if self.CameraSaved ~= nil then
		self:RestoreCamera()
	else
		self.CameraSaved = self.Services.Player.CameraMode
		self.Services.Player.CameraMode = Enum.CameraMode.LockFirstPerson
		self.CameraMode = "FirstPerson"
	end
end

function VehicleControls:SetDriving(id: string?)
	if self.DrivingId == id then
		return
	end
	if self.DrivingId ~= nil then
		self:Send(self.DrivingId, 0, 0)
	end
	self.DriveScope:Clean()
	self:Reset()
	self:RestoreCamera()
	self.DrivingId, self.Elapsed = id, self.Config.DriveSendInterval
	if id == nil then
		return
	end
	-- Custom pedals/steering replace only the native touch overlay while seated.
	-- Walking controls and the player's original visibility return on exit.
	local function hideTouchGui(gui: any)
		if gui.Name ~= "TouchGui" or not gui:IsA("ScreenGui") then
			return
		end
		local enabled = gui.Enabled
		gui.Enabled = false
		self.DriveScope:Add(function()
			if gui.Parent ~= nil and gui.Enabled == false then
				gui.Enabled = enabled
			end
		end)
	end
	local nativeTouch = self.Services.PlayerGui:FindFirstChild("TouchGui")
	if nativeTouch ~= nil then
		hideTouchGui(nativeTouch)
	end
	self.DriveScope:Connect(self.Services.PlayerGui.ChildAdded, hideTouchGui)
	local cas = self.Services.ContextActionService
	local keys = {
		Forward = { Enum.KeyCode.W, Enum.KeyCode.Up },
		Reverse = { Enum.KeyCode.S, Enum.KeyCode.Down },
		Left = { Enum.KeyCode.A, Enum.KeyCode.Left },
		Right = { Enum.KeyCode.D, Enum.KeyCode.Right },
		Brake = { Enum.KeyCode.Space },
	}
	for name, codes in pairs(keys) do
		local action = "RobloxFesDrive" .. name
		cas:BindActionAtPriority(action, function(_, state, input)
			if not self.Adapter:CanControl() then
				self:Reset()
				return Enum.ContextActionResult.Pass
			end
			self.Held[name .. tostring(input.KeyCode)] = state == Enum.UserInputState.Begin
				or state == Enum.UserInputState.Change
			return Enum.ContextActionResult.Sink
		end, false, 3000, table.unpack(codes))
		self.DriveScope:Add(function()
			cas:UnbindAction(action)
		end)
	end
end

function VehicleControls:Axes(): (number, number)
	local held = {}
	for token, down in pairs(self.Held) do
		if down then
			for _, name in ipairs({ "Forward", "Reverse", "Left", "Right", "Brake" }) do
				if string.sub(token, 1, #name) == name then
					held[name] = true
				end
			end
		end
	end
	for _, name in pairs(self.Touches) do
		held[name] = true
	end
	return Rules.Axes(held)
end

function VehicleControls:Start()
	if self.Started then
		return
	end
	self.Started = true
	local s = self.Services
	for name, button in pairs(self.View.DriveButtons) do
		self.Scope:Connect(button.InputBegan, function(input)
			if
				self.Adapter:CanControl()
				and (
					input.UserInputType == Enum.UserInputType.Touch
					or input.UserInputType == Enum.UserInputType.MouseButton1
				)
			then
				self.Touches[input] = name
			end
		end)
	end
	self.Scope:Connect(s.UserInputService.InputChanged, function(input)
		if input.UserInputState == Enum.UserInputState.Cancel or input.UserInputState == Enum.UserInputState.End then
			self.Touches[input] = nil
		end
	end)
	self.Scope:Connect(s.UserInputService.InputEnded, function(input)
		self.Touches[input] = nil
	end)
	self.Scope:Connect(s.UserInputService.WindowFocusReleased, function()
		self:Reset()
		if self.DrivingId ~= nil then
			self:Send(self.DrivingId, 0, 0)
		end
	end)
	self.Scope:Connect(self.View.Exit.Activated, function()
		if self.Adapter:CanControl() and self.DrivingId ~= nil then
			self:Reset()
			self:Send(self.DrivingId, 0, 0)
			s.CombatRemote:FireServer({ action = "logistics", operation = "exit_vehicle", vehicleId = self.DrivingId })
		end
	end)
	self.Scope:Connect(self.View.Camera.Activated, function()
		self:ToggleCamera()
	end)
	self.Scope:Connect(s.Heartbeat, function(dt)
		self.Adapter:Reconcile()
		self:SetDriving(self.Adapter.VehicleId)
		if self.DrivingId == nil then
			return
		end
		if not self.Adapter:CanControl() then
			self:Reset()
		end
		self.Elapsed += dt
		if self.Elapsed >= self.Config.DriveSendInterval then
			self.Elapsed = 0
			local throttle, steer = self:Axes()
			self:Send(self.DrivingId, throttle, steer)
		end
	end)
end

function VehicleControls:Stop()
	self.Started = false
	self:SetDriving(nil)
	self.Scope:Clean()
end
return VehicleControls
