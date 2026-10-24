import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const modules = {
	InventoryConfig: "src/shared/config/InventoryConfig.luau",
	MedicalConfig: "src/shared/config/MedicalConfig.luau",
	LogisticsConfig: "src/shared/config/LogisticsConfig.luau",
	InventoryRules: "src/server/services/InventoryRules.luau",
	MedicalRules: "src/server/services/MedicalRules.luau",
	CombatRules: "src/server/services/CombatRules.luau",
	CombatRequestRules: "src/server/services/CombatRequestRules.luau",
	InventoryService: "src/server/services/InventoryService.luau",
	MedicalService: "src/server/services/MedicalService.luau",
	CombatService: "src/server/services/CombatService.luau",
};
const hudModules = {
	Cleanup: "src/client/hud/Cleanup.luau",
	GameAdapter: "src/client/hud/GameAdapter.luau",
	HUDView: "src/client/hud/HUDView.luau",
	HUDController: "src/client/hud/HUDController.luau",
	VehicleControls: "src/client/hud/VehicleControls.luau",
	HUDRules: "src/shared/HUDRules.luau",
	VehicleInputRules: "src/server/services/VehicleInputRules.luau",
	LogisticsService: "src/server/services/LogisticsService.luau",
	LogisticsRules: "src/server/services/LogisticsRules.luau",
	VehicleRules: "src/server/services/VehicleRules.luau",
	CombatRequestRules: modules.CombatRequestRules,
	LogisticsConfig: modules.LogisticsConfig,
	MapConfig: "src/shared/config/MapConfig.luau",
};
const longString = (text) => {
	let equals = "";
	while (text.includes(`]${equals}]`)) equals += "=";
	return `[${equals}[${text}]${equals}]`;
};
async function runHarness(modulePaths, harnessPath) {
	const entries = await Promise.all(
		Object.entries(modulePaths).map(async ([name, path]) =>
			`[${JSON.stringify(name)}] = ${longString(await readFile(resolve(root, path), "utf8"))}`),
	);
	const harness = await readFile(resolve(root, harnessPath), "utf8");
	const scratch = await mkdtemp(resolve(tmpdir(), "roblox-mobile-test-"));
	try {
		const file = resolve(scratch, "runtime.luau");
		await writeFile(file, `local sources = {\n${entries.join(",\n")}\n}\n${harness}`);
		const result = spawnSync(process.env.LUAU_BIN || "luau", [file], { stdio: "inherit" });
		if (result.error) throw result.error;
		if (result.status !== 0) throw new Error(`${harnessPath} exited ${result.status}`);
	} finally {
		await rm(scratch, { recursive: true, force: true });
	}
}
await runHarness(modules, "tests/mobile-runtime.luau");
await runHarness(hudModules, "tests/hud-runtime.luau");
