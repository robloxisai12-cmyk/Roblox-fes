--!strict

type ValidRequest =
	{ action: "state" }
	| { action: "select", channelId: string }
	| { action: "send", text: string }

type RateLimitBucket = {
	WindowStartedAt: number,
	Count: number,
}

local RadioRules = {}

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function hasOnlyFields(value: { [any]: any }, allowedFields: { [string]: boolean }): boolean
	for key in pairs(value) do
		if type(key) ~= "string" or allowedFields[key] ~= true then
			return false
		end
	end
	return true
end

local function trim(value: string): string
	return (string.gsub(value, "^%s*(.-)%s*$", "%1"))
end

function RadioRules.ValidateRequest(value: any, argumentCount: number, maxMessageBytes: number): (ValidRequest?, string?)
	if argumentCount ~= 1 then
		return nil, "invalid_argument_count"
	end
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return nil, "invalid_request"
	end

	local action = value.action
	if action == "state" then
		if not hasOnlyFields(value, { action = true }) then
			return nil, "unexpected_field"
		end
		return { action = "state" }, nil
	elseif action == "select" then
		if not hasOnlyFields(value, { action = true, channelId = true }) then
			return nil, "unexpected_field"
		end
		local channelId = value.channelId
		if type(channelId) ~= "string" or #channelId < 1 or #channelId > 64 then
			return nil, "invalid_channel"
		end
		return { action = "select", channelId = channelId }, nil
	elseif action == "send" then
		if not hasOnlyFields(value, { action = true, text = true }) then
			return nil, "unexpected_field"
		end
		local text = value.text
		if type(text) ~= "string" or #text > maxMessageBytes then
			return nil, "message_too_long"
		end
		local normalizedText = trim(text)
		if normalizedText == "" then
			return nil, "empty_message"
		end
		return { action = "send", text = normalizedText }, nil
	end

	return nil, "invalid_action"
end

function RadioRules.ValidateCall(
	value: any,
	argumentCount: number,
	maxMessageBytes: number
): (ValidRequest?, string?)
	if not isFiniteNumber(maxMessageBytes) or maxMessageBytes < 1 or maxMessageBytes % 1 ~= 0 then
		return nil, "invalid_configuration"
	end
	return RadioRules.ValidateRequest(value, argumentCount, maxMessageBytes)
end

function RadioRules.IsValidConfig(config: any): boolean
	if type(config) ~= "table"
		or type(config.GeneralChannel) ~= "table"
		or type(config.SquadChannel) ~= "table"
		or type(config.GeneralChannel.Id) ~= "string"
		or config.GeneralChannel.Id == ""
		or type(config.GeneralChannel.DisplayName) ~= "string"
		or config.GeneralChannel.DisplayName == ""
		or not isFiniteNumber(config.GeneralChannel.Range)
		or config.GeneralChannel.Range <= 0
		or not isFiniteNumber(config.SquadChannel.Range)
		or config.SquadChannel.Range <= 0
		or type(config.SquadChannel.DisplayNamePrefix) ~= "string"
		or config.SquadChannel.DisplayNamePrefix == ""
		or not isFiniteNumber(config.MaxMessageBytes)
		or config.MaxMessageBytes < 1
		or config.MaxMessageBytes % 1 ~= 0
		or not isFiniteNumber(config.RequestWindowSeconds)
		or config.RequestWindowSeconds <= 0
		or not isFiniteNumber(config.MaxRequestsPerWindow)
		or config.MaxRequestsPerWindow < 1
		or config.MaxRequestsPerWindow % 1 ~= 0
		or not isFiniteNumber(config.MessageWindowSeconds)
		or config.MessageWindowSeconds <= 0
		or not isFiniteNumber(config.MaxMessagesPerWindow)
		or config.MaxMessagesPerWindow < 1
		or config.MaxMessagesPerWindow % 1 ~= 0
	then
		return false
	end
	return true
end

function RadioRules.GetSquadChannelId(squadId: string): string
	return `squad/{squadId}`
end

function RadioRules.CanAccessChannel(channelId: string, generalChannelId: string, squadId: string?): boolean
	return channelId == generalChannelId
		or (squadId ~= nil and channelId == RadioRules.GetSquadChannelId(squadId))
end

function RadioRules.IsWithinRange(distance: number, range: number): boolean
	return isFiniteNumber(distance) and isFiniteNumber(range) and distance >= 0 and range > 0 and distance <= range
end

function RadioRules.GetSignalStrength(distance: number, range: number): number
	if not RadioRules.IsWithinRange(distance, range) then
		return 0
	end
	return math.max(0.01, math.clamp(1 - distance / range, 0, 1))
end

function RadioRules.TakeRateLimitToken(
	bucket: RateLimitBucket?,
	now: number,
	windowSeconds: number,
	maxRequests: number
): (boolean, RateLimitBucket?)
	if not isFiniteNumber(now)
		or not isFiniteNumber(windowSeconds)
		or windowSeconds <= 0
		or not isFiniteNumber(maxRequests)
		or maxRequests < 1
		or maxRequests % 1 ~= 0
	then
		return false, bucket
	end
	if bucket == nil or now < bucket.WindowStartedAt or now - bucket.WindowStartedAt >= windowSeconds then
		return true, {
			WindowStartedAt = now,
			Count = 1,
		}
	end
	if bucket.Count >= maxRequests then
		return false, bucket
	end
	return true, {
		WindowStartedAt = bucket.WindowStartedAt,
		Count = bucket.Count + 1,
	}
end

return table.freeze(RadioRules)
