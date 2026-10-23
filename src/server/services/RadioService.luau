--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local PlayerDataService = require(script.Parent.PlayerDataService)
local SquadService = require(script.Parent.SquadService)
local InventoryService = require(script.Parent.InventoryService)
local RadioRules = require(script.Parent.RadioRules)

local shared = ReplicatedStorage:WaitForChild("Shared")
local configFolder = shared:WaitForChild("config")
local inventoryConfig = require(configFolder:WaitForChild("InventoryConfig") :: ModuleScript)
local config = require(configFolder:WaitForChild("RadioConfig") :: ModuleScript)
local radioRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RadioRequest") :: RemoteEvent

type RateLimitBucket = {
	WindowStartedAt: number,
	Count: number,
}

local requestBuckets: { [Player]: RateLimitBucket } = {}
local messageBuckets: { [Player]: RateLimitBucket } = {}
local selectedChannels: { [Player]: string } = {}
local connections: { RBXScriptConnection } = {}
local remoteConnection: RBXScriptConnection? = nil
local isStarted = false

local RadioService = {}

if not RadioRules.IsValidConfig(config)
	or type(inventoryConfig.Radio) ~= "table"
	or type(inventoryConfig.Radio.ItemId) ~= "string"
then
	error("RadioService: invalid radio or inventory configuration")
end

local function errorResponse(code: string)
	return {
		action = "result",
		ok = false,
		code = code,
	}
end

local function getPlayerSquad(player: Player)
	return SquadService.GetPlayerSquad(player.UserId)
end

local function getChannel(
	player: Player,
	channelId: string
): ({ id: string, name: string, range: number }?, string?)
	local generalChannel = config.GeneralChannel
	if channelId == generalChannel.Id then
		return {
			id = generalChannel.Id,
			name = generalChannel.DisplayName,
			range = generalChannel.Range,
		}, nil
	end

	local squad = getPlayerSquad(player)
	if squad == nil or channelId ~= RadioRules.GetSquadChannelId(squad.Id) then
		return nil, nil
	end
	return {
		id = channelId,
		name = `{config.SquadChannel.DisplayNamePrefix}: {squad.Name}`,
		range = config.SquadChannel.Range,
	}, squad.Id
end

local function getCharacterRoot(player: Player): BasePart?
	local character = player.Character
	if character == nil then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
		return nil
	end
	return root
end

local function isRadioAvailable(player: Player): boolean
	return player.Parent == Players
		and PlayerDataService.GetSession(player) ~= nil
		and InventoryService.HasRadio(player)
end

local function hasChannelAccess(player: Player, channelId: string, squadId: string?): boolean
	local squad = getPlayerSquad(player)
	local playerSquadId = if squad ~= nil then squad.Id else nil
	return RadioRules.CanAccessChannel(channelId, config.GeneralChannel.Id, playerSquadId)
		and (squadId == nil or playerSquadId == squadId)
end

local function getRecipients(
	sender: Player,
	channelId: string,
	squadId: string?,
	range: number
): ({ Player }, number, { [Player]: number })
	local senderRoot = getCharacterRoot(sender)
	if senderRoot == nil then
		return {}, 0, {}
	end

	local recipients = {}
	local signalStrengths: { [Player]: number } = {}
	local strongestSignal = 0
	for _, candidate in ipairs(Players:GetPlayers()) do
		if candidate ~= sender and isRadioAvailable(candidate) and hasChannelAccess(candidate, channelId, squadId) then
			local candidateRoot = getCharacterRoot(candidate)
			if candidateRoot ~= nil then
				local distance = (senderRoot.Position - candidateRoot.Position).Magnitude
				if RadioRules.IsWithinRange(distance, range) then
					local signalStrength = RadioRules.GetSignalStrength(distance, range)
					table.insert(recipients, candidate)
					signalStrengths[candidate] = signalStrength
					strongestSignal = math.max(strongestSignal, signalStrength)
				end
			end
		end
	end
	return recipients, strongestSignal, signalStrengths
end

local function getAuthorizedChannels(player: Player)
	local channels = {
		{
			id = config.GeneralChannel.Id,
			name = config.GeneralChannel.DisplayName,
		},
	}
	local squad = getPlayerSquad(player)
	if squad ~= nil then
		table.insert(channels, {
			id = RadioRules.GetSquadChannelId(squad.Id),
			name = `{config.SquadChannel.DisplayNamePrefix}: {squad.Name}`,
		})
	end
	return channels
end

local function getSignal(player: Player, channelId: string)
	local channel, squadId = getChannel(player, channelId)
	if channel == nil then
		return 0, 0
	end
	local _, strength = getRecipients(player, channelId, squadId, channel.range)
	return math.floor(strength * 100 + 0.5), channel.range
end

local function sendState(player: Player)
	local squad = getPlayerSquad(player)
	local selected = selectedChannels[player] or config.GeneralChannel.Id
	if not hasChannelAccess(player, selected, nil) then
		selected = config.GeneralChannel.Id
		selectedChannels[player] = selected
	end
	local signalPercent, range = getSignal(player, selected)
	radioRemote:FireClient(player, {
		action = "state",
		channels = getAuthorizedChannels(player),
		selectedChannelId = selected,
		signalPercent = signalPercent,
		signalRange = range,
		signalStatus = if signalPercent >= 70 then "Buena"
			elseif signalPercent >= 30 then "Media"
			elseif signalPercent > 0 then "Debil"
			else "Sin enlace",
		inSquad = squad ~= nil,
	})
end

local function takeToken(
	buckets: { [Player]: RateLimitBucket },
	player: Player,
	windowSeconds: number,
	maxRequests: number
): boolean
	local allowed, bucket = RadioRules.TakeRateLimitToken(buckets[player], os.clock(), windowSeconds, maxRequests)
	if not allowed then
		return false
	end
	buckets[player] = bucket
	return true
end

local function filterForBroadcast(player: Player, text: string): string?
	local success, filterResult = pcall(function()
		return TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
	end)
	if not success then
		warn(`RadioService: text filtering failed for user {player.UserId}: {filterResult}`)
		return nil
	end

	local broadcastSuccess, filteredText = pcall(function()
		return filterResult:GetNonChatStringForBroadcastAsync()
	end)
	if not broadcastSuccess then
		warn(`RadioService: broadcast text filtering failed for user {player.UserId}: {filteredText}`)
		return nil
	end
	if type(filteredText) ~= "string" or filteredText == "" then
		warn(`RadioService: text filtering returned invalid content for user {player.UserId}`)
		return nil
	end
	return filteredText
end

local function processRequest(player: Player, rawRequest: any, argumentCount: number)
	if not takeToken(
		requestBuckets,
		player,
		config.RequestWindowSeconds,
		config.MaxRequestsPerWindow
	) then
		radioRemote:FireClient(player, errorResponse("rate_limited"))
		return
	end
	if not isRadioAvailable(player) then
		radioRemote:FireClient(player, errorResponse("radio_unavailable"))
		return
	end

	local request, validationError =
		RadioRules.ValidateCall(rawRequest, argumentCount, config.MaxMessageBytes)
	if request == nil then
		radioRemote:FireClient(player, errorResponse(validationError or "invalid_request"))
		return
	end

	if request.action == "state" then
		sendState(player)
		return
	elseif request.action == "select" then
		local channel, squadId = getChannel(player, request.channelId)
		if channel == nil or not hasChannelAccess(player, request.channelId, squadId) then
			radioRemote:FireClient(player, errorResponse("channel_unauthorized"))
			return
		end
		selectedChannels[player] = request.channelId
		sendState(player)
		return
	end

	local channelId = selectedChannels[player] or config.GeneralChannel.Id
	local channel, squadId = getChannel(player, channelId)
	if channel == nil or not hasChannelAccess(player, channelId, squadId) then
		selectedChannels[player] = config.GeneralChannel.Id
		radioRemote:FireClient(player, errorResponse("channel_unauthorized"))
		return
	end
	if not takeToken(
		messageBuckets,
		player,
		config.MessageWindowSeconds,
		config.MaxMessagesPerWindow
	) then
		radioRemote:FireClient(player, errorResponse("rate_limited"))
		return
	end
	if getCharacterRoot(player) == nil then
		radioRemote:FireClient(player, errorResponse("character_unavailable"))
		return
	end

	local recipients, signalStrength, recipientSignalStrengths =
		getRecipients(player, channelId, squadId, channel.range)
	if #recipients == 0 then
		radioRemote:FireClient(player, errorResponse("no_signal"))
		return
	end

	local filteredText = filterForBroadcast(player, request.text)
	if filteredText == nil then
		radioRemote:FireClient(player, errorResponse("filter_unavailable"))
		return
	end

	local session = PlayerDataService.GetSession(player)
	if session == nil then
		radioRemote:FireClient(player, errorResponse("session_unavailable"))
		return
	end
	local message = {
		action = "message",
		channelId = channelId,
		channelName = channel.name,
		senderUserId = player.UserId,
		senderName = session.DisplayName,
		text = filteredText,
		sentAt = os.time(),
		signalPercent = math.floor(signalStrength * 100 + 0.5),
	}
	for _, recipient in ipairs(recipients) do
		local recipientMessage = table.clone(message)
		recipientMessage.signalPercent = math.floor(recipientSignalStrengths[recipient] * 100 + 0.5)
		radioRemote:FireClient(recipient, recipientMessage)
	end
	radioRemote:FireClient(player, message)
end

function RadioService.Start()
	if isStarted then
		return
	end
	isStarted = true
	remoteConnection = radioRemote.OnServerEvent:Connect(function(player: Player, ...: any)
		local arguments = table.pack(...)
		local success, failure = pcall(processRequest, player, arguments[1], arguments.n)
		if not success then
			warn(`RadioService request failed for user {player.UserId}: {failure}`)
			radioRemote:FireClient(player, errorResponse("internal_error"))
		end
	end)
	table.insert(connections, Players.PlayerRemoving:Connect(function(player)
		requestBuckets[player] = nil
		messageBuckets[player] = nil
		selectedChannels[player] = nil
	end))
end

function RadioService.Stop()
	if not isStarted then
		return
	end
	isStarted = false
	if remoteConnection ~= nil then
		remoteConnection:Disconnect()
		remoteConnection = nil
	end
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(requestBuckets)
	table.clear(messageBuckets)
	table.clear(selectedChannels)
end

function RadioService.BroadcastMissionUpdate(text: string)
	if not isStarted or type(text) ~= "string" or text == "" then
		return
	end
	local message = {
		action = "mission_update",
		text = string.sub(text, 1, 180),
	}
	for _, player in ipairs(Players:GetPlayers()) do
		if isRadioAvailable(player) then
			radioRemote:FireClient(player, message)
		end
	end
end

return table.freeze(RadioService)
