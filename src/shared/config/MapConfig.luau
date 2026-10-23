--!strict

local roads = table.freeze({
	table.freeze({
		Id = "camino_principal",
		Width = 14,
		Points = table.freeze({
			table.freeze({ X = -600, Z = -410 }),
			table.freeze({ X = -410, Z = -295 }),
			table.freeze({ X = -245, Z = -205 }),
			table.freeze({ X = -120, Z = -175 }),
			table.freeze({ X = 10, Z = -170 }),
			table.freeze({ X = 180, Z = -155 }),
			table.freeze({ X = 360, Z = -245 }),
			table.freeze({ X = 600, Z = -390 }),
		}),
	}),
	table.freeze({
		Id = "camino_alto",
		Width = 10,
		Points = table.freeze({
			table.freeze({ X = -550, Z = 470 }),
			table.freeze({ X = -390, Z = 330 }),
			table.freeze({ X = -270, Z = 205 }),
			table.freeze({ X = -180, Z = 55 }),
			table.freeze({ X = -90, Z = -105 }),
			table.freeze({ X = -80, Z = -165 }),
		}),
	}),
	table.freeze({
		Id = "camino_del_valle",
		Width = 9,
		Points = table.freeze({
			table.freeze({ X = 100, Z = -170 }),
			table.freeze({ X = 220, Z = -35 }),
			table.freeze({ X = 350, Z = 105 }),
			table.freeze({ X = 480, Z = 255 }),
			table.freeze({ X = 600, Z = 390 }),
		}),
	}),
})

local spawnPoints = table.freeze({
	table.freeze({ X = -22, Z = -20 }),
	table.freeze({ X = 22, Z = -20 }),
	table.freeze({ X = -22, Z = 22 }),
	table.freeze({ X = 22, Z = 22 }),
})

return table.freeze({
	Name = "Sierra de Guardia",
	Seed = 4202026,
	Dimensions = table.freeze({
		Width = 1280,
		Depth = 1280,
		BaseHeight = 24,
		TerrainDepth = 16,
		MaxHeight = 230,
	}),
	Terrain = table.freeze({
		HillCount = 20,
		MinHillRadius = 58,
		MaxHillRadius = 126,
		MountainEvery = 5,
	}),
	Vegetation = table.freeze({
		DensityPerStudSquared = 0.000075,
		MaxTrees = 128,
	}),
	Town = table.freeze({
		Id = "pueblo_sierra",
		Name = "San Isidro del Valle",
		Center = table.freeze({ X = 0, Z = 0 }),
		Radius = 190,
		BuildingCount = 8,
	}),
	SpawnZone = table.freeze({
		Id = "spawn_san_isidro",
		Name = "Plaza de San Isidro",
		Center = table.freeze({ X = 0, Z = 0 }),
		Radius = 68,
		Points = spawnPoints,
	}),
	Roads = roads,
})