--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(script.Parent.PlayerDataService)
local RankService = require(script.Parent.RankService)
local CompanyService = require(script.Parent.CompanyService)
local SquadRegistry = require(script.Parent.SquadRegistry)
local SquadRequestRules = require(script.Parent.SquadRequestRules)

local shared = ReplicatedStorage:WaitForChild("Shared")
local configFolder = shared:WaitForChild("config")
local configModule = configFolder:WaitForChild("OrganizationConfig") :: ModuleScript
local config = require(configModule)
local remoteFolder = ReplicatedStorage:WaitForChild("Remotes")
local requestRemote = remoteFolder:WaitForChild("SquadRequest") :: RemoteFunction

local registry = SquadRegistry.new({
	Companies = CompanyService.GetDefinitions(),
	AssignableSquadRoles = config.AssignableSquadRoles,
	MaxSquadsPerCompany = config.MaxSquadsPerCompany,
	MaxMembersPerSquad = config.MaxMembersPerSquad,
	MinSquadNameLength = config.MinSquadNameLength,
	MaxSquadNameLength = config.MaxSquadNameLength,
})

local REQUEST_WINDOW_SECONDS = 10
local MAX_REQUESTS_PER_WINDOW = 12

type RequestBucket = {
	WindowStartedAt: number,
	Count: number,
}

local requestBuckets: { [Player]: RequestBucket } = {}
local isStarted = false
local playerRemovingConnection: RBXScriptConnection? = nil

local SquadService = {}

local function errorResponse(code: string)
	return {
		ok = false,
		code = code,
	}
end

local function serializeSquad(squad: any)
	local members = {}
	for _, userId in ipairs(squad.MemberUserIds) do
		table.insert(members, {
			userId = userId,
			role = squad.MemberRoles[userId],
		})
	end

	return {
		id = squad.Id,
		name = squad.Name,
		companyId = squad.CompanyId,
		leaderUserId = squad.LeaderUserId,
		members = members,
	}
end

local function serializeResult(result: any)
	local response = {
		ok = result.Ok,
		code = result.Code,
	}
	if result.Squad ~= nil then
		response.squad = serializeSquad(result.Squad)
	end
	return response
end

local function syncPlayerRole(userId: number)
	local player = Players:GetPlayerByUserId(userId)
	if player == nil then
		return
	end

	local rank = RankService.GetRank(player)
	if rank == "Commander" then
		PlayerDataService.SetRole(player, "Commander")
		return
	end

	PlayerDataService.SetRole(player, registry:GetPlayerRole(userId) or "Rifleman")
end

local function syncAffectedRoles(userIds: { number })
	for _, userId in ipairs(userIds) do
		syncPlayerRole(userId)
	end
end

local function takeRateLimitToken(player: Player): boolean
	local now = os.clock()
	local bucket = requestBuckets[player]
	if bucket == nil or now - bucket.WindowStartedAt >= REQUEST_WINDOW_SECONDS then
		requestBuckets[player] = {
			WindowStartedAt = now,
			Count = 1,
		}
		return true
	end

	if bucket.Count >= MAX_REQUESTS_PER_WINDOW then
		return false
	end

	bucket.Count += 1
	return true
end

local function processRequest(player: Player, rawRequest: any, argumentCount: number)
	if player.Parent ~= Players then
		return errorResponse("invalid_player")
	end
	if not takeRateLimitToken(player) then
		return errorResponse("rate_limited")
	end

	local request, validationError = SquadRequestRules.ValidateCall(
		rawRequest,
		argumentCount,
		config.AssignableSquadRoles
	)
	if request == nil then
		return errorResponse(validationError or "invalid_request")
	end
	if PlayerDataService.GetSession(player) == nil then
		return errorResponse("session_unavailable")
	end

	if request.action == "list" then
		local squads = {}
		for _, squad in ipairs(registry:ListSquads()) do
			table.insert(squads, serializeSquad(squad))
		end
		return {
			ok = true,
			companies = CompanyService.GetPublicCompanies(registry),
			squads = squads,
		}
	elseif request.action == "create" then
		if not RankService.HasPermission(player, "squad.create") then
			return errorResponse("permission_denied")
		end
		local companyId, companyError = CompanyService.ResolveRequestedCompany(player, request.companyId)
		if companyId == nil then
			return errorResponse(companyError or "invalid_company")
		end

		local result = registry:CreateSquad(player.UserId, request.name :: string, companyId, true)
		syncAffectedRoles(result.AffectedUserIds)
		return serializeResult(result)
	elseif request.action == "join" then
		local result = registry:JoinSquad(
			player.UserId,
			request.squadId :: string,
			RankService.HasPermission(player, "squad.join")
		)
		syncAffectedRoles(result.AffectedUserIds)
		return serializeResult(result)
	elseif request.action == "leave" then
		local result = registry:LeaveSquad(
			player.UserId,
			RankService.HasPermission(player, "squad.leave")
		)
		syncAffectedRoles(result.AffectedUserIds)
		return serializeResult(result)
	elseif request.action == "disband" then
		local result = registry:DisbandSquad(
			player.UserId,
			request.squadId :: string,
			RankService.HasPermission(player, "squad.disbandAny")
		)
		syncAffectedRoles(result.AffectedUserIds)
		return serializeResult(result)
	elseif request.action == "setRole" then
		local target = Players:GetPlayerByUserId(request.targetUserId :: number)
		if target == nil or PlayerDataService.GetSession(target) == nil then
			return errorResponse("target_unavailable")
		end
		local result = registry:AssignRole(
			player.UserId,
			target.UserId,
			request.role :: string,
			RankService.HasPermission(player, "squad.assignRoles")
		)
		if result.Ok then
			syncAffectedRoles(result.AffectedUserIds)
		end
		return serializeResult(result)
	end

	return errorResponse("invalid_action")
end

function SquadService.Start()
	if isStarted then
		return
	end

	isStarted = true
	requestRemote.OnServerInvoke = function(player: Player, ...: any)
		local arguments = table.pack(...)
		local ok, response = pcall(processRequest, player, arguments[1], arguments.n)
		if not ok then
			warn(`SquadService request failed: {response}`)
			return errorResponse("internal_error")
		end
		return response
	end

	playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
		requestBuckets[player] = nil
		local result = registry:LeaveSquad(player.UserId, true)
		syncAffectedRoles(result.AffectedUserIds)
	end)
end

return table.freeze(SquadService)