--!strict

local InventoryConfig = require("../src/shared/config/InventoryConfig")
local RadioConfig = require("../src/shared/config/RadioConfig")
local InventoryRules = require("../src/server/services/InventoryRules")
local RadioRules = require("../src/server/services/RadioRules")

local checks = 0

local function check(condition: boolean, message: string)
	assert(condition, message)
	checks += 1
end

local function expectFailure(request: any, expectedCode: string, argumentCount: number?)
	local normalized, code = RadioRules.ValidateCall(request, argumentCount or 1, RadioConfig.MaxMessageBytes)
	check(normalized == nil and code == expectedCode, `expected {expectedCode}, got {code}`)
end

check(RadioRules.IsValidConfig(RadioConfig), "radio channel and rate settings validate")
local invalidConfig: any = table.clone(RadioConfig)
invalidConfig.GeneralChannel = table.clone(RadioConfig.GeneralChannel)
invalidConfig.GeneralChannel.Range = math.huge
check(not RadioRules.IsValidConfig(invalidConfig), "non-finite radio range is rejected")

local stateRequest, stateError = RadioRules.ValidateCall({ action = "state" }, 1, RadioConfig.MaxMessageBytes)
check(stateRequest ~= nil and stateError == nil and stateRequest.action == "state", "state request is accepted")
local selectedRequest, selectError =
	RadioRules.ValidateCall({ action = "select", channelId = "squad/SQD-0001" }, 1, RadioConfig.MaxMessageBytes)
check(selectedRequest ~= nil and selectError == nil, "well-formed squad channel selection is accepted")
local sentRequest, sendError =
	RadioRules.ValidateCall({ action = "send", text = "  En posicion  " }, 1, RadioConfig.MaxMessageBytes)
check(
	sentRequest ~= nil and sendError == nil and sentRequest.action == "send" and sentRequest.text == "En posicion",
	"message whitespace is normalized"
)
local exactLimitRequest = {
	action = "send",
	text = string.rep("x", RadioConfig.MaxMessageBytes),
}
check(
	RadioRules.ValidateCall(exactLimitRequest, 1, RadioConfig.MaxMessageBytes) ~= nil,
	"message at configured byte limit is accepted"
)

expectFailure({ action = "send", text = string.rep("x", RadioConfig.MaxMessageBytes + 1) }, "message_too_long")
expectFailure({ action = "send", text = "   " }, "empty_message")
expectFailure({ action = "send", text = "mensaje", senderName = "falso" }, "unexpected_field")
expectFailure({ action = "select", channelId = string.rep("x", 65) }, "invalid_channel")
expectFailure({ action = "teleport" }, "invalid_action")
expectFailure({ action = "state", userId = 42 }, "unexpected_field")
expectFailure({ action = "state" }, "invalid_argument_count", 2)
expectFailure(setmetatable({ action = "state" }, {}), "invalid_request")

check(
	RadioRules.CanAccessChannel("general", RadioConfig.GeneralChannel.Id, nil),
	"every equipped radio can use the general channel"
)
check(
	RadioRules.CanAccessChannel("squad/SQD-0001", RadioConfig.GeneralChannel.Id, "SQD-0001"),
	"member can access their squad channel"
)
check(
	not RadioRules.CanAccessChannel("squad/SQD-0002", RadioConfig.GeneralChannel.Id, "SQD-0001"),
	"squad member cannot access a different squad channel"
)
check(
	not RadioRules.CanAccessChannel("squad/SQD-0001", RadioConfig.GeneralChannel.Id, nil),
	"player without a squad cannot access a squad channel"
)

check(RadioRules.IsWithinRange(600, 600), "signal is available at the configured range boundary")
check(not RadioRules.IsWithinRange(600.1, 600), "signal is lost beyond configured range")
check(not RadioRules.IsWithinRange(-1, 600), "negative distance is invalid")
check(RadioRules.GetSignalStrength(0, 600) == 1, "signal is strongest at zero distance")
check(RadioRules.GetSignalStrength(300, 600) == 0.5, "signal falls linearly with distance")
check(RadioRules.GetSignalStrength(600, 600) > 0, "weak signal remains measurable at range boundary")
check(RadioRules.GetSignalStrength(601, 600) == 0, "out-of-range signal strength is zero")

local allowed, firstBucket = RadioRules.TakeRateLimitToken(nil, 10, 5, 2)
check(allowed and firstBucket ~= nil and firstBucket.Count == 1, "first request consumes one rate token")
local secondAllowed, secondBucket = RadioRules.TakeRateLimitToken(firstBucket, 11, 5, 2)
check(secondAllowed and secondBucket ~= nil and secondBucket.Count == 2, "request inside limit window is counted")
local thirdAllowed, unchangedBucket = RadioRules.TakeRateLimitToken(secondBucket, 12, 5, 2)
check(not thirdAllowed and unchangedBucket == secondBucket, "excess request is rejected without changing bucket")
local resetAllowed, resetBucket = RadioRules.TakeRateLimitToken(secondBucket, 15, 5, 2)
check(resetAllowed and resetBucket ~= nil and resetBucket.Count == 1, "rate limit resets at the window boundary")

local inventory = InventoryRules.Create(InventoryConfig) :: any
check(inventory.Equipment.Radio == "FieldRadio", "radio is assigned within the existing inventory")
local inventorySnapshot = InventoryRules.Copy(inventory)
inventorySnapshot.Equipment.Radio = "ForgedRadio"
check(inventory.Equipment.Radio == "FieldRadio", "radio equipment snapshot is defensive")
local invalidInventoryConfig: any = table.clone(InventoryConfig)
invalidInventoryConfig.Radio = nil
check(InventoryRules.Create(invalidInventoryConfig) == nil, "inventory rejects invalid radio equipment configuration")

print(`Fase 8: {checks} comprobaciones de reglas pasaron.`)
