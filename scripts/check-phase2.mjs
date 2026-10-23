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
		/<Item class="Folder" referent="[^"]+">\s*<Properties>\s*<string name="Name">Remotes<\/string>\s*<\/Properties>\s*<Item class="RemoteFunction" referent="[^"]+">\s*<Properties>\s*<string name="Name">SquadRequest<\/string>\s*<\/Properties>\s*<\/Item>\s*<\/Item>/s,
		"SquadRequest debe compilar como RemoteFunction bajo la carpeta Remotes",
	);
	assert.equal(
		[...placeXml.matchAll(/<Item class="Remote(?:Event|Function)"/g)].length,
		1,
		"Solo debe compilarse un remoto de mutación/listado",
	);
	console.log("Proyecto: versión Rojo, ubicaciones de módulos y remoto único comprobados.");
} finally {
	rmSync(tempDirectory, { recursive: true, force: true });
}