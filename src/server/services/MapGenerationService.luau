--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local shared = ReplicatedStorage:WaitForChild("Shared")
local configFolder = shared:WaitForChild("config")
local configModule = configFolder:WaitForChild("MapConfig") :: ModuleScript
local config = require(configModule)
local MapLayoutGenerator = require(script.Parent.MapLayoutGenerator)

local MAP_FOLDER_NAME = "SierraDeGuardiaMap"
local MAX_ROAD_SEGMENT_LENGTH = 36

type GeneratedLayout = {
	Name: string,
	Seed: number,
	Width: number,
	Depth: number,
	BaseHeight: number,
	TerrainDepth: number,
	MaxHeight: number,
	Hills: { any },
	Roads: { any },
	Buildings: { any },
	Trees: { any },
	SpawnZone: any,
}

local isStarted = false
local generatedLayout: GeneratedLayout? = nil
local MapGenerationService = {}

local function newPart(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	material: Enum.Material,
	color: Color3,
	canCollide: boolean
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = canCollide
	part.CanTouch = false
	part.CanQuery = canCollide
	part.Material = material
	part.Color = color
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function buildTerrain(layout: GeneratedLayout)
	local terrain = Workspace.Terrain
	local baseSize = Vector3.new(layout.Width, layout.TerrainDepth, layout.Depth)
	local baseCenter = Vector3.new(0, layout.BaseHeight - layout.TerrainDepth / 2, 0)
	terrain:FillBlock(CFrame.new(baseCenter), baseSize, Enum.Material.Ground)

	for _, hill in ipairs(layout.Hills) do
		local material = if hill.Material == "Rock" then Enum.Material.Rock else Enum.Material.Grass
		terrain:FillBall(Vector3.new(hill.X, layout.BaseHeight, hill.Z), hill.Radius, material)
	end
end

local function buildRoads(folder: Folder, layout: GeneratedLayout)
	local roadsFolder = Instance.new("Folder")
	roadsFolder.Name = "Roads"
	roadsFolder.Parent = folder

	local roadFolders: { [string]: Folder } = {}
	local segments = MapLayoutGenerator.GetRoadSegments(layout, MAX_ROAD_SEGMENT_LENGTH)
	for _, roadSegment in ipairs(segments) do
		local roadFolder = roadFolders[roadSegment.RoadId]
		if roadFolder == nil then
			roadFolder = Instance.new("Folder")
			roadFolder.Name = roadSegment.RoadId
			roadFolder.Parent = roadsFolder
			roadFolders[roadSegment.RoadId] = roadFolder
		end

		local startPosition = Vector3.new(roadSegment.Start.X, roadSegment.Start.Y, roadSegment.Start.Z)
		local endPosition = Vector3.new(roadSegment.End.X, roadSegment.End.Y, roadSegment.End.Z)
		local segmentLength = (endPosition - startPosition).Magnitude
		local midpoint = (startPosition + endPosition) / 2
		local segment = newPart(
			roadFolder,
			"Segment",
			Vector3.new(roadSegment.Width, 1, segmentLength + 1),
			CFrame.lookAt(midpoint, endPosition),
			Enum.Material.Asphalt,
			Color3.fromRGB(66, 68, 65),
			true
		)
		segment:SetAttribute("RoadId", roadSegment.RoadId)
	end
end

local WALL_COLORS = {
	Color3.fromRGB(210, 188, 145),
	Color3.fromRGB(194, 174, 133),
	Color3.fromRGB(205, 165, 139),
	Color3.fromRGB(222, 205, 167),
}

local ROOF_COLORS = {
	Color3.fromRGB(142, 75, 51),
	Color3.fromRGB(154, 84, 56),
	Color3.fromRGB(126, 68, 49),
	Color3.fromRGB(163, 94, 63),
}

local function buildTown(folder: Folder, layout: GeneratedLayout)
	local townFolder = Instance.new("Folder")
	townFolder.Name = "Pueblo"
	townFolder:SetAttribute("TownName", config.Town.Name)
	townFolder.Parent = folder

	for buildingIndex, building in ipairs(layout.Buildings) do
		local buildingFolder = Instance.new("Folder")
		buildingFolder.Name = string.format("Casa_%02d", buildingIndex)
		buildingFolder.Parent = townFolder

		local groundY = MapLayoutGenerator.HeightAt(layout, building.X, building.Z)
		local baseCFrame = CFrame.new(building.X, groundY, building.Z)
			* CFrame.Angles(0, building.Rotation, 0)
		local wallColor = WALL_COLORS[building.Variant]
		local roofColor = ROOF_COLORS[building.Variant]
		local wallThickness = 0.8
		local doorWidth = 3.5
		local doorHeight = 7
		local frontWallWidth = (building.Width - doorWidth) / 2

		newPart(
			buildingFolder,
			"Cimiento",
			Vector3.new(building.Width + 2, 1, building.Depth + 2),
			baseCFrame * CFrame.new(0, 0.5, 0),
			Enum.Material.Concrete,
			Color3.fromRGB(119, 113, 101),
			true
		)
		newPart(
			buildingFolder,
			"MuroTrasero",
			Vector3.new(building.Width, building.Height, wallThickness),
			baseCFrame * CFrame.new(0, building.Height / 2 + 1, building.Depth / 2),
			Enum.Material.Sandstone,
			wallColor,
			true
		)
		for _, side in ipairs({ -1, 1 }) do
			newPart(
				buildingFolder,
				"MuroLateral",
				Vector3.new(wallThickness, building.Height, building.Depth),
				baseCFrame * CFrame.new(side * building.Width / 2, building.Height / 2 + 1, 0),
				Enum.Material.Sandstone,
				wallColor,
				true
			)
			newPart(
				buildingFolder,
				"MuroFrontal",
				Vector3.new(frontWallWidth, building.Height, wallThickness),
				baseCFrame
					* CFrame.new(side * (doorWidth / 2 + frontWallWidth / 2), building.Height / 2 + 1, -building.Depth / 2),
				Enum.Material.Sandstone,
				wallColor,
				true
			)
		end
		local doorHeaderHeight = building.Height - doorHeight
		newPart(
			buildingFolder,
			"Dintel",
			Vector3.new(doorWidth, doorHeaderHeight, wallThickness),
			baseCFrame * CFrame.new(0, doorHeight + doorHeaderHeight / 2 + 1, -building.Depth / 2),
			Enum.Material.Sandstone,
			wallColor,
			true
		)
		newPart(
			buildingFolder,
			"Azotea",
			Vector3.new(building.Width + 2, 1.5, building.Depth + 2),
			baseCFrame * CFrame.new(0, building.Height + 1.75, 0),
			Enum.Material.Brick,
			roofColor,
			true
		)
		newPart(
			buildingFolder,
			"Puerta",
			Vector3.new(3.5, 7, 0.5),
			baseCFrame * CFrame.new(0, 4.5, -building.Depth / 2 - 0.28),
			Enum.Material.WoodPlanks,
			Color3.fromRGB(91, 63, 45),
			false
		)
		for side = -1, 1, 2 do
			newPart(
				buildingFolder,
				"Ventana",
				Vector3.new(4, 3.5, 0.35),
				baseCFrame * CFrame.new(side * building.Width * 0.29, building.Height * 0.58 + 1, -building.Depth / 2 - wallThickness / 2 - 0.1),
				Enum.Material.Glass,
				Color3.fromRGB(113, 153, 157),
				false
			)
		end
	end
end

local TREE_TRUNK_COLORS = {
	Color3.fromRGB(92, 68, 47),
	Color3.fromRGB(107, 78, 49),
	Color3.fromRGB(82, 65, 48),
}

local TREE_CANOPY_COLORS = {
	Color3.fromRGB(62, 104, 59),
	Color3.fromRGB(76, 119, 66),
	Color3.fromRGB(53, 91, 57),
}

local function buildVegetation(folder: Folder, layout: GeneratedLayout)
	local vegetationFolder = Instance.new("Folder")
	vegetationFolder.Name = "Vegetacion"
	vegetationFolder.Parent = folder

	for treeIndex, tree in ipairs(layout.Trees) do
		local scale = tree.Scale
		local trunkHeight = 7 * scale
		local treeFolder = Instance.new("Folder")
		treeFolder.Name = string.format("Arbol_%03d", treeIndex)
		treeFolder.Parent = vegetationFolder

		local trunk = newPart(
			treeFolder,
			"Tronco",
			Vector3.new(trunkHeight, 1.4 * scale, 1.4 * scale),
			CFrame.new(tree.X, tree.GroundY + trunkHeight / 2, tree.Z) * CFrame.Angles(0, 0, math.pi / 2),
			Enum.Material.Wood,
			TREE_TRUNK_COLORS[tree.Variant],
			true
		)
		trunk.Shape = Enum.PartType.Cylinder

		local canopy = newPart(
			treeFolder,
			"Copa",
			Vector3.new(9 * scale, 8 * scale, 9 * scale),
			CFrame.new(tree.X, tree.GroundY + trunkHeight + 1.5 * scale, tree.Z),
			Enum.Material.LeafyGrass,
			TREE_CANOPY_COLORS[tree.Variant],
			false
		)
		canopy.Shape = Enum.PartType.Ball
	end
end

local function buildSpawnZone(folder: Folder, layout: GeneratedLayout)
	local spawnFolder = Instance.new("Folder")
	spawnFolder.Name = "SpawnSeguro"
	spawnFolder:SetAttribute("ZoneId", layout.SpawnZone.Id)
	spawnFolder:SetAttribute("Radius", layout.SpawnZone.Radius)
	spawnFolder.Parent = folder

	local center = layout.SpawnZone.Center
	local centerY = MapLayoutGenerator.HeightAt(layout, center.X, center.Z)
	local zoneMarker = newPart(
		spawnFolder,
		"LimiteZona",
		Vector3.new(layout.SpawnZone.Radius * 2, 0.2, layout.SpawnZone.Radius * 2),
		CFrame.new(center.X, centerY + 0.12, center.Z),
		Enum.Material.ForceField,
		Color3.fromRGB(93, 164, 135),
		false
	)
	zoneMarker.Transparency = 1
	zoneMarker:SetAttribute("SafeZone", true)

	for index, point in ipairs(layout.SpawnZone.Points) do
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = string.format("Aparicion_%02d", index)
		spawn.Size = Vector3.new(8, 1, 8)
		spawn.CFrame = CFrame.new(point.X, point.GroundY + spawn.Size.Y / 2, point.Z)
		spawn.Anchored = true
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.AllowTeamChangeOnTouch = false
		spawn.Material = Enum.Material.Grass
		spawn.Color = Color3.fromRGB(93, 132, 82)
		spawn:SetAttribute("SafeZoneId", layout.SpawnZone.Id)
		spawn:SetAttribute("MapSeed", layout.Seed)
		spawn.Parent = spawnFolder
	end
end

local function buildMap(folder: Folder, layout: GeneratedLayout)
	buildTerrain(layout)
	buildRoads(folder, layout)
	buildTown(folder, layout)
	buildVegetation(folder, layout)
	buildSpawnZone(folder, layout)
end

function MapGenerationService.Start(): (boolean, string)
	local existingFolder = Workspace:FindFirstChild(MAP_FOLDER_NAME)
	local existingStatus = if existingFolder ~= nil then existingFolder:GetAttribute("GenerationStatus") else nil
	local shouldGenerate, decision = MapLayoutGenerator.DecideStart(isStarted, existingStatus)
	if not shouldGenerate then
		local existingMapIsComplete = decision == "map_already_exists"
		local serviceCompleted = decision == "already_started" and generatedLayout ~= nil
		return existingMapIsComplete or serviceCompleted, decision
	end

	local isValid, validationError = MapLayoutGenerator.ValidateConfig(config)
	if not isValid then
		warn(`MapGenerationService: invalid map config: {validationError}`)
		return false, validationError or "invalid_config"
	end

	local layout, generationError = MapLayoutGenerator.Generate(config)
	if layout == nil then
		warn(`MapGenerationService: unable to generate layout: {generationError}`)
		return false, generationError or "layout_failed"
	end

	isStarted = true
	local mapFolder = Instance.new("Folder")
	mapFolder.Name = MAP_FOLDER_NAME
	mapFolder:SetAttribute("GenerationStatus", "Generating")
	mapFolder:SetAttribute("Seed", layout.Seed)
	mapFolder:SetAttribute("MapWidth", layout.Width)
	mapFolder:SetAttribute("MapDepth", layout.Depth)
	mapFolder.Parent = Workspace

	local success, buildError = pcall(buildMap, mapFolder, layout)
	if not success then
		mapFolder:SetAttribute("GenerationStatus", "Failed")
		warn(`MapGenerationService: map construction failed: {buildError}`)
		return false, "build_failed"
	end

	mapFolder:SetAttribute("GenerationStatus", "Complete")
	generatedLayout = layout
	return true, "generated"
end

function MapGenerationService.GetMapInfo()
	if generatedLayout == nil then
		return nil
	end

	return {
		Name = generatedLayout.Name,
		Seed = generatedLayout.Seed,
		Width = generatedLayout.Width,
		Depth = generatedLayout.Depth,
		HillCount = #generatedLayout.Hills,
		RoadCount = #generatedLayout.Roads,
		BuildingCount = #generatedLayout.Buildings,
		TreeCount = #generatedLayout.Trees,
		SpawnCount = #generatedLayout.SpawnZone.Points,
	}
end

return table.freeze(MapGenerationService)