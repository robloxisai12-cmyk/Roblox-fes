--!strict

local allowedDriverRoles = table.freeze({
	Engineer = true,
	SquadLeader = true,
	Commander = true,
})

local vehicles = table.freeze({
	Ranger = table.freeze({
		DisplayName = "Ranger",
		Category = "Pickup",
		MaxSpeed = 42,
		ReverseSpeed = 12,
		TurnRate = 1.15,
		FuelCapacity = 100,
		InitialFuel = 100,
		FuelPerStud = 0.012,
		CargoCapacity = 24,
		AllowedDriverRoles = allowedDriverRoles,
		Spawns = table.freeze({
			table.freeze({ Id = "Ranger1", X = -75, Z = -184, Yaw = 0 }),
			table.freeze({ Id = "Ranger2", X = -125, Z = -184, Yaw = 0 }),
		}),
	}),
})

local resources = table.freeze({
	Ammo = table.freeze({ DisplayName = "Municion", Weight = 1 }),
	Medical = table.freeze({ DisplayName = "Suministros medicos", Weight = 1 }),
	Rations = table.freeze({ DisplayName = "Raciones", Weight = 1 }),
	Fuel = table.freeze({ DisplayName = "Combustible", Weight = 1 }),
})

local supplyPoints = table.freeze({
	table.freeze({
		Id = "SierraDepot",
		Name = "Deposito de San Isidro",
		Kind = "Depot",
		X = -90,
		Z = -166,
		Radius = 18,
		Stock = table.freeze({ Ammo = 24, Medical = 12, Rations = 20, Fuel = 600 }),
		MaxStock = table.freeze({ Ammo = 40, Medical = 20, Rations = 30, Fuel = 1000 }),
		RestockSeconds = 300,
		RestockAmount = table.freeze({ Ammo = 8, Medical = 4, Rations = 6, Fuel = 200 }),
	}),
	table.freeze({
		Id = "ValleyDelivery",
		Name = "Punto logistico del valle",
		Kind = "Delivery",
		X = 420,
		Z = 75,
		Radius = 20,
		Stock = table.freeze({ Ammo = 0, Medical = 0, Rations = 0, Fuel = 0 }),
		MaxStock = table.freeze({ Ammo = 60, Medical = 30, Rations = 50, Fuel = 1200 }),
		RestockSeconds = 600,
		RestockAmount = table.freeze({ Ammo = 0, Medical = 0, Rations = 0, Fuel = 0 }),
	}),
})

return table.freeze({
	Vehicles = vehicles,
	Resources = resources,
	SupplyPoints = supplyPoints,
	InteractionRange = 12,
	VehicleEnterRange = 14,
	MaxRequestAmount = 8,
	RequestWindowSeconds = 1,
	MaxRequestsPerWindow = 10,
	VehicleStatusInterval = 1,
	DriveSendInterval = 0.2,
	DriveInputTimeout = 0.65,
	MaxDriveRequestsPerWindow = 12,
	Resupply = table.freeze({
		AmmoRoundsPerUnit = 30,
		MaxAmmoReserveMultiplier = 2,
		MedicalCapacityMultiplier = 2,
		MedicalItemsPerUnit = 1,
		RationsPerUnit = 1,
		MaxRations = 30,
		FuelPerUnit = 10,
	}),
})
