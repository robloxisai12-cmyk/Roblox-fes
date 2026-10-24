--!strict

local TacticalUIRules = require("../src/shared/config/TacticalUIRules")
local HUDLayout = require("../src/shared/HUDLayout")
local HUDRules = require("../src/shared/HUDRules")
local MapConfig = require("../src/shared/config/MapConfig")
local LogisticsConfig = require("../src/shared/config/LogisticsConfig")

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
check(
	invalidViewport.PanelWidth == 460 and invalidViewport.PanelHeight == 520,
	"invalid viewport falls back to safe desktop dimensions"
)

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

check(TacticalUIRules.GetCondition(0, 100, 1, 1, true) == "MUERTO", "death takes priority over stale injury flags")
check(
	TacticalUIRules.GetCombatMessage("no_ammo", false):find("Recarga") ~= nil,
	"empty magazine feedback explains the next action"
)
check(
	TacticalUIRules.GetCombatMessage("no_reserve_ammo", false):find("reserva") ~= nil,
	"missing reserve has explicit feedback"
)
check(
	TacticalUIRules.GetCombatMessage("magazine_full", false):find("lleno") ~= nil,
	"full magazine explains a rejected reload"
)
check(
	TacticalUIRules.GetCombatMessage("reloading", false) ~= "",
	"weapon switching during reload explains the rejection"
)
check(TacticalUIRules.GetCombatMessage("reload_complete", true) ~= "", "reload completion has confirmation")
check(TacticalUIRules.GetCombatMessage("future_error", false) ~= "", "unknown errors are not silently swallowed")
check(TacticalUIRules.GetCombatMessage("miss", true) == "", "normal shot misses do not spam feedback")

-- HUD layout: every visible element stays on screen, never overlaps another and respects the
-- areas Roblox reserves for its own touch controls. Sizes are the *usable* area (after the top bar).
local usableSizes = {
	{ 320, 520 }, -- small portrait phone
	{ 360, 582 }, -- portrait phone
	{ 667, 262 }, -- short landscape phone
	{ 800, 302 }, -- typical landscape phone
	{ 812, 317 },
	{ 932, 340 }, -- large landscape phone
	{ 1024, 710 }, -- tablet
	{ 1280, 662 }, -- desktop window
	{ 1920, 1022 }, -- full HD
}
local layoutCases = 0
local minTouch = math.huge
for _, size in ipairs(usableSizes) do
	for _, mode in ipairs({ "walking", "driving" }) do
		for _, chat in ipairs({ true, false }) do
			local layout = HUDLayout.Compute(size[1], size[2], { Mode = mode, ChatExpanded = chat, Touch = true })
			local label = string.format("%dx%d %s chat=%s", size[1], size[2], mode, tostring(chat))
			local visible: { any } = {}
			for _, box in ipairs(layout.Boxes) do
				if box.Visible then
					table.insert(visible, box)
					check(HUDLayout.Inside(box.Rect, size[1], size[2]), box.Name .. " fits on screen at " .. label)
					local touchSized = box.Name:match("^Menu_") ~= nil
						or box.Name:match("^Shortcut_") ~= nil
						or box.Name:match("Button$") ~= nil
						or box.Name == "Radio"
						or box.Name:match("^Drive_") ~= nil
						or box.Name == "Fire"
						or box.Name == "Reload"
					if touchSized then
						minTouch = math.min(minTouch, math.min(box.Rect.W, box.Rect.H))
						check(math.min(box.Rect.W, box.Rect.H) >= 40, box.Name .. " touch target at " .. label)
					end
				end
			end
			for i = 1, #visible do
				for j = i + 1, #visible do
					check(
						not HUDLayout.Overlaps(visible[i].Rect, visible[j].Rect),
						visible[i].Name .. " overlaps " .. visible[j].Name .. " at " .. label
					)
				end
			end
			for _, slot in ipairs(layout.Slots) do
				check(HUDLayout.Inside(slot, size[1], size[2]), "hotbar slot fits at " .. label)
				check(slot.W >= 44 and slot.H >= 44, "hotbar slot touch size at " .. label)
			end
			if mode == "walking" then
				for _, box in ipairs(visible) do
					check(
						not HUDLayout.Overlaps(box.Rect, layout.Reserved.Jump),
						box.Name .. " keeps the native jump area free at " .. label
					)
					check(
						not HUDLayout.Overlaps(box.Rect, layout.Reserved.Thumb),
						box.Name .. " keeps the native thumbstick area free at " .. label
					)
				end
			end
			layoutCases += 1
		end
	end
end
check(layoutCases == #usableSizes * 4 and minTouch >= 40, "layout checked for every size, mode and chat state")

local phoneLayout = HUDLayout.Compute(800, 302, { Mode = "walking", ChatExpanded = false })
check(not HUDLayout.Profile(800, 302).Regular and #phoneLayout.Shortcuts >= 1, "phones keep menu shortcuts in a row")
check(#HUDLayout.Compute(1280, 662, {}).MenuItems == 4, "regular screens list the four menu entries")
check(#HUDLayout.Compute(1280, 662, {}).Slots == 5 and #phoneLayout.Slots == 4, "hotbar adapts to screen size")
check(HUDLayout.Compute(0, 0, {}).Width == 1280, "invalid viewport falls back to a safe desktop size")
check(HUDLayout.Compute(360, 582, {}).SecondRow, "portrait phones move the compass to its own row")

-- Compass, zone and gauge rules use only configured data.
check(HUDRules.CompassOffset(350, 10) == -20 and HUDRules.CompassOffset(10, 350) == 20, "compass wraps across north")
check(HUDRules.CompassOffset(180, 0) == 180, "compass offset covers the opposite side")
check(HUDRules.Cardinal(HUDRules.Heading(1, 0)) == "E" and HUDRules.Cardinal(315) == "NO", "compass uses Spanish cardinals")
check(HUDRules.Zone(0, 0, MapConfig, LogisticsConfig) == MapConfig.SpawnZone.Name, "spawn plaza is recognised")
check(HUDRules.Zone(-90, -166, MapConfig, LogisticsConfig) == "Deposito de San Isidro", "depot is the most specific zone")
check(HUDRules.Zone(420, 75, MapConfig, LogisticsConfig) == "Punto logistico del valle", "delivery point is recognised")
check(HUDRules.Zone(0, 150, MapConfig, LogisticsConfig) == MapConfig.Town.Name, "town zone is recognised")
check(HUDRules.Zone(500, 500, MapConfig, LogisticsConfig) == MapConfig.Name, "open ground falls back to the map name")
check(HUDRules.Fraction(50, 100) == 0.5 and HUDRules.Fraction(150, 100) == 1, "gauge fraction is clamped")
check(HUDRules.Fraction(nil, 100) == 0 and HUDRules.Fraction(5, 0) == 0, "missing data never invents a gauge value")
check(HUDRules.Fraction(0 / 0, 100) == 0, "NaN never reaches a gauge")

print(`Fase 10: {checks} comprobaciones de interfaz pasaron.`)
