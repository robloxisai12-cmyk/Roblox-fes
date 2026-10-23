--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PlayerDataService = require(script.Parent.PlayerDataService)
local SquadService = require(script.Parent.SquadService)
local LogisticsService = require(script.Parent.LogisticsService)
local RadioService = require(script.Parent.RadioService)
local MatchRules = require(script.Parent.MatchRules)

local configFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("config")
local config = require(configFolder:WaitForChild("MissionConfig") :: ModuleScript)
local mapConfig = require(configFolder:WaitForChild("MapConfig") :: ModuleScript)
local logisticsConfig = require(configFolder:WaitForChild("LogisticsConfig") :: ModuleScript)
local missionRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MissionRequest") :: RemoteEvent

local ZONES_FOLDER_NAME = "SierraDeGuardiaObjectives"

type ObjectiveZone = {
	Definition: any,
	Center: Vector3,
	Part: BasePart,
}

type RequestBucket = {
	LastRequestAt: number,
}

type MovementSample = {
	Character: Model,
	Position: Vector3,
	SampledAt: number,
}

local zones: { ObjectiveZone } = {}
local requestBuckets: { [Player]: RequestBucket } = {}
local movementSamples: { [Player]: MovementSample } = {}
local deliveryBaselines: { [string]: number } = {}
local connections: { RBXScriptConnection } = {}
local state = MatchRules.Create(config)
local isStarted = false
local worldFolder: Folder? = nil
local heartbeatConnection: RBXScriptConnection? = nil
local remoteConnection: RBXScriptConnection? = nil
local lastTickAt = 0
local lastUpdateAt = 0
local activeSquadNames: { string } = {}
local MatchService = {}

local function validateWorldConfiguration()
	if not MatchRules.ValidateConfig(config) then
		error("MatchService: invalid MissionConfig")
	end
	local points: { [string]: any } = {}
	for _, point in ipairs(logisticsConfig.SupplyPoints) do
		points[point.Id] = point
	end
	for _, objective in ipairs(config.Objectives) do
		if math.abs(objective.X) > mapConfig.Dimensions.Width / 2
			or math.abs(objective.Z) > mapConfig.Dimensions.Depth / 2
		then
			error(`MatchService: objective {objective.Id} is outside the generated map`)
		end
		if objective.Kind == "delivery" then
			local point = points[objective.PointId]
			if point == nil
				or point.Kind ~= "Delivery"
				or point.X ~= objective.X
				or point.Z ~= objective.Z
				or point.Stock[objective.ResourceId] == nil
			then
				error(`MatchService: objective {objective.Id} has an invalid logistics delivery point`)
			end
		end
	end
end

local function getGroundPosition(x: number, z: number): Vector3
	local result = Workspace:Raycast(
		Vector3.new(x, mapConfig.Dimensions.MaxHeight + 100, z),
		Vector3.new(0, -(mapConfig.Dimensions.MaxHeight + 200), 0),
		RaycastParams.new()
	)
	return Vector3.new(x, if result ~= nil then result.Position.Y else mapConfig.Dimensions.BaseHeight, z)
end

local function createZoneMarker(parent: Folder, definition: any): ObjectiveZone
	local center = getGroundPosition(definition.X, definition.Z)
	local marker = Instance.new("Part")
	marker.Name = definition.Id
	marker.Shape = Enum.PartType.Cylinder
	marker.Size = Vector3.new(0.25, definition.Radius * 2, definition.Radius * 2)
	marker.CFrame = CFrame.new(center + Vector3.new(0, 0.16, 0)) * CFrame.Angles(0, 0, math.rad(90))
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanTouch = false
	marker.CanQuery = false
	marker.Material = Enum.Material.Neon
	marker.Color = Color3.fromRGB(92, 151, 119)
	marker.Transparency = 0.78
	marker:SetAttribute("MissionObjectiveId", definition.Id)
	marker:SetAttribute("ObjectiveKind", definition.Kind)
	marker.Parent = parent

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ObjectiveLabel"
	billboard.Size = UDim2.fromOffset(210, 44)
	billboard.StudsOffset = Vector3.new(0, 5, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = marker

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(22, 29, 31)
	label.BackgroundTransparency = 0.15
	label.TextColor3 = Color3.fromRGB(245, 240, 220)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = definition.Name
	label.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label

	return {
		Definition = definition,
		Center = center,
		Part = marker,
	}
end

local function createWorld()
	local previous = Workspace:FindFirstChild(ZONES_FOLDER_NAME)
	if previous ~= nil then
		previous:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = ZONES_FOLDER_NAME
	folder.Parent = Workspace
	worldFolder = folder
	table.clear(zones)
	for _, definition in ipairs(config.Objectives) do
		table.insert(zones, createZoneMarker(folder, definition))
	end
end

local function getConnectedPlayerCount(): number
	local count = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if PlayerDataService.GetSession(player) ~= nil then
			count += 1
		end
	end
	return count
end

local function samplePlayerMovement(now: number): { [Player]: boolean }
	local validMovement: { [Player]: boolean } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
		local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
		if PlayerDataService.GetSession(player) ~= nil
			and character ~= nil
			and humanoid ~= nil
			and humanoid.Health > 0
			and root ~= nil
			and root:IsA("BasePart")
		then
			local sample = movementSamples[player]
			if sample == nil or sample.Character ~= character then
				movementSamples[player] = {
					Character = character,
					Position = root.Position,
					SampledAt = now,
				}
				validMovement[player] = false
			else
				local distance = Vector2.new(
					root.Position.X - sample.Position.X,
					root.Position.Z - sample.Position.Z
				).Magnitude
				local verticalDistance = math.abs(root.Position.Y - sample.Position.Y)
				local elapsed = math.max(0, now - sample.SampledAt)
				local plausible = MatchRules.IsMovementPlausible(
					distance,
					verticalDistance,
					elapsed,
					config.MaxObservedHorizontalSpeed,
					config.MaxObservedVerticalSpeed,
					config.MovementTolerance
				)
				sample.SampledAt = now
				if plausible then
					sample.Position = root.Position
				end
				validMovement[player] = plausible
			end
		else
			movementSamples[player] = nil
		end
	end
	return validMovement
end

local function getContributors(zone: ObjectiveZone, validMovement: { [Player]: boolean }): ({ number }, { string })
	local contributors = {}
	local squadNames: { [string]: boolean } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if PlayerDataService.GetSession(player) ~= nil and validMovement[player] == true then
			local character = player.Character
			local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
			local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
			if character ~= nil
				and humanoid ~= nil
				and humanoid.Health > 0
				and character:GetAttribute("SierraIncapacitated") ~= true
				and root ~= nil
				and root:IsA("BasePart")
			then
				local horizontalDistance = Vector2.new(root.Position.X - zone.Center.X, root.Position.Z - zone.Center.Z).Magnitude
				local verticalDistance = math.abs(root.Position.Y - zone.Center.Y)
				if horizontalDistance <= zone.Definition.Radius and verticalDistance <= 18 then
					table.insert(contributors, player.UserId)
					local squad = SquadService.GetPlayerSquad(player.UserId)
					if squad ~= nil then
						squadNames[squad.Name] = true
					end
				end
			end
		end
	end
	local names = {}
	for name in pairs(squadNames) do
		table.insert(names, name)
	end
	table.sort(names)
	return contributors, names
end

local function getDeliveredTotals(): { [string]: number }
	local totals = {}
	for _, objective in ipairs(config.Objectives) do
		if objective.Kind == "delivery" then
			totals[objective.Id] = LogisticsService.GetDeliveredAmount(objective.PointId, objective.ResourceId)
		end
	end
	return totals
end

local function captureDeliveryBaselines()
	table.clear(deliveryBaselines)
	for index, objective in ipairs(config.Objectives) do
		if objective.Kind == "delivery" then
			deliveryBaselines[objective.Id] =
				LogisticsService.GetDeliveredAmount(objective.PointId, objective.ResourceId)
			state.Objectives[index].DeliveryBaseline = deliveryBaselines[objective.Id]
		end
	end
end

local function settleMissionDeliveries()
	local deliveredTotals = getDeliveredTotals()
	for _, objective in ipairs(config.Objectives) do
		if objective.Kind == "delivery" then
			local amount = math.max(
				0,
				(deliveredTotals[objective.Id] or 0) - (deliveryBaselines[objective.Id] or 0)
			)
			if amount > 0
				and not LogisticsService.ConsumeDeliveredStock(objective.PointId, objective.ResourceId, amount)
			then
				warn(`MatchService: failed to consume mission delivery for {objective.Id}`)
			end
		end
	end
end

local function getSnapshot()
	if state == nil then
		return nil
	end
	local snapshot: { [string]: any } = MatchRules.Copy(state, os.clock())
	local objective = config.Objectives[state.ActiveObjectiveIndex]
	local squadNames = {}
	if state.Status == "active" and objective ~= nil and objective.Kind == "capture" then
		squadNames = table.clone(activeSquadNames)
	end
	snapshot.participatingSquads = squadNames
	return snapshot
end

local function sendState(player: Player?)
	local snapshot = getSnapshot()
	if snapshot == nil then
		return
	end
	local message = {
		action = "mission_state",
		state = snapshot,
	}
	if player ~= nil then
		missionRemote:FireClient(player, message)
	else
		missionRemote:FireAllClients(message)
	end
end

local function getAnnouncement(event: string?): string?
	if event == "preparation_started" then
		return "Preparacion iniciada. La partida comenzara pronto."
	elseif event == "match_started" then
		return "Partida activa. Aseguren el valle y completen los objetivos."
	elseif event == "objective_completed" then
		local previousObjective = state.Objectives[state.ActiveObjectiveIndex - 1]
		local nextObjective = state.Objectives[state.ActiveObjectiveIndex]
		return if nextObjective ~= nil
			then `{previousObjective.Name} completado. Siguiente objetivo: {nextObjective.Name}.`
			else `{previousObjective.Name} completado.`
	elseif event == "match_victory" then
		return "Victoria. Todos los objetivos de mision fueron completados."
	elseif event == "match_defeat" then
		return if state.Reason == "time_expired"
			then "Derrota. Se agoto el tiempo de la partida."
			else "Derrota. No hay suficientes jugadores para continuar."
	elseif event == "match_reset" then
		return "La mision se reinicio. Esperando jugadores."
	end
	return nil
end

local function processEvent(event: string?)
	if event == nil then
		return
	end
	local announcement = if config.RadioAnnouncements then getAnnouncement(event) else nil
	if announcement ~= nil then
		RadioService.BroadcastMissionUpdate(announcement)
	end
	sendState(nil)
end

local function handleRequest(player: Player, rawRequest: any, argumentCount: number)
	local now = os.clock()
	local bucket = requestBuckets[player]
	if bucket ~= nil and now - bucket.LastRequestAt < 1 then
		return
	end
	requestBuckets[player] = { LastRequestAt = now }
	local valid, validationError = MatchRules.ValidateRequest(rawRequest, argumentCount)
	if not valid then
		missionRemote:FireClient(player, {
			action = "mission_result",
			ok = false,
			code = validationError or "invalid_request",
		})
		return
	end
	sendState(player)
end

local function step(deltaTime: number)
	if state == nil then
		return
	end
	local now = os.clock()
	local validMovement = samplePlayerMovement(now)
	local playerCount = getConnectedPlayerCount()
	local changed, event = MatchRules.Step(state, playerCount, now, config)
	if event == "match_started" then
		captureDeliveryBaselines()
	elseif event == "match_defeat" then
		settleMissionDeliveries()
	elseif event == "match_reset" then
		table.clear(deliveryBaselines)
	end
	if changed then
		processEvent(event)
	end

	if state.Status == "active" then
		local objective = config.Objectives[state.ActiveObjectiveIndex]
		local contributors = {}
		if objective ~= nil and objective.Kind == "capture" then
			local squadNames: { string }
			contributors, squadNames = getContributors(zones[state.ActiveObjectiveIndex], validMovement)
			activeSquadNames = squadNames
		else
			activeSquadNames = {}
		end
		local progressChanged, objectiveEvent = MatchRules.AdvanceObjective(
			state,
			math.min(deltaTime, 1),
			contributors,
			getDeliveredTotals(),
			config.MaxCaptureContributors,
			config.ResultSeconds,
			now
		)
		if progressChanged then
			if objectiveEvent == "match_victory" then
				settleMissionDeliveries()
			end
			processEvent(objectiveEvent)
		end
	else
		table.clear(activeSquadNames)
	end

	if now - lastUpdateAt >= config.StateUpdateSeconds then
		lastUpdateAt = now
		sendState(nil)
	end
end

function MatchService.Start()
	if isStarted then
		return
	end
	validateWorldConfiguration()
	state = MatchRules.Create(config)
	if state == nil then
		error("MatchService: could not create initial match state")
	end
	isStarted = true
	createWorld()
	lastTickAt = os.clock()
	lastUpdateAt = lastTickAt

	remoteConnection = missionRemote.OnServerEvent:Connect(function(player: Player, ...: any)
		local arguments = table.pack(...)
		local ok, failure = pcall(handleRequest, player, arguments[1], arguments.n)
		if not ok then
			warn(`MatchService request failed for user {player.UserId}: {failure}`)
			missionRemote:FireClient(player, {
				action = "mission_result",
				ok = false,
				code = "internal_error",
			})
		end
	end)
	table.insert(connections, Players.PlayerRemoving:Connect(function(player)
		requestBuckets[player] = nil
	end))
	heartbeatConnection = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local deltaTime = math.max(0, now - lastTickAt)
		lastTickAt = now
		step(deltaTime)
	end)
	sendState(nil)
end

function MatchService.Stop()
	if not isStarted then
		return
	end
	isStarted = false
	if heartbeatConnection ~= nil then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
	if remoteConnection ~= nil then
		remoteConnection:Disconnect()
		remoteConnection = nil
	end
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(requestBuckets)
	table.clear(movementSamples)
	table.clear(deliveryBaselines)
	table.clear(zones)
	table.clear(activeSquadNames)
	if worldFolder ~= nil then
		worldFolder:Destroy()
		worldFolder = nil
	end
	state = MatchRules.Create(config)
	lastTickAt = 0
	lastUpdateAt = 0
end

return table.freeze(MatchService)
