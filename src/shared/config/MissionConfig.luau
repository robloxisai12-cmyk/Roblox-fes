--!strict

return table.freeze({
	MinimumPlayers = 1,
	PreparationSeconds = 15,
	MatchDurationSeconds = 900,
	ResultSeconds = 8,
	CleanupSeconds = 2,
	StateUpdateSeconds = 0.5,
	MaxCaptureContributors = 3,
	MaxObservedHorizontalSpeed = 65,
	MaxObservedVerticalSpeed = 220,
	MovementTolerance = 12,
	RadioAnnouncements = true,
	Objectives = table.freeze({
		table.freeze({
			Id = "secure_valley",
			Name = "Asegurar el valle",
			Description = "Mantengan presencia en la zona del valle.",
			Kind = "capture",
			X = 350,
			Z = 105,
			Radius = 42,
			RequiredProgress = 60,
		}),
		table.freeze({
			Id = "supply_valley",
			Name = "Abastecer el valle",
			Description = "Entreguen suministros medicos en ValleyDelivery.",
			Kind = "delivery",
			PointId = "ValleyDelivery",
			ResourceId = "Medical",
			RequiredAmount = 2,
			X = 420,
			Z = 75,
			Radius = 30,
		}),
	}),
})
