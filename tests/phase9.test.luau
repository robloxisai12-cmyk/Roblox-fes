--!strict

local MissionConfig = require("../src/shared/config/MissionConfig")
local MatchRules = require("../src/server/services/MatchRules")

local checks = 0

local function check(condition: boolean, message: string)
	assert(condition, message)
	checks += 1
end

local function expectRequestFailure(request: any, expectedCode: string, argumentCount: number?)
	local valid, code = MatchRules.ValidateRequest(request, argumentCount or 1)
	check(not valid and code == expectedCode, `expected {expectedCode}, got {code}`)
end

check(MatchRules.ValidateConfig(MissionConfig), "mission and match configuration validates")
local invalidConfig: any = table.clone(MissionConfig)
invalidConfig.MatchDurationSeconds = math.huge
check(not MatchRules.ValidateConfig(invalidConfig), "non-finite match duration is rejected")

local duplicateConfig: any = table.clone(MissionConfig)
duplicateConfig.Objectives = { MissionConfig.Objectives[1], MissionConfig.Objectives[1] }
check(not MatchRules.ValidateConfig(duplicateConfig), "duplicate objective IDs are rejected")

local invalidDelivery: any = table.clone(MissionConfig)
invalidDelivery.Objectives = { table.clone(MissionConfig.Objectives[2]) }
invalidDelivery.Objectives[1].RequiredAmount = 0
check(not MatchRules.ValidateConfig(invalidDelivery), "delivery objectives require a positive integer amount")
local duplicateDelivery: any = table.clone(MissionConfig)
duplicateDelivery.Objectives = {
	table.clone(MissionConfig.Objectives[2]),
	table.clone(MissionConfig.Objectives[2]),
}
duplicateDelivery.Objectives[2].Id = "duplicate_supply"
check(not MatchRules.ValidateConfig(duplicateDelivery), "duplicate delivery counters are rejected")

local initialState = MatchRules.Create(MissionConfig)
check(initialState ~= nil and initialState.Status == "waiting", "new match starts in waiting state")
local state = initialState :: any
check(state.Objectives[1].Status == "locked", "objectives are unavailable before the match")

local noChange, noChangeEvent = MatchRules.Step(state, 0, 10, MissionConfig)
check(not noChange and noChangeEvent == nil and state.Status == "waiting", "match waits below minimum players")
local startedPrep, prepEvent = MatchRules.Step(state, 1, 11, MissionConfig)
check(startedPrep and prepEvent == "preparation_started" and state.Status == "preparation", "sufficient players start preparation")
check(state.Round == 0, "cancelled preparation does not consume a round number")
local cancelled, cancelEvent = MatchRules.Step(state, 0, 12, MissionConfig)
check(cancelled and cancelEvent == "preparation_cancelled" and state.Status == "waiting", "preparation cancels when players leave")
local restartedPrep = MatchRules.Step(state, 1, 20, MissionConfig)
check(restartedPrep and state.Status == "preparation", "waiting state can start preparation again")
local beforePrepEnd = MatchRules.Step(state, 1, 34, MissionConfig)
check(not beforePrepEnd and state.Status == "preparation", "preparation does not end before its configured timer")
local beganMatch, matchEvent = MatchRules.Step(state, 1, 35, MissionConfig)
check(beganMatch and matchEvent == "match_started" and state.Status == "active", "preparation timer activates the match")
check(state.Round == 1 and state.EndsAt == 935, "match duration and round are set by server rules")
check(state.Objectives[1].Status == "active", "first mission objective activates with the match")

local noContributors = MatchRules.AdvanceObjective(state, 5, {}, {}, 3, MissionConfig.ResultSeconds, 40)
check(not noContributors and state.Objectives[1].Progress == 0, "capture cannot progress without living contributors")
local captureProgress = MatchRules.AdvanceObjective(
	state,
	10,
	{ 101, 101 },
	{ supply_valley = 0 },
	3,
	MissionConfig.ResultSeconds,
	50
)
check(not captureProgress and state.Objectives[1].Progress == 10, "duplicate user IDs cannot amplify capture progress")
check(state.Objectives[1].Contributors[101] == true, "valid capture contribution is recorded")

local captureComplete, captureEvent = MatchRules.AdvanceObjective(
	state,
	25,
	{ 101, 202, 303 },
	{ supply_valley = 0 },
	3,
	MissionConfig.ResultSeconds,
	75
)
check(captureComplete and captureEvent == "objective_completed", "cooperative capture completes its objective")
check(state.Objectives[1].Status == "complete" and state.Objectives[2].Status == "active", "objective order is enforced")
state.Objectives[2].DeliveryBaseline = 10

local priorDeliveries = MatchRules.AdvanceObjective(
	state,
	1,
	{},
	{ supply_valley = 10 },
	3,
	MissionConfig.ResultSeconds,
	76
)
check(not priorDeliveries and state.Objectives[2].Progress == 0, "delivery objective does not accept a client-side completion")
local deliveredOne = MatchRules.AdvanceObjective(
	state,
	1,
	{},
	{ supply_valley = 11 },
	3,
	MissionConfig.ResultSeconds,
	77
)
check(not deliveredOne and state.Objectives[2].Progress == 1, "server-observed deliveries advance objective progress")
local invalidDeliveryAmount = MatchRules.AdvanceObjective(
	state,
	1,
	{},
	{ supply_valley = math.huge },
	3,
	MissionConfig.ResultSeconds,
	78
)
check(not invalidDeliveryAmount and state.Objectives[2].Progress == 1, "invalid delivery totals do not mutate progress")
local deliveryComplete, victoryEvent = MatchRules.AdvanceObjective(
	state,
	1,
	{},
	{ supply_valley = 12 },
	3,
	MissionConfig.ResultSeconds,
	79
)
check(deliveryComplete and victoryEvent == "match_victory" and state.Status == "victory", "required deliveries produce mission victory")
check(state.Objectives[2].Status == "complete", "successful delivery objective is marked complete")

local resultChanged, resultEvent = MatchRules.Step(state, 1, 87, MissionConfig)
check(resultChanged and resultEvent == "cleanup_started" and state.Status == "ended", "result phase transitions into cleanup")
local resetChanged, resetEvent = MatchRules.Step(state, 1, 89, MissionConfig)
check(resetChanged and resetEvent == "match_reset" and state.Status == "waiting", "cleanup returns match to waiting")
check(state.Objectives[1].Progress == 0 and state.Objectives[2].Progress == 0, "next match clears prior objective progress")

local defeatState = MatchRules.Create(MissionConfig) :: any
MatchRules.Step(defeatState, 1, 100, MissionConfig)
MatchRules.Step(defeatState, 1, 115, MissionConfig)
local playerDefeat, playerDefeatEvent = MatchRules.Step(defeatState, 0, 116, MissionConfig)
check(playerDefeat and playerDefeatEvent == "match_defeat", "match ends in defeat when no players remain")
local timeState = MatchRules.Create(MissionConfig) :: any
MatchRules.Step(timeState, 1, 100, MissionConfig)
MatchRules.Step(timeState, 1, 115, MissionConfig)
local timeoutDefeat, timeoutEvent = MatchRules.Step(timeState, 1, 1015, MissionConfig)
check(timeoutDefeat and timeoutEvent == "match_defeat" and timeState.Reason == "time_expired", "match duration safely times out")

local stateRequest, stateRequestError = MatchRules.ValidateRequest({ action = "state" }, 1)
check(stateRequest and stateRequestError == nil, "client may request a read-only mission snapshot")
expectRequestFailure({ action = "advance", objectiveId = "supply_valley" }, "unexpected_field")
expectRequestFailure({ action = "start" }, "invalid_action")
expectRequestFailure({ action = "state" }, "invalid_argument_count", 2)
expectRequestFailure(setmetatable({ action = "state" }, {}), "invalid_request")
check(
	MatchRules.IsMovementPlausible(7.5, 2, 0.1, 65, 220, 12),
	"plausible player movement remains eligible to contribute"
)
check(
	not MatchRules.IsMovementPlausible(12, 0, 1 / 60, 65, 220, 12),
	"per-frame teleport increments cannot use a fixed distance allowance"
)
check(
	not MatchRules.IsMovementPlausible(100, 2, 0.1, 65, 220, 12),
	"horizontal teleport-sized movement is rejected"
)
check(
	not MatchRules.IsMovementPlausible(0, 100, 0.1, 65, 220, 12),
	"vertical teleport-sized movement is rejected"
)

local copy = MatchRules.Copy(state, 90)
check(copy.status == "waiting" and copy.objectives[1].progress == 0, "client snapshot reflects reset state")
check(copy.objectives[1].contributorCount == 0, "round cleanup removes contributor records")

print(`Fase 9: {checks} comprobaciones de reglas pasaron.`)
