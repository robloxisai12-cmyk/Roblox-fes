--!strict

local TacticalUIRules = require("../src/shared/config/TacticalUIRules")

local checks = 0

local function check(condition: boolean, message: string)
	assert(condition, message)
	checks += 1
end

local phone = TacticalUIRules.GetProfile(320, 568)
check(phone.IsCompact, "phone profile uses compact layout")
check(phone.PanelWidth <= 296 and phone.PanelHeight <= 472, "phone panels fit the available viewport")
check(phone.Scale >= 0.9 and phone.Scale < 1, "phone text uses a compact but readable scale")
check(phone.TouchTargetSize >= 44, "interactive touch targets meet the recommended minimum")

local tablet = TacticalUIRules.GetProfile(800, 1280)
check(not tablet.IsCompact, "tablet profile uses expanded layout")
check(tablet.PanelWidth == 460, "expanded panels are capped to a readable width")

local desktop = TacticalUIRules.GetProfile(1920, 1080)
check(desktop.Scale == 1.2 and desktop.PanelHeight == 520, "large screens use a capped panel and readable scale")

local invalidViewport = TacticalUIRules.GetProfile(math.huge, 0)
check(invalidViewport.PanelWidth == 460 and invalidViewport.PanelHeight == 520, "invalid viewport falls back to safe desktop dimensions")

check(
	TacticalUIRules.GetCondition(1, 100, 0, 0, true) == "INCAPACITADO",
	"incapacitation takes priority in the character condition"
)
check(
	TacticalUIRules.GetCondition(50, 100, 2, 1.5, false) == "SANGRANDO 1.5/s",
	"bleeding is visible ahead of a general wound count"
)
check(TacticalUIRules.GetCondition(75, 100, 0, 0, false) == "HERIDO", "reduced health is visible")
check(TacticalUIRules.GetCondition(100, 100, 0, 0, false) == "ESTABLE", "full health reports stable condition")
check(TacticalUIRules.GetAmmoText(8, 25, false) == "8  |  25", "ammunition snapshot is formatted")
check(TacticalUIRules.GetAmmoText(0, 25, true) == "RECARGANDO", "reload state is surfaced")

print(`Fase 10: {checks} comprobaciones de interfaz pasaron.`)
