--!strict

local MapGenerationService = require(script.Parent.services.MapGenerationService)
local PlayerDataService = require(script.Parent.services.PlayerDataService)
local SquadService = require(script.Parent.services.SquadService)
local InventoryService = require(script.Parent.services.InventoryService)
local MedicalService = require(script.Parent.services.MedicalService)
local LogisticsService = require(script.Parent.services.LogisticsService)
local CombatService = require(script.Parent.services.CombatService)
local RadioService = require(script.Parent.services.RadioService)
local MatchService = require(script.Parent.services.MatchService)

local mapGenerated, mapStatus = MapGenerationService.Start()
if not mapGenerated then
	warn(`Sierra de Guardia: map generation failed ({mapStatus})`)
end

PlayerDataService.Start()
SquadService.Start()
InventoryService.Start()
MedicalService.Start()
LogisticsService.Start()
CombatService.Start()
RadioService.Start()
MatchService.Start()