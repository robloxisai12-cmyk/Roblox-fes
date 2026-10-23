--!strict

type Request = {
	action: string,
	name: string?,
	companyId: string?,
	squadId: string?,
	targetUserId: number?,
	role: string?,
}

local fieldsByAction = {
	list = { action = true },
	create = { action = true, name = true, companyId = true },
	join = { action = true, squadId = true },
	leave = { action = true },
	disband = { action = true, squadId = true },
	setRole = { action = true, targetUserId = true, role = true },
}

local SquadRequestRules = {}

function SquadRequestRules.Validate(
	value: any,
	assignableRoles: { read [string]: boolean }
): (Request?, string?)
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return nil, "invalid_request"
	end

	local action = value.action
	local allowedFields = if type(action) == "string" then fieldsByAction[action] else nil
	if allowedFields == nil then
		return nil, "invalid_action"
	end
	for key in pairs(value) do
		if type(key) ~= "string" or allowedFields[key] ~= true then
			return nil, "unexpected_field"
		end
	end

	local clean: Request = { action = action }
	if action == "create" then
		if type(value.name) ~= "string" or #value.name > 64 then
			return nil, "invalid_name"
		end
		clean.name = value.name
		if value.companyId ~= nil then
			if type(value.companyId) ~= "string" or not string.match(value.companyId, "^[%w_-]+$") then
				return nil, "invalid_company"
			end
			clean.companyId = value.companyId
		end
	elseif action == "join" or action == "disband" then
		if type(value.squadId) ~= "string" or not string.match(value.squadId, "^SQD%-%d+$") then
			return nil, "invalid_squad"
		end
		clean.squadId = value.squadId
	elseif action == "setRole" then
		local targetUserId = value.targetUserId
		if type(targetUserId) ~= "number"
			or targetUserId ~= targetUserId
			or targetUserId <= 0
			or targetUserId > 2147483647
			or targetUserId % 1 ~= 0
		then
			return nil, "invalid_target"
		end
		if type(value.role) ~= "string" or assignableRoles[value.role] ~= true then
			return nil, "invalid_role"
		end
		clean.targetUserId = targetUserId
		clean.role = value.role
	end

	return clean, nil
end

function SquadRequestRules.ValidateCall(
	value: any,
	argumentCount: number,
	assignableRoles: { read [string]: boolean }
): (Request?, string?)
	if argumentCount ~= 1 then
		return nil, "invalid_argument_count"
	end

	return SquadRequestRules.Validate(value, assignableRoles)
end

return table.freeze(SquadRequestRules)