--!strict

local SquadRegistry = require("../src/server/services/SquadRegistry")
local SquadRequestRules = require("../src/server/services/SquadRequestRules")
local RankRules = require("../src/server/services/RankRules")

local testsRun = 0

local function expectFailure(result, code: string)
	assert(not result.Ok, `expected failure {code}`)
	assert(result.Code == code, `expected {code}, got {result.Code}`)
	testsRun += 1
end

local config = {
	Companies = {
		{ Id = "sierra", Name = "Compania Sierra" },
		{ Id = "norte", Name = "Compania Norte" },
	},
	AssignableSquadRoles = {
		Rifleman = true,
		Medic = true,
		Engineer = true,
	},
	MaxSquadsPerCompany = 1,
	MaxMembersPerSquad = 2,
	MinSquadNameLength = 3,
	MaxSquadNameLength = 24,
}

local registry = SquadRegistry.new(config)

expectFailure(registry:CreateSquad(100, "Alpha", "sierra", false), "permission_denied")

local created = registry:CreateSquad(100, "  Alpha  ", "sierra", true)
assert(created.Ok and created.Squad ~= nil)
assert(created.Squad.Name == "Alpha")
assert(created.Squad.LeaderUserId == 100)
assert(created.Squad.MemberRoles[100] == "SquadLeader")
local squadId = created.Squad.Id
testsRun += 1

expectFailure(registry:CreateSquad(100, "Bravo", "norte", true), "already_in_squad")

local joined = registry:JoinSquad(200, squadId, true)
assert(joined.Ok and joined.Squad ~= nil)
assert(#joined.Squad.MemberUserIds == 2)
testsRun += 1

expectFailure(registry:JoinSquad(200, squadId, true), "already_in_squad")
expectFailure(registry:JoinSquad(300, squadId, true), "squad_full")
expectFailure(registry:CreateSquad(300, "Charlie", "sierra", true), "squad_limit")

expectFailure(registry:AssignRole(200, 100, "Medic", false), "permission_denied")
local assignedRole = registry:AssignRole(100, 200, "Medic", true)
assert(assignedRole.Ok and assignedRole.Squad ~= nil)
assert(assignedRole.Squad.MemberRoles[200] == "Medic")
testsRun += 1

local leaderLeft = registry:LeaveSquad(100, true)
assert(leaderLeft.Ok and leaderLeft.Squad ~= nil)
assert(leaderLeft.Squad.LeaderUserId == 200)
assert(leaderLeft.Squad.MemberRoles[200] == "SquadLeader")
testsRun += 1

expectFailure(registry:DisbandSquad(300, squadId, false), "permission_denied")
local disbanded = registry:DisbandSquad(200, squadId, false)
assert(disbanded.Ok and registry:GetPlayerSquad(200) == nil)
testsRun += 1

local function expectInvalidRequest(request, expectedCode: string)
	local normalized, code = SquadRequestRules.Validate(request, config.AssignableSquadRoles)
	assert(normalized == nil, `expected invalid request: {expectedCode}`)
	assert(code == expectedCode, `expected {expectedCode}, got {code}`)
	testsRun += 1
end

expectInvalidRequest("create", "invalid_request")
expectInvalidRequest({ action = "promote", rank = "Commander" }, "invalid_action")
expectInvalidRequest({ action = "create", name = "Alpha", rank = "Commander" }, "unexpected_field")
expectInvalidRequest({ action = "leave", userId = 100 }, "unexpected_field")
local extraArguments, extraArgumentsError = SquadRequestRules.ValidateCall(
	{ action = "leave" },
	2,
	config.AssignableSquadRoles
)
assert(extraArguments == nil and extraArgumentsError == "invalid_argument_count")
testsRun += 1
expectInvalidRequest({ action = "join", squadId = "not-an-id" }, "invalid_squad")
expectInvalidRequest({ action = "setRole", targetUserId = 0, role = "Medic" }, "invalid_target")
expectInvalidRequest({ action = "setRole", targetUserId = 200, role = "Commander" }, "invalid_role")

assert(RankRules.HasPermission("Recruit", "squad.create"))
assert(not RankRules.HasPermission("Recruit", "squad.disbandAny"))
assert(RankRules.HasPermission("Sergeant", "squad.disbandAny"))
assert(RankRules.CanAssignRank("Commander", "Sergeant"))
assert(not RankRules.CanAssignRank("Commander", "Commander"))
testsRun += 1

print(`Fase 3: {testsRun} comprobaciones de reglas pasaron.`)