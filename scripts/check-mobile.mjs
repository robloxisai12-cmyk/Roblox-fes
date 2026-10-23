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
const longString = (text) => {
	let equals = "";
	while (text.includes(`]${equals}]`)) equals += "=";
	return `[${equals}[${text}]${equals}]`;
};
const entries = await Promise.all(
	Object.entries(modules).map(
		async ([name, path]) =>
			`[${JSON.stringify(name)}] = ${longString(await readFile(resolve(root, path), "utf8"))}`,
	),
);
const harness = await readFile(
	resolve(root, "tests/mobile-runtime.luau"),
	"utf8",
);
const scratch = await mkdtemp(resolve(tmpdir(), "roblox-mobile-test-"));
try {
	const file = resolve(scratch, "mobile-runtime.luau");
	await writeFile(
		file,
		`local sources = {\n${entries.join(",\n")}\n}\n${harness}`,
	);
	const result = spawnSync(process.env.LUAU_BIN || "luau", [file], {
		stdio: "inherit",
	});
	if (result.error) throw result.error;
	process.exitCode = result.status ?? 1;
} finally {
	await rm(scratch, { recursive: true, force: true });
}
