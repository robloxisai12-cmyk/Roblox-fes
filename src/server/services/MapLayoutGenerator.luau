--!strict

type Point = {
	X: number,
	Z: number,
}
	type SpawnPoint = {
		X: number,
		Z: number,
		GroundY: number,
	}

type Road = {
	Id: string,
	Width: number,
	Points: { Point },
}

type Hill = {
	X: number,
	Z: number,
	Radius: number,
	Material: string,
}

type Building = {
	X: number,
	Z: number,
	Width: number,
	Depth: number,
	Height: number,
	Rotation: number,
	Variant: number,
}

type Tree = {
	X: number,
	Z: number,
	GroundY: number,
	Scale: number,
	Variant: number,
}

type RoadSegment = {
	RoadId: string,
	Width: number,
	Start: { X: number, Y: number, Z: number },
	End: { X: number, Y: number, Z: number },
}

type Layout = {
	Name: string,
	Seed: number,
	Width: number,
	Depth: number,
	BaseHeight: number,
	TerrainDepth: number,
	MaxHeight: number,
	Hills: { Hill },
	Roads: { Road },
	Buildings: { Building },
	Trees: { Tree },
	SpawnZone: {
		Id: string,
		Name: string,
		Center: Point,
		Radius: number,
		Points: { SpawnPoint },
	},
}

type Config = {
	Name: string,
	Seed: number,
	Dimensions: {
		Width: number,
		Depth: number,
		BaseHeight: number,
		TerrainDepth: number,
		MaxHeight: number,
	},
	Terrain: {
		HillCount: number,
		MinHillRadius: number,
		MaxHillRadius: number,
		MountainEvery: number,
	},
	Vegetation: {
		DensityPerStudSquared: number,
		MaxTrees: number,
	},
	Town: {
		Id: string,
		Name: string,
		Center: Point,
		Radius: number,
		BuildingCount: number,
	},
	SpawnZone: {
		Id: string,
		Name: string,
		Center: Point,
		Radius: number,
		Points: { Point },
	},
	Roads: { Road },
}

type Generator = {
	State: number,
}

local UINT32_RANGE = 4294967296
local MAX_BASE_TERRAIN_CELLS = 2000000

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function isInteger(value: any): boolean
	return isFinite(value) and value % 1 == 0
end

local function isPointInBounds(point: any, halfWidth: number, halfDepth: number): boolean
	return type(point) == "table"
		and isFinite(point.X)
		and isFinite(point.Z)
		and math.abs(point.X) <= halfWidth
		and math.abs(point.Z) <= halfDepth
end

local function distanceSquared(left: Point, right: Point): number
	local x = left.X - right.X
	local z = left.Z - right.Z
	return x * x + z * z
end

local function distanceToSegmentSquared(point: Point, startPoint: Point, endPoint: Point): number
	local segmentX = endPoint.X - startPoint.X
	local segmentZ = endPoint.Z - startPoint.Z
	local segmentLengthSquared = segmentX * segmentX + segmentZ * segmentZ
	if segmentLengthSquared == 0 then
		return distanceSquared(point, startPoint)
	end

	local projection = ((point.X - startPoint.X) * segmentX + (point.Z - startPoint.Z) * segmentZ)
		/ segmentLengthSquared
	local t = math.clamp(projection, 0, 1)
	local closestPoint = {
		X = startPoint.X + t * segmentX,
		Z = startPoint.Z + t * segmentZ,
	}
	return distanceSquared(point, closestPoint)
end

local function nextUnit(generator: Generator): number
	generator.State = (generator.State * 1664525 + 1013904223) % UINT32_RANGE
	return generator.State / UINT32_RANGE
end

local function nextRange(generator: Generator, minimum: number, maximum: number): number
	return minimum + nextUnit(generator) * (maximum - minimum)
end

local function validateConfig(config: any, seed: any): (boolean, string?)
	if type(config) ~= "table" or type(config.Dimensions) ~= "table" then
		return false, "invalid_config"
	end
	if seed ~= nil and (not isInteger(seed) or seed < 0 or seed > 2147483647) then
		return false, "invalid_seed"
	end
	if not isInteger(config.Seed) or config.Seed < 0 or config.Seed > 2147483647 then
		return false, "invalid_config_seed"
	end

	local dimensions = config.Dimensions
	if not isInteger(dimensions.Width)
		or not isInteger(dimensions.Depth)
		or dimensions.Width % 4 ~= 0
		or dimensions.Depth % 4 ~= 0
		or dimensions.Width < 512
		or dimensions.Width > 4096
		or dimensions.Depth < 512
		or dimensions.Depth > 4096
		or not isFinite(dimensions.BaseHeight)
		or not isFinite(dimensions.TerrainDepth)
		or not isFinite(dimensions.MaxHeight)
		or dimensions.TerrainDepth < 16
		or not isInteger(dimensions.TerrainDepth)
		or dimensions.TerrainDepth % 4 ~= 0
		or dimensions.MaxHeight <= dimensions.BaseHeight
		or dimensions.BaseHeight < 0
		or dimensions.MaxHeight > 512
		or (dimensions.Width / 4)
			* (dimensions.Depth / 4)
			* (dimensions.TerrainDepth / 4)
			> MAX_BASE_TERRAIN_CELLS
	then
		return false, "invalid_dimensions"
	end

	local terrain = config.Terrain
	if type(terrain) ~= "table"
		or not isInteger(terrain.HillCount)
		or terrain.HillCount < 1
		or terrain.HillCount > 40
		or not isFinite(terrain.MinHillRadius)
		or not isFinite(terrain.MaxHillRadius)
		or terrain.MinHillRadius < 24
		or terrain.MaxHillRadius < terrain.MinHillRadius
		or terrain.MaxHillRadius > math.min(dimensions.Width, dimensions.Depth) / 3
		or dimensions.BaseHeight + terrain.MaxHillRadius > dimensions.MaxHeight
		or not isInteger(terrain.MountainEvery)
		or terrain.MountainEvery < 1
	then
		return false, "invalid_terrain"
	end

	local vegetation = config.Vegetation
	if type(vegetation) ~= "table"
		or not isFinite(vegetation.DensityPerStudSquared)
		or vegetation.DensityPerStudSquared < 0
		or vegetation.DensityPerStudSquared > 0.001
		or not isInteger(vegetation.MaxTrees)
		or vegetation.MaxTrees < 0
		or vegetation.MaxTrees > 256
	then
		return false, "invalid_vegetation"
	end

	local town = config.Town
	if type(town) ~= "table"
		or type(town.Id) ~= "string"
		or type(town.Name) ~= "string"
		or not isPointInBounds(town.Center, dimensions.Width / 2, dimensions.Depth / 2)
		or not isFinite(town.Radius)
		or town.Radius < 90
		or town.Radius > math.min(dimensions.Width, dimensions.Depth) / 3
		or math.abs(town.Center.X) + town.Radius > dimensions.Width / 2
		or math.abs(town.Center.Z) + town.Radius > dimensions.Depth / 2
		or not isInteger(town.BuildingCount)
		or town.BuildingCount < 1
		or town.BuildingCount > 16
	then
		return false, "invalid_town"
	end

	local spawnZone = config.SpawnZone
	if type(spawnZone) ~= "table"
		or type(spawnZone.Id) ~= "string"
		or type(spawnZone.Name) ~= "string"
		or not isPointInBounds(spawnZone.Center, dimensions.Width / 2, dimensions.Depth / 2)
		or not isFinite(spawnZone.Radius)
		or spawnZone.Radius < 16
		or spawnZone.Radius > town.Radius
		or math.sqrt(distanceSquared(spawnZone.Center, town.Center)) + spawnZone.Radius > town.Radius
		or math.abs(spawnZone.Center.X) + spawnZone.Radius > dimensions.Width / 2
		or math.abs(spawnZone.Center.Z) + spawnZone.Radius > dimensions.Depth / 2
		or type(spawnZone.Points) ~= "table"
		or #spawnZone.Points == 0
	then
		return false, "invalid_spawn_zone"
	end

	for _, point in ipairs(spawnZone.Points :: { Point }) do
		if not isPointInBounds(point, dimensions.Width / 2, dimensions.Depth / 2)
			or distanceSquared(point, spawnZone.Center) > spawnZone.Radius * spawnZone.Radius
		then
			return false, "spawn_out_of_bounds"
		end
	end

	if type(config.Roads) ~= "table" or #config.Roads == 0 then
		return false, "invalid_roads"
	end
	for _, road in ipairs(config.Roads :: { Road }) do
		if type(road.Id) ~= "string"
			or not isFinite(road.Width)
			or road.Width < 4
			or road.Width > 32
			or type(road.Points) ~= "table"
			or #road.Points < 2
		then
			return false, "invalid_road"
		end
		for _, point in ipairs(road.Points :: { Point }) do
			if not isPointInBounds(point, dimensions.Width / 2, dimensions.Depth / 2)
				or math.abs(point.X) + road.Width / 2 > dimensions.Width / 2
				or math.abs(point.Z) + road.Width / 2 > dimensions.Depth / 2
			then
				return false, "road_out_of_bounds"
			end
		end
	end

	return true, nil
end

local function copyRoads(roads: { Road }): { Road }
	local result = {}
	for _, road in ipairs(roads) do
		local points = {}
		for _, point in ipairs(road.Points) do
			table.insert(points, { X = point.X, Z = point.Z })
		end
		table.insert(result, {
			Id = road.Id,
			Width = road.Width,
			Points = points,
		})
	end
	return result
end

local function isNearRoad(point: Point, roads: { Road }, minimumDistance: number): boolean
	local minimumDistanceSquared = minimumDistance * minimumDistance
	for _, road in ipairs(roads) do
		for index = 1, #road.Points - 1 do
			if distanceToSegmentSquared(point, road.Points[index], road.Points[index + 1])
				< minimumDistanceSquared
			then
				return true
			end
		end
	end
	return false
end

local function heightAt(baseHeight: number, hills: { Hill }, x: number, z: number): number
	local height = baseHeight
	for _, hill in ipairs(hills) do
		local deltaX = x - hill.X
		local deltaZ = z - hill.Z
		local distanceSquaredFromCenter = deltaX * deltaX + deltaZ * deltaZ
		local radiusSquared = hill.Radius * hill.Radius
		if distanceSquaredFromCenter < radiusSquared then
			local surfaceHeight = baseHeight + math.sqrt(radiusSquared - distanceSquaredFromCenter)
			height = math.max(height, surfaceHeight)
		end
	end
	return height
end

local function createHills(config: Config, generator: Generator, roads: { Road }): { Hill }?
	local hills = {}
	local halfWidth = config.Dimensions.Width / 2
	local halfDepth = config.Dimensions.Depth / 2
	local town = config.Town

	for index = 1, config.Terrain.HillCount do
		local accepted: Hill? = nil
		for _ = 1, 120 do
			local radius = nextRange(generator, config.Terrain.MinHillRadius, config.Terrain.MaxHillRadius)
			local point = {
				X = nextRange(generator, -halfWidth + radius, halfWidth - radius),
				Z = nextRange(generator, -halfDepth + radius, halfDepth - radius),
			}
			local townClearance = town.Radius + radius + 24
			if distanceSquared(point, town.Center) > townClearance * townClearance
				and not isNearRoad(point, roads, radius + 24)
			then
				accepted = {
					X = point.X,
					Z = point.Z,
					Radius = radius,
					Material = if index % config.Terrain.MountainEvery == 0 then "Rock" else "Grass",
				}
				break
			end
		end

		if accepted == nil then
			return nil
		end
		table.insert(hills, accepted)
	end

	return hills
end

local function buildingClearanceRadius(building: Building): number
	return math.sqrt((building.Width / 2) ^ 2 + (building.Depth / 2) ^ 2)
end

local function createBuildings(config: Config, generator: Generator, roads: { Road }): { Building }?
	local buildings: { Building } = {}
	local town = config.Town
	local phase = nextUnit(generator) * math.pi * 2
	local angleStep = math.pi * 2 / town.BuildingCount
	for index = 1, town.BuildingCount do
		local placed: Building? = nil
		local targetAngle = phase + (index - 1) * angleStep
		for _ = 1, 120 do
			local angle = targetAngle + nextRange(generator, -angleStep * 0.6, angleStep * 0.6)
			local radius = nextRange(generator, town.Radius * 0.56, town.Radius * 0.72)
			local candidate: Building = {
				X = town.Center.X + math.cos(angle) * radius,
				Z = town.Center.Z + math.sin(angle) * radius,
				Width = nextRange(generator, 24, 36),
				Depth = nextRange(generator, 20, 30),
				Height = nextRange(generator, 10, 15),
				Rotation = nextRange(generator, -0.12, 0.12),
				Variant = math.floor(nextUnit(generator) * 4) + 1,
			}
			local clearance = buildingClearanceRadius(candidate)
			local collidesWithRoad = isNearRoad(candidate, roads, clearance + 5)
			local collidesWithBuilding = false
			for _, existingBuilding in ipairs(buildings) do
				local requiredDistance = clearance + buildingClearanceRadius(existingBuilding)
				if distanceSquared(candidate, existingBuilding) < requiredDistance * requiredDistance then
					collidesWithBuilding = true
					break
				end
			end

			if not collidesWithRoad and not collidesWithBuilding then
				placed = candidate
				break
			end
		end

		if placed == nil then
			return nil
		end
		table.insert(buildings, placed)
	end
	return buildings
end

local function createTrees(config: Config, generator: Generator, roads: { Road }, hills: { Hill }): { Tree }
	local trees: { Tree } = {}
	local vegetation = config.Vegetation
	local desiredCount = math.min(
		vegetation.MaxTrees,
		math.floor(config.Dimensions.Width * config.Dimensions.Depth * vegetation.DensityPerStudSquared)
	)
	local halfWidth = config.Dimensions.Width / 2
	local halfDepth = config.Dimensions.Depth / 2
	local town = config.Town
	local spawnZone = config.SpawnZone

	for _ = 1, desiredCount * 32 do
		if #trees >= desiredCount then
			break
		end

		local point: Point = {
			X = nextRange(generator, -halfWidth + 16, halfWidth - 16),
			Z = nextRange(generator, -halfDepth + 16, halfDepth - 16),
		}
		local scale = nextRange(generator, 0.78, 1.24)
		local minimumTreeSpacing = 5.6 * scale
		local townKeepout = town.Radius + 28
		local spawnKeepout = spawnZone.Radius + 18
		local overlapsExistingTree = false
		for _, existingTree in ipairs(trees) do
			local requiredSpacing = minimumTreeSpacing + 5.6 * existingTree.Scale
			if distanceSquared(point, existingTree) < requiredSpacing * requiredSpacing then
				overlapsExistingTree = true
				break
			end
		end
		if distanceSquared(point, town.Center) > townKeepout * townKeepout
			and distanceSquared(point, spawnZone.Center) > spawnKeepout * spawnKeepout
			and not isNearRoad(point, roads, 26)
			and not overlapsExistingTree
		then
			table.insert(trees, {
				X = point.X,
				Z = point.Z,
				GroundY = heightAt(config.Dimensions.BaseHeight, hills, point.X, point.Z),
				Scale = scale,
				Variant = math.floor(nextUnit(generator) * 3) + 1,
			})
		end
	end

	return trees
end

local MapLayoutGenerator = {}

function MapLayoutGenerator.ValidateConfig(config: any, seed: any?): (boolean, string?)
	return validateConfig(config, seed)
end

function MapLayoutGenerator.DecideStart(isStarted: boolean, existingGenerationStatus: any): (boolean, string)
	if isStarted then
		return false, "already_started"
	end
	if existingGenerationStatus == "Complete" then
		return false, "map_already_exists"
	end
	if existingGenerationStatus ~= nil then
		return false, "incomplete_map_exists"
	end
	return true, "generate"
end

function MapLayoutGenerator.Generate(config: any, requestedSeed: any?): (Layout?, string?)
	local valid, validationError = validateConfig(config, requestedSeed)
	if not valid then
		return nil, validationError
	end

	local validatedConfig = config :: Config
	local seed = (requestedSeed or validatedConfig.Seed) :: number
	local generator: Generator = { State = seed }
	local roads = copyRoads(validatedConfig.Roads :: { Road })
	local hills = createHills(validatedConfig, generator, roads)
	if hills == nil then
		return nil, "unable_to_place_hills"
	end

	local buildings = createBuildings(validatedConfig, generator, roads)
	if buildings == nil then
		return nil, "unable_to_place_buildings"
	end
	local trees = createTrees(validatedConfig, generator, roads, hills)
	local spawnPoints: { SpawnPoint } = {}
	for _, point in ipairs(validatedConfig.SpawnZone.Points) do
		table.insert(spawnPoints, {
			X = point.X,
			Z = point.Z,
			GroundY = heightAt(validatedConfig.Dimensions.BaseHeight, hills, point.X, point.Z),
		})
	end

	return {
		Name = validatedConfig.Name,
		Seed = seed,
		Width = validatedConfig.Dimensions.Width,
		Depth = validatedConfig.Dimensions.Depth,
		BaseHeight = validatedConfig.Dimensions.BaseHeight,
		TerrainDepth = validatedConfig.Dimensions.TerrainDepth,
		MaxHeight = validatedConfig.Dimensions.MaxHeight,
		Hills = hills,
		Roads = roads,
		Buildings = buildings,
		Trees = trees,
		SpawnZone = {
			Id = validatedConfig.SpawnZone.Id,
			Name = validatedConfig.SpawnZone.Name,
			Center = { X = validatedConfig.SpawnZone.Center.X, Z = validatedConfig.SpawnZone.Center.Z },
			Radius = validatedConfig.SpawnZone.Radius,
			Points = spawnPoints,
		},
	}, nil
end

function MapLayoutGenerator.GetRoadSegments(layout: Layout, maxSegmentLength: number): { RoadSegment }
	assert(isFinite(maxSegmentLength) and maxSegmentLength >= 8 and maxSegmentLength <= 128)

	local segments = {}
	for _, road in ipairs(layout.Roads) do
		for pointIndex = 1, #road.Points - 1 do
			local startPoint = road.Points[pointIndex]
			local endPoint = road.Points[pointIndex + 1]
			local deltaX = endPoint.X - startPoint.X
			local deltaZ = endPoint.Z - startPoint.Z
			local horizontalLength = math.sqrt(deltaX * deltaX + deltaZ * deltaZ)
			local segmentCount = math.max(1, math.ceil(horizontalLength / maxSegmentLength))

			for segmentIndex = 1, segmentCount do
				local alphaStart = (segmentIndex - 1) / segmentCount
				local alphaEnd = segmentIndex / segmentCount
				local startX = startPoint.X + deltaX * alphaStart
				local startZ = startPoint.Z + deltaZ * alphaStart
				local endX = startPoint.X + deltaX * alphaEnd
				local endZ = startPoint.Z + deltaZ * alphaEnd
				table.insert(segments, {
					RoadId = road.Id,
					Width = road.Width,
					Start = {
						X = startX,
						Y = heightAt(layout.BaseHeight, layout.Hills, startX, startZ) + 0.55,
						Z = startZ,
					},
					End = {
						X = endX,
						Y = heightAt(layout.BaseHeight, layout.Hills, endX, endZ) + 0.55,
						Z = endZ,
					},
				})
			end
		end
	end
	return segments
end

function MapLayoutGenerator.HeightAt(layout: Layout, x: number, z: number): number
	return heightAt(layout.BaseHeight, layout.Hills, x, z)
end

return table.freeze(MapLayoutGenerator)