--!strict

local items = table.freeze({
	Bandage = table.freeze({
		DisplayName = "Vendaje",
		InitialCount = 3,
		UseSeconds = 1,
		BleedReduction = 2,
		HealAmount = 0,
		MaxSeverity = 1,
	}),
	Medkit = table.freeze({
		DisplayName = "Botiquin",
		InitialCount = 1,
		UseSeconds = 2,
		BleedReduction = 6,
		HealAmount = 35,
		MaxSeverity = 3,
	}),
	EmergencyKit = table.freeze({
		DisplayName = "Kit de emergencia",
		InitialCount = 1,
		UseSeconds = 4,
	}),
})

return table.freeze({
	Items = items,
	MaxWounds = 8,
	SeverityThresholds = table.freeze({
		ModerateDamage = 20,
		SevereDamage = 40,
	}),
	BleedRateBySeverity = table.freeze({
		[1] = 0.5,
		[2] = 1.5,
		[3] = 3,
	}),
	BleedTickSeconds = 1,
	MaxBleedDamagePerTick = 6,
	IncapacitationEnabled = true,
	IncapacitationHealth = 1,
	IncapacitationDuration = 45,
	ReviveHealth = 35,
	TreatmentRange = 12,
	MedicOnlyForAllyTreatment = true,
	TreatmentCooldown = 0.5,
	RequestWindowSeconds = 1,
	MaxRequestsPerWindow = 8,
})
