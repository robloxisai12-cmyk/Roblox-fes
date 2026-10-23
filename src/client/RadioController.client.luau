--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local radioRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RadioRequest") :: RemoteEvent
local playerGui = player:WaitForChild("PlayerGui")

local screen = Instance.new("ScreenGui")
screen.Name = "SierraRadio"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = false
screen.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "RadioPanel"
panel.AnchorPoint = Vector2.new(1, 1)
panel.Position = UDim2.new(1, -12, 1, -12)
panel.Size = UDim2.new(0.92, 0, 0, 326)
panel.BackgroundColor3 = Color3.fromRGB(22, 29, 31)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Parent = screen

local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MinSize = Vector2.new(260, 220)
sizeLimit.MaxSize = Vector2.new(390, 326)
sizeLimit.Parent = panel

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 8)
panelCorner.Parent = panel

local header = Instance.new("TextLabel")
header.Name = "Header"
header.Position = UDim2.new(0, 12, 0, 8)
header.Size = UDim2.new(0.42, 0, 0, 26)
header.BackgroundTransparency = 1
header.Font = Enum.Font.GothamBold
header.Text = "RADIO TACTICA"
header.TextColor3 = Color3.fromRGB(236, 240, 225)
header.TextSize = 15
header.TextXAlignment = Enum.TextXAlignment.Left
header.Parent = panel

local signalLabel = Instance.new("TextLabel")
signalLabel.Name = "Signal"
signalLabel.Position = UDim2.new(0.43, 0, 0, 8)
signalLabel.Size = UDim2.new(0.53, -8, 0, 26)
signalLabel.BackgroundTransparency = 1
signalLabel.Font = Enum.Font.GothamSemibold
signalLabel.Text = "Enlace: sincronizando"
signalLabel.TextColor3 = Color3.fromRGB(202, 213, 180)
signalLabel.TextSize = 13
signalLabel.TextXAlignment = Enum.TextXAlignment.Right
signalLabel.TextTruncate = Enum.TextTruncate.AtEnd
signalLabel.Parent = panel

local channelButton = Instance.new("TextButton")
channelButton.Name = "Channel"
channelButton.Position = UDim2.new(0, 10, 0, 40)
channelButton.Size = UDim2.new(1, -20, 0, 44)
channelButton.BackgroundColor3 = Color3.fromRGB(50, 78, 72)
channelButton.BorderSizePixel = 0
channelButton.Font = Enum.Font.GothamSemibold
channelButton.Text = "Canal: General  [cambiar]"
channelButton.TextColor3 = Color3.fromRGB(255, 255, 245)
channelButton.TextSize = 14
channelButton.TextTruncate = Enum.TextTruncate.AtEnd
channelButton.Parent = panel

local channelCorner = Instance.new("UICorner")
channelCorner.CornerRadius = UDim.new(0, 6)
channelCorner.Parent = channelButton

local messageList = Instance.new("ScrollingFrame")
messageList.Name = "Messages"
messageList.Position = UDim2.new(0, 10, 0, 92)
messageList.Size = UDim2.new(1, -20, 1, -152)
messageList.BackgroundColor3 = Color3.fromRGB(14, 19, 20)
messageList.BackgroundTransparency = 0.08
messageList.BorderSizePixel = 0
messageList.CanvasSize = UDim2.new()
messageList.ScrollBarThickness = 6
messageList.ScrollingDirection = Enum.ScrollingDirection.Y
messageList.AutomaticCanvasSize = Enum.AutomaticSize.Y
messageList.Parent = panel

local listCorner = Instance.new("UICorner")
listCorner.CornerRadius = UDim.new(0, 6)
listCorner.Parent = messageList

local listPadding = Instance.new("UIPadding")
listPadding.PaddingTop = UDim.new(0, 6)
listPadding.PaddingBottom = UDim.new(0, 6)
listPadding.PaddingLeft = UDim.new(0, 7)
listPadding.PaddingRight = UDim.new(0, 7)
listPadding.Parent = messageList

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 4)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = messageList

local messageInput = Instance.new("TextBox")
messageInput.Name = "MessageInput"
messageInput.Position = UDim2.new(0, 10, 1, -54)
messageInput.Size = UDim2.new(1, -92, 0, 44)
messageInput.BackgroundColor3 = Color3.fromRGB(40, 48, 47)
messageInput.BorderSizePixel = 0
messageInput.ClearTextOnFocus = false
messageInput.Font = Enum.Font.Gotham
messageInput.PlaceholderText = "Escribe un mensaje..."
messageInput.Text = ""
messageInput.TextColor3 = Color3.fromRGB(245, 245, 235)
messageInput.PlaceholderColor3 = Color3.fromRGB(175, 181, 169)
messageInput.TextSize = 15
messageInput.TextXAlignment = Enum.TextXAlignment.Left
messageInput.Parent = panel

local inputCorner = Instance.new("UICorner")
inputCorner.CornerRadius = UDim.new(0, 6)
inputCorner.Parent = messageInput

local inputPadding = Instance.new("UIPadding")
inputPadding.PaddingLeft = UDim.new(0, 8)
inputPadding.PaddingRight = UDim.new(0, 8)
inputPadding.Parent = messageInput

local sendButton = Instance.new("TextButton")
sendButton.Name = "Send"
sendButton.Position = UDim2.new(1, -74, 1, -54)
sendButton.Size = UDim2.new(0, 64, 0, 44)
sendButton.BackgroundColor3 = Color3.fromRGB(79, 110, 74)
sendButton.BorderSizePixel = 0
sendButton.Font = Enum.Font.GothamBold
sendButton.Text = "ENVIAR"
sendButton.TextColor3 = Color3.fromRGB(255, 255, 245)
sendButton.TextSize = 12
sendButton.Parent = panel

local sendCorner = Instance.new("UICorner")
sendCorner.CornerRadius = UDim.new(0, 6)
sendCorner.Parent = sendButton

local channels: { { id: string, name: string } } = {}
local selectedChannelId = "general"
local messageOrder = 0
local maxVisibleMessages = 30

local function updatePanelSize()
	local camera = Workspace.CurrentCamera
	local viewportHeight = if camera ~= nil then camera.ViewportSize.Y else 720
	panel.Size = UDim2.new(0.92, 0, 0, math.min(326, math.max(220, viewportHeight - 24)))
end

local function setSignal(status: string, percent: number)
	signalLabel.Text = string.format("Enlace: %s  %d%%", status, percent)
end

local function displayError(code: string)
	local labels = {
		radio_unavailable = "No tienes radio de campaña.",
		channel_unauthorized = "No tienes permiso para ese canal.",
		rate_limited = "Espera antes de transmitir otra vez.",
		no_signal = "No hay una radio aliada dentro del alcance.",
		character_unavailable = "No puedes transmitir en este estado.",
		filter_unavailable = "No se pudo filtrar el mensaje; intenta de nuevo.",
		message_too_long = "El mensaje excede el limite permitido.",
		empty_message = "Escribe un mensaje antes de transmitir.",
	}
	signalLabel.Text = labels[code] or `Radio: {code}`
end

local function renderChannel()
	local selectedName = "General"
	for _, channel in ipairs(channels) do
		if channel.id == selectedChannelId then
			selectedName = channel.name
			break
		end
	end
	channelButton.Text = `Canal: {selectedName}  [cambiar]`
end

local function addMessage(message: any)
	local label = Instance.new("TextLabel")
	label.Name = "Message"
	label.LayoutOrder = messageOrder
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.Text = string.format("[%s] %s: %s", message.channelName, message.senderName, message.text)
	label.TextColor3 = Color3.fromRGB(232, 235, 224)
	label.TextSize = 14
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.RichText = false
	label.Parent = messageList
	messageOrder += 1

	local labels = {}
	for _, child in ipairs(messageList:GetChildren()) do
		if child:IsA("TextLabel") and child.Name == "Message" then
			table.insert(labels, child)
		end
	end
	while #labels > maxVisibleMessages do
		local oldest = table.remove(labels, 1)
		oldest:Destroy()
	end
	task.defer(function()
		messageList.CanvasPosition = Vector2.new(0, math.max(0, listLayout.AbsoluteContentSize.Y))
	end)
end

local function requestSend()
	if messageInput.Text == "" then
		displayError("empty_message")
		return
	end
	radioRemote:FireServer({
		action = "send",
		text = messageInput.Text,
	})
	messageInput.Text = ""
	messageInput:ReleaseFocus()
end

channelButton.Activated:Connect(function()
	if #channels == 0 then
		return
	end
	local selectedIndex = 0
	for index, channel in ipairs(channels) do
		if channel.id == selectedChannelId then
			selectedIndex = index
			break
		end
	end
	local nextIndex = selectedIndex % #channels + 1
	radioRemote:FireServer({
		action = "select",
		channelId = channels[nextIndex].id,
	})
end)

sendButton.Activated:Connect(requestSend)
messageInput.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		requestSend()
	end
end)

radioRemote.OnClientEvent:Connect(function(response: any)
	if type(response) ~= "table" then
		return
	end
	if response.action == "state" then
		if type(response.channels) == "table" then
			channels = response.channels
		end
		if type(response.selectedChannelId) == "string" then
			selectedChannelId = response.selectedChannelId
		end
		if type(response.signalPercent) == "number" and type(response.signalStatus) == "string" then
			setSignal(response.signalStatus, response.signalPercent)
		end
		renderChannel()
	elseif response.action == "message" then
		if type(response.channelName) == "string"
			and type(response.senderName) == "string"
			and type(response.text) == "string"
		then
			addMessage(response)
			setSignal(if response.signalPercent >= 70 then "Buena"
				elseif response.signalPercent >= 30 then "Media"
				elseif response.signalPercent > 0 then "Debil"
				else "Sin enlace", response.signalPercent)
		end
	elseif response.action == "mission_update" and type(response.text) == "string" then
		addMessage({
			channelName = "MISION",
			senderName = "Mando",
			text = response.text,
		})
	elseif response.action == "result" and response.ok == false and type(response.code) == "string" then
		displayError(response.code)
	end
end)

radioRemote:FireServer({
	action = "state",
})

updatePanelSize()
local camera = Workspace.CurrentCamera
if camera ~= nil then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(updatePanelSize)
end
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	local currentCamera = Workspace.CurrentCamera
	if currentCamera ~= nil then
		currentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updatePanelSize)
		updatePanelSize()
	end
end)

task.spawn(function()
	while screen.Parent ~= nil do
		task.wait(3)
		radioRemote:FireServer({
			action = "state",
		})
	end
end)
