--!strict

type CompanyDefinition = {
	Id: string,
	Name: string,
}

type Configuration = {
	Companies: { CompanyDefinition },
	AssignableSquadRoles: { [string]: boolean },
	MaxSquadsPerCompany: number,
	MaxMembersPerSquad: number,
	MinSquadNameLength: number,
	MaxSquadNameLength: number,
}

type SquadData = {
	Id: string,
	Name: string,
	CompanyId: string,
	LeaderUserId: number,
	MemberUserIds: { number },
	MemberRoles: { [number]: string },
}

type OperationResult = {
	Ok: boolean,
	Code: string,
	Squad: SquadData?,
	AffectedUserIds: { number },
}

type Registry = {
	_config: Configuration,
	_companies: { [string]: CompanyDefinition },
	_squads: { [string]: SquadData },
	_playerSquads: { [number]: string },
	_nextId: number,
	CreateSquad: (Registry, number, string, string, boolean) -> OperationResult,
	JoinSquad: (Registry, number, string, boolean) -> OperationResult,
	LeaveSquad: (Registry, number, boolean) -> OperationResult,
	DisbandSquad: (Registry, number, string, boolean) -> OperationResult,
	AssignRole: (Registry, number, number, string, boolean) -> OperationResult,
	GetPlayerSquad: (Registry, number) -> SquadData?,
	GetPlayerRole: (Registry, number) -> string?,
	GetCompanySquadCount: (Registry, string) -> number,
	ListSquads: (Registry) -> { SquadData },
}

local RegistryMethods: any = {}
RegistryMethods.__index = RegistryMethods

local function isValidUserId(userId: number): boolean
	return type(userId) == "number"
		and userId > 0
		and userId <= 2147483647
		and userId % 1 == 0
end

local function copySquad(squad: SquadData): SquadData
	return {
		Id = squad.Id,
		Name = squad.Name,
		CompanyId = squad.CompanyId,
		LeaderUserId = squad.LeaderUserId,
		MemberUserIds = table.clone(squad.MemberUserIds),
		MemberRoles = table.clone(squad.MemberRoles),
	}
end

local function failure(code: string): OperationResult
	return {
		Ok = false,
		Code = code,
		Squad = nil,
		AffectedUserIds = {},
	}
end

local function success(code: string, squad: SquadData?, affectedUserIds: { number }?): OperationResult
	return {
		Ok = true,
		Code = code,
		Squad = if squad then copySquad(squad) else nil,
		AffectedUserIds = affectedUserIds or {},
	}
end

local function cleanName(name: string): string
	return (string.gsub(name, "^%s*(.-)%s*$", "%1"))
end

local function countCompanySquads(self: Registry, companyId: string): number
	local count = 0
	for _, squad in pairs(self._squads) do
		if squad.CompanyId == companyId then
			count += 1
		end
	end
	return count
end

function RegistryMethods.CreateSquad(
	self: Registry,
	userId: number,
	name: string,
	companyId: string,
	authorized: boolean
): OperationResult
	if not authorized then
		return failure("permission_denied")
	end
	if not isValidUserId(userId) then
		return failure("invalid_player")
	end
	if self._playerSquads[userId] ~= nil then
		return failure("already_in_squad")
	end
	if type(name) ~= "string" then
		return failure("invalid_name")
	end
	local normalizedName = cleanName(name)
	if #normalizedName < self._config.MinSquadNameLength
		or #normalizedName > self._config.MaxSquadNameLength
	then
		return failure("invalid_name")
	end
	if type(companyId) ~= "string" or self._companies[companyId] == nil then
		return failure("invalid_company")
	end
	if countCompanySquads(self, companyId) >= self._config.MaxSquadsPerCompany then
		return failure("squad_limit")
	end

	local squadId = string.format("SQD-%04d", self._nextId)
	self._nextId += 1
	local squad: SquadData = {
		Id = squadId,
		Name = normalizedName,
		CompanyId = companyId,
		LeaderUserId = userId,
		MemberUserIds = { userId },
		MemberRoles = { [userId] = "SquadLeader" },
	}

	self._squads[squadId] = squad
	self._playerSquads[userId] = squadId
	return success("created", squad, { userId })
end

function RegistryMethods.JoinSquad(
	self: Registry,
	userId: number,
	squadId: string,
	authorized: boolean
): OperationResult
	if not authorized then
		return failure("permission_denied")
	end
	if not isValidUserId(userId) then
		return failure("invalid_player")
	end
	if type(squadId) ~= "string" or #squadId > 32 then
		return failure("invalid_squad")
	end
	if self._playerSquads[userId] ~= nil then
		return failure("already_in_squad")
	end

	local squad = self._squads[squadId]
	if squad == nil then
		return failure("squad_not_found")
	end
	if #squad.MemberUserIds >= self._config.MaxMembersPerSquad then
		return failure("squad_full")
	end

	table.insert(squad.MemberUserIds, userId)
	squad.MemberRoles[userId] = "Rifleman"
	self._playerSquads[userId] = squadId
	return success("joined", squad, { userId })
end

function RegistryMethods.LeaveSquad(
	self: Registry,
	userId: number,
	authorized: boolean
): OperationResult
	if not authorized then
		return failure("permission_denied")
	end
	if not isValidUserId(userId) then
		return failure("invalid_player")
	end

	local squadId = self._playerSquads[userId]
	local squad = if squadId then self._squads[squadId] else nil
	if squad == nil then
		return failure("not_in_squad")
	end

	for index, memberUserId in ipairs(squad.MemberUserIds) do
		if memberUserId == userId then
			table.remove(squad.MemberUserIds, index)
			break
		end
	end
	squad.MemberRoles[userId] = nil
	self._playerSquads[userId] = nil

	local affected = { userId }
	if #squad.MemberUserIds == 0 then
		self._squads[squad.Id] = nil
		return success("left_and_disbanded", nil, affected)
	end

	if squad.LeaderUserId == userId then
		local newLeaderUserId = squad.MemberUserIds[1]
		squad.LeaderUserId = newLeaderUserId
		squad.MemberRoles[newLeaderUserId] = "SquadLeader"
		table.insert(affected, newLeaderUserId)
	end

	return success("left", squad, affected)
end

function RegistryMethods.DisbandSquad(
	self: Registry,
	userId: number,
	squadId: string,
	canDisbandAny: boolean
): OperationResult
	if not isValidUserId(userId) then
		return failure("invalid_player")
	end
	if type(squadId) ~= "string" or #squadId > 32 then
		return failure("invalid_squad")
	end

	local squad = self._squads[squadId]
	if squad == nil then
		return failure("squad_not_found")
	end
	if squad.LeaderUserId ~= userId and not canDisbandAny then
		return failure("permission_denied")
	end

	local affected = table.clone(squad.MemberUserIds)
	for _, memberUserId in ipairs(affected) do
		self._playerSquads[memberUserId] = nil
	end
	self._squads[squadId] = nil
	return success("disbanded", nil, affected)
end

function RegistryMethods.AssignRole(
	self: Registry,
	actorUserId: number,
	targetUserId: number,
	role: string,
	authorized: boolean
): OperationResult
	if not authorized then
		return failure("permission_denied")
	end
	if not isValidUserId(actorUserId) or not isValidUserId(targetUserId) then
		return failure("invalid_player")
	end
	if type(role) ~= "string" or self._config.AssignableSquadRoles[role] ~= true then
		return failure("invalid_role")
	end

	local squadId = self._playerSquads[actorUserId]
	local squad = if squadId then self._squads[squadId] else nil
	if squad == nil or squad.LeaderUserId ~= actorUserId then
		return failure("permission_denied")
	end
	if self._playerSquads[targetUserId] ~= squadId then
		return failure("target_not_member")
	end

	squad.MemberRoles[targetUserId] = role
	return success("role_assigned", squad, { targetUserId })
end

function RegistryMethods.GetPlayerSquad(self: Registry, userId: number): SquadData?
	local squadId = self._playerSquads[userId]
	local squad = if squadId then self._squads[squadId] else nil
	return if squad then copySquad(squad) else nil
end

function RegistryMethods.GetPlayerRole(self: Registry, userId: number): string?
	local squadId = self._playerSquads[userId]
	local squad = if squadId then self._squads[squadId] else nil
	return if squad then squad.MemberRoles[userId] else nil
end

function RegistryMethods.GetCompanySquadCount(self: Registry, companyId: string): number
	return countCompanySquads(self, companyId)
end

function RegistryMethods.ListSquads(self: Registry): { SquadData }
	local squads: { SquadData } = {}
	for _, squad in pairs(self._squads) do
		table.insert(squads, copySquad(squad))
	end
	table.sort(squads, function(left: SquadData, right: SquadData)
		return left.Id < right.Id
	end)
	return squads
end

local SquadRegistry = {}

function SquadRegistry.new(config: Configuration): Registry
	local companies: { [string]: CompanyDefinition } = {}
	for _, company in ipairs(config.Companies) do
		companies[company.Id] = {
			Id = company.Id,
			Name = company.Name,
		}
	end

	local registry = {
		_config = config,
		_companies = companies,
		_squads = {},
		_playerSquads = {},
		_nextId = 1,
	} :: Registry

	return setmetatable(registry, RegistryMethods) :: Registry
end

return SquadRegistry