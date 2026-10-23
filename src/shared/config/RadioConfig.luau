--!strict

return table.freeze({
	GeneralChannel = table.freeze({
		Id = "general",
		DisplayName = "General",
		Range = 600,
	}),
	SquadChannel = table.freeze({
		Range = 900,
		DisplayNamePrefix = "Escuadron",
	}),
	MaxMessageBytes = 240,
	RequestWindowSeconds = 10,
	MaxRequestsPerWindow = 30,
	MessageWindowSeconds = 8,
	MaxMessagesPerWindow = 4,
})
