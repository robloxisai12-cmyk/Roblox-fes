import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";

const candidates = [
	process.env.ROJO_BIN,
	"rojo",
	join(homedir(), ".aftman", "bin", "rojo"),
].filter(Boolean);

function runRojo(args) {
	for (const executable of candidates) {
		const result = spawnSync(executable, args, { encoding: "utf8" });
		if (result.error?.code === "ENOENT") {
			continue;
		}

		assert.ifError(result.error);
		assert.equal(
			result.status,
			0,
			`${executable} ${args.join(" ")} failed:\n${result.stderr}`,
		);
		return result.stdout.trim();
	}

	throw new Error("No se encontró Rojo. Instala Rojo 7.7.0 con Aftman o define ROJO_BIN.");
}

assert.equal(runRojo(["--version"]), "Rojo 7.7.0");
const bootstrapSource = readFileSync("src/server/Bootstrap.server.luau", "utf8");
assert.equal(
	bootstrapSource.match(/MapGenerationService\.Start\(\)/g)?.length ?? 0,
	1,
	"MapGenerationService debe iniciarse una sola vez en el bootstrap del servidor",
);
const startupOrder = [
	"MapGenerationService.Start()",
	"PlayerDataService.Start()",
	"SquadService.Start()",
	"InventoryService.Start()",
	"MedicalService.Start()",
	"LogisticsService.Start()",
	"CombatService.Start()",
	"RadioService.Start()",
	"MatchService.Start()",
];
let previousStartupIndex = -1;
for (const call of startupOrder) {
	const currentStartupIndex = bootstrapSource.indexOf(call);
	assert.ok(currentStartupIndex > previousStartupIndex, `Orden de arranque inválido o ausente: ${call}`);
	previousStartupIndex = currentStartupIndex;
}

const tempDirectory = mkdtempSync(join(tmpdir(), "sierra-fase2-"));
try {
	const sourcemapPath = join(tempDirectory, "sourcemap.json");
	runRojo(["sourcemap", "default.project.json", "--output", sourcemapPath]);
	const sourcemap = JSON.parse(readFileSync(sourcemapPath, "utf8"));
	const entries = new Map();

	function collect(node, parentPath = "") {
		const path = parentPath ? `${parentPath}/${node.name}` : node.name;
		entries.set(path, node);
		for (const child of node.children ?? []) {
			collect(child, path);
		}
	}

	collect(sourcemap);

	const expected = [
		[
			"SierraDeGuardia/ServerScriptService/Server/Bootstrap",
			"Script",
			"src/server/Bootstrap.server.luau",
		],
		[
			"SierraDeGuardia/ServerScriptService/Server/services/PlayerDataService",
			"ModuleScript",
			"src/server/services/PlayerDataService.luau",
		],
		[
			"SierraDeGuardia/ServerScriptService/Server/services/SquadService",
			"ModuleScript",
			"src/server/services/SquadService.luau",
		],
		[
			"SierraDeGuardia/ServerScriptService/Server/services/SquadRegistry",
			"ModuleScript",
			"src/server/services/SquadRegistry.luau",
		],
		[
			"SierraDeGuardia/ServerScriptService/Server/services/SquadRequestRules",
			"ModuleScript",
			"src/server/services/SquadRequestRules.luau",
		],
		[
			"SierraDeGuardia/ServerScriptService/Server/services/RankService",
			"ModuleScript",
			"src/server/services/RankService.luau",
		],
		[
			"SierraDeGuardia/ServerScriptService/Server/services/RankRules",
			"ModuleScript",
			"src/server/services/RankRules.luau",
		],
		[
			"SierraDeGuardia/ServerScriptService/Server/services/CompanyService",
			"ModuleScript",
			"src/server/services/CompanyService.luau",
		],
		[
			"SierraDeGuardia/ServerScriptService/Server/services/MapLayoutGenerator",
			"ModuleScript",
			"src/server/services/MapLayoutGenerator.luau",
		],
		[
			"SierraDeGuardia/ServerScriptService/Server/services/MapGenerationService",
			"ModuleScript",
			"src/server/services/MapGenerationService.luau",
		],
		[
			"SierraDeGuardia/ReplicatedStorage/Shared/config/PlayerSessionDefaults",
			"ModuleScript",
			"src/shared/config/PlayerSessionDefaults.luau",
		],
		[
			"SierraDeGuardia/ReplicatedStorage/Shared/config/OrganizationConfig",
			"ModuleScript",
			"src/shared/config/OrganizationConfig.luau",
		],
		[
			"SierraDeGuardia/ReplicatedStorage/Shared/config/MapConfig",
			"ModuleScript",
			"src/shared/config/MapConfig.luau",
		],
		[
			"SierraDeGuardia/ReplicatedStorage/Shared/config/InventoryConfig",
			"ModuleScript",
			"src/shared/config/InventoryConfig.luau",
		],
		[
			"SierraDeGuardia/ReplicatedStorage/Shared/config/MedicalConfig",
			"ModuleScript",
			"src/shared/config/MedicalConfig.luau",
		],
		[
			"SierraDeGuardia/ReplicatedStorage/Shared/config/LogisticsConfig",
			"ModuleScript",
			"src/shared/config/LogisticsConfig.luau",
		],
		[
			"SierraDeGuardia/ReplicatedStorage/Shared/config/RadioConfig",
			"ModuleScript",
			"src/shared/config/RadioConfig.luau",
		],
		[
			"SierraDeGuardia/ReplicatedStorage/Shared/config/MissionConfig",
			"ModuleScript",
			"src/shared/config/MissionConfig.luau",
		],
		[
			"SierraDeGuardia/ReplicatedStorage/Shared/config/TacticalUIRules",
			"ModuleScript",
			"src/shared/config/TacticalUIRules.luau",
		],
		[
			"SierraDeGuardia/ServerScriptService/Server/services/InventoryService",
			"ModuleScript",
			"src/server/services/InventoryService.luau",
		],
		[
			"SierraDeGuardia/ServerScriptService/Server/services/CombatService",
			"ModuleScript",
			"src/server/services/CombatService.luau",
		],
		[
			"SierraDeGuardia/ServerScriptService/Server/services/InventoryRules",
			"ModuleScript",
			"src/server/services/InventoryRules.luau",
		],
		[
			"SierraDeGuardia/ServerScriptService/Server/services/CombatRequestRules",
			"ModuleScript",
			"src/server/services/CombatRequestRules.luau",
		],
		[
			"SierraDeGuardia/ServerScriptService/Server/services/CombatRules",
			"ModuleScript",
			"src/server/services/CombatRules.luau",
		],
		[
			"SierraDeGuardia/ServerScriptService/Server/services/MedicalService",
			"ModuleScript",
			"src/server/services/MedicalService.luau",
		],
		[
			"SierraDeGuardia/ServerScriptService/Server/services/MedicalRules",
			"ModuleScript",
			"src/server/services/MedicalRules.luau",
		],
		[
			"SierraDeGuardia/ServerScriptService/Server/services/LogisticsService",
			"ModuleScript",
			"src/server/services/LogisticsService.luau",
		],
		[
			"SierraDeGuardia/ServerScriptService/Server/services/LogisticsRules",
			"ModuleScript",
			"src/server/services/LogisticsRules.luau",
		],
		[
			"SierraDeGuardia/ServerScriptService/Server/services/VehicleRules",
			"ModuleScript",
			"src/server/services/VehicleRules.luau",
		],
		[
			"SierraDeGuardia/ServerScriptService/Server/services/RadioService",
			"ModuleScript",
			"src/server/services/RadioService.luau",
		],
		[
			"SierraDeGuardia/ServerScriptService/Server/services/RadioRules",
			"ModuleScript",
			"src/server/services/RadioRules.luau",
		],
		[
			"SierraDeGuardia/ServerScriptService/Server/services/MatchRules",
			"ModuleScript",
			"src/server/services/MatchRules.luau",
		],
		[
			"SierraDeGuardia/ServerScriptService/Server/services/MatchService",
			"ModuleScript",
			"src/server/services/MatchService.luau",
		],
		[
			"SierraDeGuardia/StarterPlayer/StarterPlayerScripts/Client/CombatController",
			"LocalScript",
			"src/client/CombatController.client.luau",
		],
		[
			"SierraDeGuardia/StarterPlayer/StarterPlayerScripts/Client/MedicalController",
			"LocalScript",
			"src/client/MedicalController.client.luau",
		],
		[
			"SierraDeGuardia/StarterPlayer/StarterPlayerScripts/Client/LogisticsController",
			"LocalScript",
			"src/client/LogisticsController.client.luau",
		],
		[
			"SierraDeGuardia/StarterPlayer/StarterPlayerScripts/Client/RadioController",
			"LocalScript",
			"src/client/RadioController.client.luau",
		],
		[
			"SierraDeGuardia/StarterPlayer/StarterPlayerScripts/Client/MissionController",
			"LocalScript",
			"src/client/MissionController.client.luau",
		],
		[
			"SierraDeGuardia/StarterPlayer/StarterPlayerScripts/Client/TacticalHUD",
			"LocalScript",
			"src/client/TacticalHUD.client.luau",
		],
	];

	for (const [path, className, filePath] of expected) {
		const entry = entries.get(path);
		assert.ok(entry, `Falta en sourcemap: ${path}`);
		assert.equal(entry.className, className, `Clase incorrecta en ${path}`);
		assert.ok(entry.filePaths?.includes(filePath), `Falta origen ${filePath}`);
	}

	const placePath = join(tempDirectory, "place.rbxlx");
	runRojo(["build", "default.project.json", "--output", placePath]);
	const placeXml = readFileSync(placePath, "utf8");
	assert.match(
		placeXml,
		/<Item class="Folder" referent="[^"]+">\s*<Properties>\s*<string name="Name">Remotes<\/string>\s*<\/Properties>\s*<Item class="RemoteEvent" referent="[^"]+">\s*<Properties>\s*<string name="Name">CombatRequest<\/string>\s*<\/Properties>\s*<\/Item>\s*<Item class="RemoteEvent" referent="[^"]+">\s*<Properties>\s*<string name="Name">MissionRequest<\/string>\s*<\/Properties>\s*<\/Item>\s*<Item class="RemoteEvent" referent="[^"]+">\s*<Properties>\s*<string name="Name">RadioRequest<\/string>\s*<\/Properties>\s*<\/Item>\s*<Item class="RemoteFunction" referent="[^"]+">\s*<Properties>\s*<string name="Name">SquadRequest<\/string>\s*<\/Properties>\s*<\/Item>\s*<\/Item>/s,
		"CombatRequest, MissionRequest, RadioRequest y SquadRequest deben compilar con sus clases y nombres en Remotes",
	);
	assert.equal(
		[...placeXml.matchAll(/<Item class="Remote(?:Event|Function)"/g)].length,
		4,
		"Solo deben compilarse SquadRequest, CombatRequest, RadioRequest y MissionRequest",
	);
	console.log("Proyecto: versión Rojo, ubicaciones de módulos y remotos declarados comprobados.");
} finally {
	rmSync(tempDirectory, { recursive: true, force: true });
}