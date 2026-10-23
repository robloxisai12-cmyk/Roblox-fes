--!strict

local weapons = table.freeze({
	Rifle = table.freeze({
		DisplayName = "Fusil",
		MagazineCapacity = 30,
		InitialMagazine = 30,
		InitialReserve = 90,
		RoundsPerMinute = 420,
		Damage = 22,
		Range = 500,
		ReloadSeconds = 2.1,
		Recoil = table.freeze({
			PitchDegrees = 1.1,
			YawDegrees = 0.35,
		}),
	}),
	Sidearm = table.freeze({
		DisplayName = "Pistola",
		MagazineCapacity = 12,
		InitialMagazine = 12,
		InitialReserve = 36,
		RoundsPerMinute = 300,
		Damage = 18,
		Range = 180,
		ReloadSeconds = 1.6,
		Recoil = table.freeze({
			PitchDegrees = 1.8,
			YawDegrees = 0.55,
		}),
	}),
})

return table.freeze({
	DefaultWeapon = "Rifle",
	Weapons = weapons,
	Radio = table.freeze({
		ItemId = "FieldRadio",
		DisplayName = "Radio de campaña",
	}),
})
