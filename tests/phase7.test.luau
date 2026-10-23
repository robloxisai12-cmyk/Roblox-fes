--!strict

local LogisticsConfig = require("../src/shared/config/LogisticsConfig")
local InventoryConfig = require("../src/shared/config/InventoryConfig")
local MedicalConfig = require("../src/shared/config/MedicalConfig")
local InventoryRules = require("../src/server/services/InventoryRules")
local LogisticsRules = require("../src/server/services/LogisticsRules")
local VehicleRules = require("../src/server/services/VehicleRules")
local CombatRequestRules = require("../src/server/services/CombatRequestRules")

local checks = 0

local function check(condition: boolean, message: string)
	assert(condition, message)
	checks += 1
end

local function expectFailure(request: any, expectedCode: string)
	local normalized, code = CombatRequestRules.Validate(request, 1)
	check(normalized == nil and code == expectedCode, `expected {expectedCode}, got {code}`)
end

check(LogisticsRules.ValidateConfig(LogisticsConfig), "logistics configuration validates")
local invalidConfig: any = table.clone(LogisticsConfig)
invalidConfig.MaxRequestAmount = math.huge
check(not LogisticsRules.ValidateConfig(invalidConfig), "invalid request limit is rejected")

local depot = LogisticsConfig.SupplyPoints[1]
local stock: { [string]: number } = {
	Ammo = depot.Stock.Ammo,
	Medical = depot.Stock.Medical,
	Rations = depot.Stock.Rations,
	Fuel = depot.Stock.Fuel,
}
local destinationDepot = LogisticsConfig.SupplyPoints[2]
local destinationStock: { [string]: number } = {
	Ammo = destinationDepot.Stock.Ammo,
	Medical = destinationDepot.Stock.Medical,
	Rations = destinationDepot.Stock.Rations,
	Fuel = destinationDepot.Stock.Fuel,
}
local destinationMax: { [string]: number } = {
	Ammo = destinationDepot.MaxStock.Ammo,
	Medical = destinationDepot.MaxStock.Medical,
	Rations = destinationDepot.MaxStock.Rations,
	Fuel = destinationDepot.MaxStock.Fuel,
}
local cargo = LogisticsRules.CreateCargo(LogisticsConfig)
check(cargo.Ammo == 0 and cargo.Medical == 0, "vehicle cargo starts empty")
check(LogisticsRules.CargoWeight(cargo, LogisticsConfig.Resources) == 0, "empty cargo has no weight")

local loaded, loadedCode = LogisticsRules.LoadCargo(cargo, stock, LogisticsConfig.Resources, 24, "Ammo", 8)
check(loaded and loadedCode == "loaded", "available cargo loads")
check(stock.Ammo == depot.Stock.Ammo - 8 and cargo.Ammo == 8, "loading deducts depot stock and adds vehicle cargo")
local excessCargo, excessCode = LogisticsRules.LoadCargo(cargo, stock, LogisticsConfig.Resources, 24, "Rations", 17)
check(not excessCargo and excessCode == "cargo_full", "cargo capacity blocks excessive load")
check(stock.Rations == depot.Stock.Rations and cargo.Rations == 0, "failed cargo load does not alter stock or load")
local unknownResource, unknownCode = LogisticsRules.LoadCargo(cargo, stock, LogisticsConfig.Resources, 24, "Weapons", 1)
check(not unknownResource and unknownCode == "invalid_resource", "unknown supply resource is rejected")
local invalidAmount, invalidAmountCode = LogisticsRules.LoadCargo(cargo, stock, LogisticsConfig.Resources, 24, "Ammo", 1.5)
check(not invalidAmount and invalidAmountCode == "invalid_amount", "fractional supply count is rejected")
local noStock, noStockCode = LogisticsRules.LoadCargo(cargo, stock, LogisticsConfig.Resources, 24, "Medical", 13)
check(not noStock and noStockCode == "insufficient_stock", "load above depot stock is rejected")

local delivered, deliveredCode =
	LogisticsRules.DeliverCargo(cargo, destinationStock, destinationMax, LogisticsConfig.Resources, nil, nil)
check(delivered and deliveredCode == "delivered", "cargo delivers to authorized stock")
check(cargo.Ammo == 0 and destinationStock.Ammo == 8, "delivery transfers cargo exactly once")
local secondDelivery, secondDeliveryCode =
	LogisticsRules.DeliverCargo(cargo, destinationStock, destinationMax, LogisticsConfig.Resources, nil, nil)
check(not secondDelivery and secondDeliveryCode == "destination_full", "empty cargo cannot be delivered twice")

local limitedCargo = LogisticsRules.CreateCargo(LogisticsConfig)
limitedCargo.Ammo = 5
destinationStock.Ammo = destinationMax.Ammo - 2
local partialDelivery, partialDeliveryCode =
	LogisticsRules.DeliverCargo(limitedCargo, destinationStock, destinationMax, LogisticsConfig.Resources, "Ammo", 5)
check(partialDelivery and partialDeliveryCode == "delivered", "delivery accepts only destination capacity")
check(limitedCargo.Ammo == 3 and destinationStock.Ammo == destinationMax.Ammo, "overflow cargo remains in the vehicle")

local restockPoint = {
	Stock = { Ammo = 0, Medical = 0, Rations = 0, Fuel = 0 },
	MaxStock = { Ammo = 5, Medical = 2, Rations = 3, Fuel = 10 },
	RestockAmount = { Ammo = 3, Medical = 2, Rations = 1, Fuel = 10 },
}
local earlyRestock = LogisticsRules.Restock(restockPoint, 9, 10, 5)
check(earlyRestock == 0 and restockPoint.Stock.Ammo == 0, "stock does not restock before its timer")
local restocked, nextRestock = LogisticsRules.Restock(restockPoint, 10, 10, 5)
check(restocked == 1 and nextRestock == 15 and restockPoint.Stock.Ammo == 3, "stock restocks on the server schedule")
LogisticsRules.Restock(restockPoint, 15, 15, 5)
LogisticsRules.Restock(restockPoint, 20, 20, 5)
check(restockPoint.Stock.Ammo == 5 and restockPoint.Stock.Fuel == 10, "restocking never exceeds configured stock limits")

local taken, takeCode = LogisticsRules.TakeStock(stock, "Fuel", 50)
check(taken and takeCode == "taken" and stock.Fuel == depot.Stock.Fuel - 50, "fuel stock can be consumed")
local overTaken, overTakeCode = LogisticsRules.TakeStock(stock, "Fuel", 9999)
check(not overTaken and overTakeCode == "insufficient_stock", "stock cannot be withdrawn below zero")

local fuelStock = { Fuel = 10 }
local refueled, unitsUsed, refuelCode = LogisticsRules.Refuel(45, 100, fuelStock, 10)
check(refuelCode == "refueled" and refueled == 100 and unitsUsed == 6, "refueling fills only available tank capacity")
check(fuelStock.Fuel == 4, "refueling consumes matching depot fuel units")
local unchangedFuel, noFuelUsed, fullCode = LogisticsRules.Refuel(100, 100, fuelStock, 10)
check(unchangedFuel == 100 and noFuelUsed == 0 and fullCode == "tank_full", "full tank cannot be overfilled")

local validDriver, driverCode = LogisticsRules.CanDrive(1, true, true)
check(validDriver and driverCode == "ready", "authorized occupant with fuel can drive")
local noOccupant, noOccupantCode = LogisticsRules.CanDrive(1, false, true)
check(not noOccupant and noOccupantCode == "driver_required", "vehicle cannot drive without an occupant")
local unauthorized, unauthorizedCode = LogisticsRules.CanDrive(1, true, false)
check(not unauthorized and unauthorizedCode == "driver_unauthorized", "unauthorized role cannot drive")
local emptyFuel, emptyFuelCode = LogisticsRules.CanDrive(0, true, true)
check(not emptyFuel and emptyFuelCode == "out_of_fuel", "empty vehicle cannot drive")
local forwardSpeed, remainingFuel = LogisticsRules.StepVehicle(1, 1, 40, 10, 0.01, 1)
check(forwardSpeed == 40 and remainingFuel == 0.6, "forward speed and fuel use are server bounded")
local reverseSpeed = LogisticsRules.StepVehicle(10, -1, 40, 10, 0.01, 1)
check(reverseSpeed == -10, "reverse speed uses its separate limit")
local fuelLimitedSpeed, noFuelRemaining = LogisticsRules.StepVehicle(0.01, 1, 40, 10, 0.01, 1)
check(math.abs(fuelLimitedSpeed - 1) < 0.000001 and noFuelRemaining == 0, "vehicle slows as fuel is exhausted")

check(VehicleRules.CanEnter(true, false, true), "live authorized player may enter an empty vehicle")
local occupiedEntry, occupiedCode = VehicleRules.CanEnter(true, true, true)
check(not occupiedEntry and occupiedCode == "vehicle_occupied", "occupied vehicle rejects another driver")
local unauthorizedEntry, unauthorizedEntryCode = VehicleRules.CanEnter(true, false, false)
check(not unauthorizedEntry and unauthorizedEntryCode == "driver_unauthorized", "vehicle entry requires an allowed role")
check(VehicleRules.CanExit(true), "vehicle occupant may exit")
local invalidExit, invalidExitCode = VehicleRules.CanExit(false)
check(not invalidExit and invalidExitCode == "not_vehicle_occupant", "non-occupant cannot exit another player's vehicle")
check(VehicleRules.IsSafeInteraction(12, 12, true), "interaction at configured distance is allowed")
check(not VehicleRules.IsSafeInteraction(12.1, 12, true), "interaction beyond configured distance is rejected")
check(not VehicleRules.IsSafeInteraction(1 / 0, 12, true), "non-finite interaction distance is rejected")
check(not VehicleRules.IsSafeInteraction(1, 12, false), "dead player cannot interact")

local inventory = InventoryRules.Create(InventoryConfig, MedicalConfig) :: any
local ammoAdded, ammoCode = InventoryRules.AddAmmoReserve(inventory, "Rifle", 30, 180)
check(ammoAdded == 30 and ammoCode == "supplied", "logistics can add reserve ammo to existing inventory")
local fullAmmo, fullAmmoCode = InventoryRules.AddAmmoReserve(inventory, "Rifle", 100, 120)
check(fullAmmo == 0 and fullAmmoCode == "ammo_capacity_full", "reserve capacity prevents duplicate ammunition")
local rationsAdded, rationsCode = InventoryRules.AddSupply(inventory, "Rations", 5, 30)
check(rationsAdded == 5 and rationsCode == "supplied", "other supplies use the existing player inventory")
local snapshot = InventoryRules.Copy(inventory)
snapshot.Supplies.Rations = 0
check(inventory.Supplies.Rations == 5, "inventory supply snapshot is defensive")

local request, requestError = CombatRequestRules.Validate({
	action = "logistics",
	operation = "load_cargo",
	vehicleId = "Ranger1",
	resourceId = "Ammo",
	amount = 2,
}, 1)
check(request ~= nil and requestError == nil, "well-formed logistics request is accepted")
expectFailure({ action = "logistics", operation = "load_cargo", vehicleId = "Ranger1", resourceId = "Ammo", amount = 9 }, "invalid_logistics_request")
expectFailure({ action = "logistics", operation = "resupply", pointId = "SierraDepot", resourceId = "Ammo", amount = 1, health = 100 }, "unexpected_field")
expectFailure({ action = "logistics", operation = "refuel", vehicleId = "Ranger1", pointId = "SierraDepot", fuel = 100 }, "unexpected_field")
expectFailure({ action = "logistics", operation = "teleport" }, "invalid_operation")
local firstToken, bucket = LogisticsRules.TakeRateLimitToken(nil, 1, 1, 2)
local secondToken, secondBucket = LogisticsRules.TakeRateLimitToken(bucket, 1.1, 1, 2)
local thirdToken = LogisticsRules.TakeRateLimitToken(secondBucket, 1.2, 1, 2)
check(firstToken and secondToken and not thirdToken, "logistics request limiter caps bursts")

print(`Fase 7: {checks} comprobaciones de reglas logisticas y vehiculos pasaron.`)
