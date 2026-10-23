--!strict

type ObjectiveDefinition = {
	Id: string,
	Name: string,
	Description: string,
	Kind: string,
	X: number,
	Z: number,
	Radius: number,
	RequiredProgress: number?,
	PointId: string?,
	ResourceId: string?,
	RequiredAmount: number?,
}

type ObjectiveState = {
	Id: string,
	Name: string,
	Description: string,
	Kind: string,
	PointId: string?,
	ResourceId: string?,
	Status: string,
	Progress: number,
	RequiredProgress: number,
	Contributors: { [number]: boolean },
	DeliveryBaseline: number,
}

type MatchState = {
	Status: string,
	Round: number,
	StartedAt: number?,
	EndsAt: number?,
	Reason: string?,
	ActiveObjectiveIndex: number,
	Objectives: { ObjectiveState },
}

local MatchRules = {}

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function isPositiveInteger(value: any): boolean
	return isFiniteNumber(value) and value > 0 and value % 1 == 0
end

function MatchRules.ValidateConfig(config: any): boolean
	if type(config) ~= "table"
		or not isPositiveInteger(config.MinimumPlayers)
		or not isFiniteNumber(config.PreparationSeconds)
		or config.PreparationSeconds < 0
		or not isFiniteNumber(config.MatchDurationSeconds)
		or config.MatchDurationSeconds <= 0
		or not isFiniteNumber(config.ResultSeconds)
		or config.ResultSeconds < 0
		or not isFiniteNumber(config.CleanupSeconds)
		or config.CleanupSeconds < 0
		or not isFiniteNumber(config.StateUpdateSeconds)
		or config.StateUpdateSeconds <= 0
		or not isPositiveInteger(config.MaxCaptureContributors)
		or not isFiniteNumber(config.MaxObservedHorizontalSpeed)
		or config.MaxObservedHorizontalSpeed <= 0
		or not isFiniteNumber(config.MaxObservedVerticalSpeed)
		or config.MaxObservedVerticalSpeed <= 0
		or not isFiniteNumber(config.MovementTolerance)
		or config.MovementTolerance < 0
		or type(config.RadioAnnouncements) ~= "boolean"
		or type(config.Objectives) ~= "table"
		or #config.Objectives == 0
	then
		return false
	end

	local ids: { [string]: boolean } = {}
	local deliveryPairs: { [string]: boolean } = {}
	local objectiveDefinitions = config.Objectives :: { ObjectiveDefinition }
	for _, objective in ipairs(objectiveDefinitions) do
		if type(objective) ~= "table"
			or type(objective.Id) ~= "string"
			or objective.Id == ""
			or #objective.Id > 64
			or ids[objective.Id] == true
			or type(objective.Name) ~= "string"
			or objective.Name == ""
			or type(objective.Description) ~= "string"
			or objective.Description == ""
			or (objective.Kind ~= "capture" and objective.Kind ~= "delivery")
			or not isFiniteNumber(objective.X)
			or not isFiniteNumber(objective.Z)
			or not isFiniteNumber(objective.Radius)
			or objective.Radius <= 0
		then
			return false
		end
		ids[objective.Id] = true

		if objective.Kind == "capture" then
			if not isFiniteNumber(objective.RequiredProgress) or (objective.RequiredProgress :: number) <= 0 then
				return false
			end
		elseif type(objective.PointId) ~= "string"
			or objective.PointId == ""
			or type(objective.ResourceId) ~= "string"
			or objective.ResourceId == ""
			or not isPositiveInteger(objective.RequiredAmount)
		then
			return false
		elseif deliveryPairs[objective.PointId .. "\0" .. objective.ResourceId] == true then
			return false
		else
			deliveryPairs[objective.PointId .. "\0" .. objective.ResourceId] = true
		end
	end
	return true
end

function MatchRules.Create(config: any): MatchState?
	if not MatchRules.ValidateConfig(config) then
		return nil
	end

	local objectives: { ObjectiveState } = {}
	for _, definition in ipairs(config.Objectives :: { ObjectiveDefinition }) do
		local objectiveState: ObjectiveState = {
			Id = definition.Id,
			Name = definition.Name,
			Description = definition.Description,
			Kind = definition.Kind,
			PointId = definition.PointId,
			ResourceId = definition.ResourceId,
			Status = "locked",
			Progress = 0,
			RequiredProgress = if definition.Kind == "capture"
				then definition.RequiredProgress :: number
				else definition.RequiredAmount :: number,
			Contributors = {} :: { [number]: boolean },
			DeliveryBaseline = 0,
		}
		table.insert(objectives, objectiveState)
	end

	return {
		Status = "waiting",
		Round = 0,
		StartedAt = nil,
		EndsAt = nil,
		Reason = nil,
		ActiveObjectiveIndex = 1,
		Objectives = objectives,
	}
end

function MatchRules.ValidateRequest(request: any, argumentCount: number): (boolean, string?)
	if argumentCount ~= 1 then
		return false, "invalid_argument_count"
	end
	if type(request) ~= "table" or getmetatable(request) ~= nil then
		return false, "invalid_request"
	end
	for key in pairs(request) do
		if key ~= "action" then
			return false, "unexpected_field"
		end
	end
	if request.action ~= "state" then
		return false, "invalid_action"
	end
	return true, nil
end

function MatchRules.IsMovementPlausible(
	horizontalDistance: number,
	verticalDistance: number,
	elapsedSeconds: number,
	maxHorizontalSpeed: number,
	maxVerticalSpeed: number,
	tolerance: number
): boolean
	return isFiniteNumber(horizontalDistance)
		and isFiniteNumber(verticalDistance)
		and isFiniteNumber(elapsedSeconds)
		and isFiniteNumber(maxHorizontalSpeed)
		and isFiniteNumber(maxVerticalSpeed)
		and isFiniteNumber(tolerance)
		and horizontalDistance >= 0
		and verticalDistance >= 0
		and elapsedSeconds >= 0
		and maxHorizontalSpeed > 0
		and maxVerticalSpeed > 0
		and tolerance >= 0
		and horizontalDistance <= (maxHorizontalSpeed + tolerance) * elapsedSeconds
		and verticalDistance <= (maxVerticalSpeed + tolerance) * elapsedSeconds
end

local function setStatus(state: MatchState, status: string, reason: string?, endsAt: number?)
	state.Status = status
	state.Reason = reason
	state.EndsAt = endsAt
end

function MatchRules.Step(
	state: MatchState,
	playerCount: number,
	now: number,
	config: any
): (boolean, string?)
	if not isFiniteNumber(playerCount) or playerCount < 0 or playerCount % 1 ~= 0 or not isFiniteNumber(now) then
		return false, "invalid_input"
	end

	if state.Status == "waiting" then
		if playerCount >= config.MinimumPlayers then
			state.StartedAt = nil
			setStatus(state, "preparation", nil, now + config.PreparationSeconds)
			return true, "preparation_started"
		end
	elseif state.Status == "preparation" then
		if playerCount < config.MinimumPlayers then
			state.StartedAt = nil
			setStatus(state, "waiting", "players_unavailable", nil)
			return true, "preparation_cancelled"
		elseif state.EndsAt ~= nil and now >= state.EndsAt then
			state.Round += 1
			state.StartedAt = now
			setStatus(state, "active", nil, now + config.MatchDurationSeconds)
			state.ActiveObjectiveIndex = 1
			state.Objectives[1].Status = "active"
			return true, "match_started"
		end
	elseif state.Status == "active" then
		if playerCount < config.MinimumPlayers then
			setStatus(state, "defeat", "players_unavailable", now + config.ResultSeconds)
			return true, "match_defeat"
		elseif state.EndsAt ~= nil and now >= state.EndsAt then
			setStatus(state, "defeat", "time_expired", now + config.ResultSeconds)
			return true, "match_defeat"
		end
	elseif state.Status == "victory" or state.Status == "defeat" then
		if state.EndsAt ~= nil and now >= state.EndsAt then
			setStatus(state, "ended", state.Reason, now + config.CleanupSeconds)
			return true, "cleanup_started"
		end
	elseif state.Status == "ended" and state.EndsAt ~= nil and now >= state.EndsAt then
		state.StartedAt = nil
		state.ActiveObjectiveIndex = 1
		for _, objective in ipairs(state.Objectives) do
			objective.Status = "locked"
			objective.Progress = 0
			objective.Contributors = {}
			objective.DeliveryBaseline = 0
		end
		setStatus(state, "waiting", nil, nil)
		return true, "match_reset"
	end
	return false, nil
end

function MatchRules.AdvanceObjective(
	state: MatchState,
	deltaTime: number,
	contributorUserIds: { number },
	deliveredTotals: { [string]: number },
	maxCaptureContributors: number,
	resultSeconds: number,
	now: number
): (boolean, string?)
	if state.Status ~= "active"
		or not isFiniteNumber(deltaTime)
		or deltaTime < 0
		or type(deliveredTotals) ~= "table"
		or not isPositiveInteger(maxCaptureContributors)
		or not isFiniteNumber(resultSeconds)
		or resultSeconds < 0
		or not isFiniteNumber(now)
	then
		return false, nil
	end
	for _, amount in pairs(deliveredTotals) do
		if not isFiniteNumber(amount) or amount < 0 then
			return false, nil
		end
	end

	local objective = state.Objectives[state.ActiveObjectiveIndex]
	if objective == nil then
		return false, nil
	end

	local completed = false
	if objective.Kind == "capture" then
		local contributorCount = 0
		local seenContributors: { [number]: boolean } = {}
		for _, userId in ipairs(contributorUserIds) do
			if isPositiveInteger(userId) and seenContributors[userId] ~= true then
				seenContributors[userId] = true
				objective.Contributors[userId] = true
				contributorCount += 1
			end
		end
		if contributorCount > 0 then
			objective.Progress = math.min(
				objective.RequiredProgress,
				objective.Progress + deltaTime * math.min(contributorCount, maxCaptureContributors)
			)
		end
		completed = objective.Progress >= objective.RequiredProgress
	else
		local deliveredTotal = deliveredTotals[objective.Id] or 0
		objective.Progress = math.min(objective.RequiredProgress, math.max(0, deliveredTotal - objective.DeliveryBaseline))
		completed = objective.Progress >= objective.RequiredProgress
	end

	if not completed then
		return false, nil
	end

	objective.Status = "complete"
	state.ActiveObjectiveIndex += 1
	local nextObjective = state.Objectives[state.ActiveObjectiveIndex]
	if nextObjective ~= nil then
		nextObjective.Status = "active"
		return true, "objective_completed"
	end

	setStatus(state, "victory", "objectives_complete", now + resultSeconds)
	return true, "match_victory"
end

function MatchRules.Copy(state: MatchState, now: number?)
	local objectives = {}
	for _, objective in ipairs(state.Objectives) do
		table.insert(objectives, {
			id = objective.Id,
			name = objective.Name,
			description = objective.Description,
			kind = objective.Kind,
			status = objective.Status,
			progress = objective.Progress,
			requiredProgress = objective.RequiredProgress,
			contributorCount = (function()
				local count = 0
				for _ in pairs(objective.Contributors) do
					count += 1
				end
				return count
			end)(),
		})
	end
	return {
		status = state.Status,
		round = state.Round,
		secondsRemaining = if now ~= nil and state.EndsAt ~= nil
			then math.max(0, math.ceil(state.EndsAt - now))
			else nil,
		reason = state.Reason,
		objectives = objectives,
	}
end

return table.freeze(MatchRules)
