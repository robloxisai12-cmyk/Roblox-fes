--!strict
local Cleanup = require(script.Parent.Cleanup)
local GameAdapter = require(script.Parent.GameAdapter)
local HUDView = require(script.Parent.HUDView)
local VehicleControls = require(script.Parent.VehicleControls)
local HUDController = {}
HUDController.__index = HUDController

function HUDController.new(services: any, screen: ScreenGui, openPanel: (string) -> ())
	return setmetatable({
		Services = services,
		Screen = screen,
		OpenPanel = openPanel,
		Scope = Cleanup.new(),
		CameraScope = Cleanup.new(),
		Adapter = GameAdapter.new(services),
		Started = false,
	}, HUDController)
end

function HUDController:Layout()
	local camera = self.Services.Workspace.CurrentCamera
	local size = self.Screen.AbsoluteSize
	-- ScreenGui respects device safe areas; AbsoluteSize is the usable area.
	if size.X <= 0 or size.Y <= 0 then
		size = if camera ~= nil then camera.ViewportSize else Vector2.new(1280, 720)
	end
	self.View:Layout(size.X, size.Y, self.Services.UserInputService.TouchEnabled)
end

function HUDController:Start()
	if self.Started then
		return
	end
	self.Started = true
	local s = self.Services
	self.View = HUDView.new(self.Screen, s.MapConfig, s.LogisticsConfig)
	self.Controls = VehicleControls.new(s, self.Adapter, self.View, s.LogisticsConfig)
	self.Adapter:Start()
	self.Controls:Start()
	local function bindCamera()
		self.CameraScope:Clean()
		local camera = s.Workspace.CurrentCamera
		if camera ~= nil then
			self.CameraScope:Connect(camera:GetPropertyChangedSignal("ViewportSize"), function()
				self:Layout()
			end)
		end
		self:Layout()
	end
	self.Scope:Connect(s.Workspace:GetPropertyChangedSignal("CurrentCamera"), bindCamera)
	self.Scope:Connect(self.Screen:GetPropertyChangedSignal("AbsoluteSize"), function()
		self:Layout()
	end)
	bindCamera()
	for id, control in pairs(self.View.NavButtons) do
		self.Scope:Connect(control.Activated, function()
			self.OpenPanel(id)
		end)
	end
	for id, control in pairs(self.View.Weapons) do
		self.Scope:Connect(control.Activated, function()
			local state = self.Adapter:GetState()
			if state.Mode == "walking" and not state.Blocked then
				s.CombatRemote:FireServer({ action = "equip", weaponId = id })
			end
		end)
	end
	local chatWindow = s.TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
	local chatInput = s.TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
	if chatWindow ~= nil and chatInput ~= nil and s.TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
		local previous = {
			Enabled = chatWindow.Enabled,
			HorizontalAlignment = chatWindow.HorizontalAlignment,
			VerticalAlignment = chatWindow.VerticalAlignment,
			WidthScale = chatWindow.WidthScale,
			HeightScale = chatWindow.HeightScale,
			InputEnabled = chatInput.Enabled,
		}
		chatWindow.HorizontalAlignment = Enum.HorizontalAlignment.Left
		chatWindow.VerticalAlignment = Enum.VerticalAlignment.Top
		chatWindow.WidthScale = 0.7
		chatWindow.HeightScale = 0.6
		chatWindow.Enabled = not self.View.Profile.Compact
		-- Use the platform input, filtering and permissions; never relay user chat through a custom remote.
		self.Scope:Connect(self.View.Chat.Activated, function()
			chatWindow.Enabled = not chatWindow.Enabled
			self.View.ChatExpanded = chatWindow.Enabled
			chatInput.Enabled = true
		end)
		self.Scope:Add(function()
			chatWindow.Enabled = previous.Enabled
			chatWindow.HorizontalAlignment, chatWindow.VerticalAlignment =
				previous.HorizontalAlignment, previous.VerticalAlignment
			chatWindow.WidthScale, chatWindow.HeightScale = previous.WidthScale, previous.HeightScale
			chatInput.Enabled = previous.InputEnabled
		end)
	else
		self.Scope:Connect(self.View.Chat.Activated, function()
			local ok = pcall(function()
				s.StarterGui:SetCore("ChatActive", true)
			end)
			if not ok then
				self.View.Notice.Text = "Chat nativo no disponible en esta sesion"
			end
		end)
	end
	local noticeRemaining = 0
	self.Scope:Connect(s.CombatRemote.OnClientEvent, function(message)
		if type(message) ~= "table" or message.action ~= "logistics_result" then
			return
		end
		local token = message.character or (type(message.status) == "table" and message.status.character)
		if token ~= nil and token ~= s.Player.Character then
			return
		end
		local messages = {
			driver_unauthorized = "Tu rol no tiene permiso para conducir",
			out_of_range = "Acercate al vehiculo",
			vehicle_occupied = "Vehiculo ocupado",
			player_unavailable = "No puedes realizar esta accion en tu estado actual",
			entered_vehicle = if s.UserInputService.TouchEnabled
				then "Usa los pedales y la direccion; Salir para bajar"
				else "Conduccion: WASD / flechas · Espacio frena · B sale",
			exited_vehicle = "Has salido del vehiculo",
			refueled = "Combustible repuesto",
		}
		self.View.Notice.Text = messages[message.code]
			or (if message.ok then "Accion logistica completada" else `Logistica: {message.code or "accion rechazada"}`)
		noticeRemaining = 4
	end)
	local elapsed = 0
	self.Scope:Connect(s.Heartbeat, function(dt)
		if noticeRemaining > 0 then
			noticeRemaining = math.max(0, noticeRemaining - dt)
			if noticeRemaining == 0 then
				self.View.Notice.Text = ""
			end
		end
		elapsed += dt
		if elapsed < 0.1 then
			return
		end
		elapsed = 0
		self.View.FirstPerson = self.Controls.CameraMode == "FirstPerson"
		self.View:Render(self.Adapter:GetState())
	end)
	self.View:Render(self.Adapter:GetState())
end

function HUDController:Stop()
	if not self.Started then
		return
	end
	self.Started = false
	self.Scope:Clean()
	self.CameraScope:Clean()
	self.Controls:Stop()
	self.Adapter:Stop()
	self.View:Destroy()
end
return HUDController
