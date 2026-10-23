--!strict

local MapConfig = require("../src/shared/config/MapConfig")
local MapLayoutGenerator = require("../src/server/services/MapLayoutGenerator")

local checks = 0

local function assertDeepEqual(left: any, right: any, path: string?)
	local currentPath = path or "layout"
	assert(type(left) == type(right), `type mismatch at {currentPath}`)
	if type(left) ~= "table" then
		assert(left == right, `value mismatch at {currentPath}`)
		return
	end

	for key, value in pairs(left) do
		assertDeepEqual(value, right[key], `{currentPath}.{key}`)
	end
	for key in pairs(right) do
		assert(left[key] ~= nil, `unexpected key at {currentPath}.{key}`)
	end
end

local function distanceSquared(leftX: number, leftZ: number, rightX: number, rightZ: number): number
	local deltaX = leftX - rightX
	local deltaZ = leftZ - rightZ
	return deltaX * deltaX + deltaZ * deltaZ
end

local function distanceToRoadSquared(pointX: number, pointZ: number, roadSegment: any): number
	local startPoint = roadSegment.Start
	local endPoint = roadSegment.End
	local deltaX = endPoint.X - startPoint.X
	local deltaZ = endPoint.Z - startPoint.Z
	local lengthSquared = deltaX * deltaX + deltaZ * deltaZ
	local projection = if lengthSquared == 0
		then 0
		else ((pointX - startPoint.X) * deltaX + (pointZ - startPoint.Z) * deltaZ) / lengthSquared
	local alpha = math.clamp(projection, 0, 1)
	local nearestX = startPoint.X + deltaX * alpha
	local nearestZ = startPoint.Z + deltaZ * alpha
	return distanceSquared(pointX, pointZ, nearestX, nearestZ)
end

local function cross2D(origin: any, first: any, second: any): number
	return (first.X - origin.X) * (second.Z - origin.Z)
		- (first.Z - origin.Z) * (second.X - origin.X)
end

local function segmentDistanceSquared(firstStart: any, firstEnd: any, secondStart: any, secondEnd: any): number
	local firstSideStart = cross2D(firstStart, firstEnd, secondStart)
	local firstSideEnd = cross2D(firstStart, firstEnd, secondEnd)
	local secondSideStart = cross2D(secondStart, secondEnd, firstStart)
	local secondSideEnd = cross2D(secondStart, secondEnd, firstEnd)
	if firstSideStart * firstSideEnd <= 0 and secondSideStart * secondSideEnd <= 0 then
		return 0
	end

	local distance = math.min(
		distanceToRoadSquared(firstStart.X, firstStart.Z, { Start = secondStart, End = secondEnd }),
		distanceToRoadSquared(firstEnd.X, firstEnd.Z, { Start = secondStart, End = secondEnd }),
		distanceToRoadSquared(secondStart.X, secondStart.Z, { Start = firstStart, End = firstEnd }),
		distanceToRoadSquared(secondEnd.X, secondEnd.Z, { Start = firstStart, End = firstEnd })
	)
	return distance
end

local function isRoadConnected(road: any, otherRoads: { any }): boolean
	for roadIndex = 1, #road.Points - 1 do
		local startPoint = road.Points[roadIndex]
		local endPoint = road.Points[roadIndex + 1]
		for _, otherRoad in ipairs(otherRoads) do
			if otherRoad.Id ~= road.Id then
				local combinedRadius = (road.Width + otherRoad.Width) / 2
				for otherIndex = 1, #otherRoad.Points - 1 do
					if segmentDistanceSquared(
						startPoint,
						endPoint,
						otherRoad.Points[otherIndex],
						otherRoad.Points[otherIndex + 1]
					) <= combinedRadius ^ 2 then
						return true
					end
				end
			end
		end
	end
	return false
end

local isConfigValid, configError = MapLayoutGenerator.ValidateConfig(MapConfig)
assert(isConfigValid, `valid config rejected: {configError}`)
checks += 1

local canStart, startDecision = MapLayoutGenerator.DecideStart(false, nil)
assert(canStart and startDecision == "generate")
local canStartAgain, startedDecision = MapLayoutGenerator.DecideStart(true, "Complete")
assert(not canStartAgain and startedDecision == "already_started")
local canDuplicateCompleteMap, completeDecision = MapLayoutGenerator.DecideStart(false, "Complete")
assert(not canDuplicateCompleteMap and completeDecision == "map_already_exists")
local canDuplicatePartialMap, partialDecision = MapLayoutGenerator.DecideStart(false, "Generating")
assert(not canDuplicatePartialMap and partialDecision == "incomplete_map_exists")
checks += 1

local firstLayout, firstError = MapLayoutGenerator.Generate(MapConfig)
assert(firstLayout ~= nil, `layout generation failed: {firstError}`)
local sameSeedLayout, sameSeedError = MapLayoutGenerator.Generate(MapConfig, MapConfig.Seed)
assert(sameSeedLayout ~= nil, `repeat layout generation failed: {sameSeedError}`)
assertDeepEqual(firstLayout, sameSeedLayout)
checks += 1

local otherSeedLayout, otherSeedError = MapLayoutGenerator.Generate(MapConfig, MapConfig.Seed + 1)
assert(otherSeedLayout ~= nil, `alternate seed generation failed: {otherSeedError}`)
assert(firstLayout.Hills[1].X ~= otherSeedLayout.Hills[1].X)
checks += 1

assert(firstLayout.Width == MapConfig.Dimensions.Width)
assert(firstLayout.Depth == MapConfig.Dimensions.Depth)
assert(firstLayout.TerrainDepth == 16)
assert(#firstLayout.Hills == MapConfig.Terrain.HillCount)
assert(#firstLayout.Roads == #MapConfig.Roads)
assert(#firstLayout.Buildings == MapConfig.Town.BuildingCount)
assert(#firstLayout.Trees <= MapConfig.Vegetation.MaxTrees)
local expectedTreeCount = math.min(
	MapConfig.Vegetation.MaxTrees,
	math.floor(firstLayout.Width * firstLayout.Depth * MapConfig.Vegetation.DensityPerStudSquared)
)
assert(#firstLayout.Trees >= math.floor(expectedTreeCount * 0.5))
assert(#firstLayout.SpawnZone.Points == #MapConfig.SpawnZone.Points)
checks += 1

local halfWidth = firstLayout.Width / 2
local halfDepth = firstLayout.Depth / 2
for _, hill in ipairs(firstLayout.Hills) do
	assert(math.abs(hill.X) + hill.Radius <= halfWidth)
	assert(math.abs(hill.Z) + hill.Radius <= halfDepth)
	assert(MapLayoutGenerator.HeightAt(firstLayout, hill.X, hill.Z) <= firstLayout.MaxHeight)
end
for _, road in ipairs(firstLayout.Roads) do
	for _, point in ipairs(road.Points) do
		assert(math.abs(point.X) <= halfWidth and math.abs(point.Z) <= halfDepth)
	end
	assert(isRoadConnected(road, firstLayout.Roads), `{road.Id} no conecta con el resto de caminos`)
end
for _, building in ipairs(firstLayout.Buildings) do
	assert(math.abs(building.X) <= halfWidth and math.abs(building.Z) <= halfDepth)
end
for _, tree in ipairs(firstLayout.Trees) do
	assert(math.abs(tree.X) <= halfWidth and math.abs(tree.Z) <= halfDepth)
end
for _, spawnPoint in ipairs(firstLayout.SpawnZone.Points) do
	local offsetX = spawnPoint.X - firstLayout.SpawnZone.Center.X
	local offsetZ = spawnPoint.Z - firstLayout.SpawnZone.Center.Z
	assert(math.abs(spawnPoint.X) <= halfWidth and math.abs(spawnPoint.Z) <= halfDepth)
	assert(offsetX * offsetX + offsetZ * offsetZ <= firstLayout.SpawnZone.Radius ^ 2)
	assert(spawnPoint.GroundY == MapLayoutGenerator.HeightAt(firstLayout, spawnPoint.X, spawnPoint.Z))
	assert(spawnPoint.GroundY == firstLayout.BaseHeight)
end
checks += 1

local roadSegments = MapLayoutGenerator.GetRoadSegments(firstLayout, 36)
local previousSegmentByRoad = {}
local maximumRoadGrade = 0
for _, roadSegment in ipairs(roadSegments) do
	local previousSegment = previousSegmentByRoad[roadSegment.RoadId]
	if previousSegment ~= nil then
		assert(previousSegment.End.X == roadSegment.Start.X)
		assert(previousSegment.End.Y == roadSegment.Start.Y)
		assert(previousSegment.End.Z == roadSegment.Start.Z)
	end
	assert(roadSegment.Width >= 4)
	assert(roadSegment.Width <= 32)
	local horizontalLength = math.sqrt(
		(roadSegment.End.X - roadSegment.Start.X) ^ 2
			+ (roadSegment.End.Z - roadSegment.Start.Z) ^ 2
	)
	local grade = math.abs(roadSegment.End.Y - roadSegment.Start.Y) / horizontalLength
	maximumRoadGrade = math.max(maximumRoadGrade, grade)
	previousSegmentByRoad[roadSegment.RoadId] = roadSegment
end
assert(#roadSegments > #firstLayout.Roads)
assert(#roadSegments == 88)
assert(maximumRoadGrade < 0.5)
checks += 1

for _, spawnPoint in ipairs(firstLayout.SpawnZone.Points) do
	for _, roadSegment in ipairs(roadSegments) do
		local clearance = roadSegment.Width / 2 + 6
		assert(distanceToRoadSquared(spawnPoint.X, spawnPoint.Z, roadSegment) > clearance * clearance)
	end
	for _, building in ipairs(firstLayout.Buildings) do
		local buildingRadius = math.sqrt((building.Width / 2) ^ 2 + (building.Depth / 2) ^ 2)
		assert(distanceSquared(spawnPoint.X, spawnPoint.Z, building.X, building.Z) > (buildingRadius + 6) ^ 2)
	end
	for _, tree in ipairs(firstLayout.Trees) do
		local canopyRadius = 5.6 * tree.Scale
		assert(distanceSquared(spawnPoint.X, spawnPoint.Z, tree.X, tree.Z) > (canopyRadius + 6) ^ 2)
	end
end

for buildingIndex, building in ipairs(firstLayout.Buildings) do
	local buildingRadius = math.sqrt((building.Width / 2) ^ 2 + (building.Depth / 2) ^ 2)
	for otherIndex = buildingIndex + 1, #firstLayout.Buildings do
		local other = firstLayout.Buildings[otherIndex]
		local otherRadius = math.sqrt((other.Width / 2) ^ 2 + (other.Depth / 2) ^ 2)
		assert(distanceSquared(building.X, building.Z, other.X, other.Z) > (buildingRadius + otherRadius) ^ 2)
	end
	for _, roadSegment in ipairs(roadSegments) do
		local clearance = buildingRadius + roadSegment.Width / 2
		assert(distanceToRoadSquared(building.X, building.Z, roadSegment) > clearance * clearance)
	end
end
checks += 1

local instanceEstimate = 1
	+ 1
	+ #firstLayout.Roads
	+ #roadSegments
	+ 1
	+ #firstLayout.Buildings * 12
	+ 1
	+ #firstLayout.Trees * 3
	+ 1
	+ 1
	+ #firstLayout.SpawnZone.Points
assert(instanceEstimate == 563)
local baseTerrainCells = firstLayout.Width / 4 * (firstLayout.TerrainDepth / 4) * (firstLayout.Depth / 4)
assert(baseTerrainCells == 409600)
local terrainBaseTop = firstLayout.BaseHeight - firstLayout.TerrainDepth / 2 + firstLayout.TerrainDepth / 2
assert(terrainBaseTop == firstLayout.BaseHeight)

local invalidSeedLayout, invalidSeedError = MapLayoutGenerator.Generate(MapConfig, -1)
assert(invalidSeedLayout == nil and invalidSeedError == "invalid_seed")
local tooLargeSeedLayout, tooLargeSeedError = MapLayoutGenerator.Generate(MapConfig, 2147483648)
assert(tooLargeSeedLayout == nil and tooLargeSeedError == "invalid_seed")
checks += 1

local invalidDimensions: any = table.clone(MapConfig)
invalidDimensions.Dimensions = table.clone(MapConfig.Dimensions)
invalidDimensions.Dimensions.Width = 128
local dimensionsValid, dimensionsError = MapLayoutGenerator.ValidateConfig(invalidDimensions)
assert(not dimensionsValid and dimensionsError == "invalid_dimensions")

local oversizedTerrain: any = table.clone(MapConfig)
oversizedTerrain.Dimensions = table.clone(MapConfig.Dimensions)
oversizedTerrain.Dimensions.Width = 4096
oversizedTerrain.Dimensions.Depth = 4096
local terrainBudgetValid, terrainBudgetError = MapLayoutGenerator.ValidateConfig(oversizedTerrain)
assert(not terrainBudgetValid and terrainBudgetError == "invalid_dimensions")
checks += 1

local invalidSpawn: any = table.clone(MapConfig)
invalidSpawn.SpawnZone = table.clone(MapConfig.SpawnZone)
invalidSpawn.SpawnZone.Points = { { X = halfWidth + 1, Z = 0 } }
local spawnValid, spawnError = MapLayoutGenerator.ValidateConfig(invalidSpawn)
assert(not spawnValid and spawnError == "spawn_out_of_bounds")

local spawnOutsideTown: any = table.clone(MapConfig)
spawnOutsideTown.SpawnZone = table.clone(MapConfig.SpawnZone)
spawnOutsideTown.SpawnZone.Center = { X = 140, Z = 0 }
local townSpawnValid, townSpawnError = MapLayoutGenerator.ValidateConfig(spawnOutsideTown)
assert(not townSpawnValid and townSpawnError == "invalid_spawn_zone")

for treeIndex, tree in ipairs(firstLayout.Trees) do
	assert(distanceSquared(tree.X, tree.Z, MapConfig.Town.Center.X, MapConfig.Town.Center.Z)
		> (MapConfig.Town.Radius + 28) ^ 2)
	for _, roadSegment in ipairs(roadSegments) do
		assert(distanceToRoadSquared(tree.X, tree.Z, roadSegment) > 26 ^ 2)
	end
	for otherIndex = treeIndex + 1, #firstLayout.Trees do
		local other = firstLayout.Trees[otherIndex]
		local minimumTreeSpacing = 5.6 * (tree.Scale + other.Scale)
		assert(distanceSquared(tree.X, tree.Z, other.X, other.Z) > minimumTreeSpacing ^ 2)
	end
end
checks += 1
assert(baseTerrainCells <= 2000000)

local invalidRoad: any = table.clone(MapConfig)
invalidRoad.Roads = table.clone(MapConfig.Roads)
invalidRoad.Roads[1] = table.clone(MapConfig.Roads[1])
invalidRoad.Roads[1].Points = table.clone(MapConfig.Roads[1].Points)
invalidRoad.Roads[1].Points[1] = { X = halfWidth - 1, Z = 0 }
local roadValid, roadError = MapLayoutGenerator.ValidateConfig(invalidRoad)
assert(not roadValid and roadError == "road_out_of_bounds")
checks += 1

print(
	`Fase 4: {checks} grupos pasaron; mapa {firstLayout.Width}x{firstLayout.Depth}, `
		.. `{#firstLayout.Hills} colinas, {#firstLayout.Roads} caminos, `
		.. `{#firstLayout.Buildings} edificios, {#firstLayout.Trees} arboles, `
		.. `{#firstLayout.SpawnZone.Points} spawns; aproximadamente {instanceEstimate} instancias, `
		.. `{baseTerrainCells} celdas base de terreno; pendiente maxima {maximumRoadGrade}.`
)