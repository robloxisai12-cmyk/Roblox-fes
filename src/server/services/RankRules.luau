--!strict

type RankDefinition = {
	Level: number,
	Permissions: { [string]: boolean },
}

local rankDefinitions: { [string]: RankDefinition } = {
	Recruit = {
		Level = 1,
		Permissions = {
			["squad.create"] = true,
			["squad.join"] = true,
			["squad.leave"] = true,
		},
	},
	Private = {
		Level = 2,
		Permissions = {
			["squad.create"] = true,
			["squad.join"] = true,
			["squad.leave"] = true,
		},
	},
	Corporal = {
		Level = 3,
		Permissions = {
			["squad.create"] = true,
			["squad.join"] = true,
			["squad.leave"] = true,
			["squad.assignRoles"] = true,
		},
	},
	Sergeant = {
		Level = 4,
		Permissions = {
			["squad.create"] = true,
			["squad.join"] = true,
			["squad.leave"] = true,
			["squad.assignRoles"] = true,
			["squad.disbandAny"] = true,
			["company.assign"] = true,
		},
	},
	Commander = {
		Level = 5,
		Permissions = {
			["squad.create"] = true,
			["squad.join"] = true,
			["squad.leave"] = true,
			["squad.assignRoles"] = true,
			["squad.disbandAny"] = true,
			["company.assign"] = true,
			["rank.assign"] = true,
		},
	},
}

local RankRules = {}

function RankRules.IsRank(rank: string): boolean
	return rankDefinitions[rank] ~= nil
end

function RankRules.HasPermission(rank: string, permission: string): boolean
	local definition = rankDefinitions[rank]
	return definition ~= nil and definition.Permissions[permission] == true
end

function RankRules.CanAssignRank(actorRank: string, targetRank: string): boolean
	local actor = rankDefinitions[actorRank]
	local target = rankDefinitions[targetRank]

	return actor ~= nil
		and target ~= nil
		and actor.Permissions["rank.assign"] == true
		and actor.Level > target.Level
end

function RankRules.GetRanks(): { string }
	local ranks = {}
	for rank in pairs(rankDefinitions) do
		table.insert(ranks, rank)
	end
	table.sort(ranks, function(left, right)
		return rankDefinitions[left].Level < rankDefinitions[right].Level
	end)
	return ranks
end

return table.freeze(RankRules)