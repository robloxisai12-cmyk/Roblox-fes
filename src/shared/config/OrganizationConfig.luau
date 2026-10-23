--!strict

local roles = table.freeze({
	Rifleman = true,
	Medic = true,
	Engineer = true,
	SquadLeader = true,
	Commander = true,
})

local companies = table.freeze({
	table.freeze({ Id = "sierra", Name = "Compania Sierra" }),
	table.freeze({ Id = "norte", Name = "Compania Norte" }),
	table.freeze({ Id = "sur", Name = "Compania Sur" }),
})

return table.freeze({
	Roles = roles,
	AssignableSquadRoles = table.freeze({
		Rifleman = true,
		Medic = true,
		Engineer = true,
	}),
	Companies = companies,
	DefaultCompanyId = "sierra",
	MaxSquadsPerCompany = 8,
	MaxMembersPerSquad = 8,
	MinSquadNameLength = 3,
	MaxSquadNameLength = 32,
})