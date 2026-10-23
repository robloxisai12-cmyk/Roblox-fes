--!strict

local MapGenerationService = require(script.Parent.services.MapGenerationService)
local PlayerDataService = require(script.Parent.services.PlayerDataService)
local SquadService = require(script.Parent.services.SquadService)

local mapGenerated, mapStatus = MapGenerationService.Start()
if not mapGenerated then
	warn(`Sierra de Guardia: map generation failed ({mapStatus})`)
end

PlayerDataService.Start()
SquadService.Start()