--!strict

local PlayerDataService = require(script.Parent.PlayerDataService)
local RankRules = require(script.Parent.RankRules)

local RankService = {}

function RankService.GetRank(player: Player): string?
	local session = PlayerDataService.GetSession(player)
	if session == nil or not RankRules.IsRank(session.Rank) then
		return nil
	end

	return session.Rank
end

function RankService.HasPermission(player: Player, permission: string): boolean
	local rank = RankService.GetRank(player)
	return rank ~= nil and RankRules.HasPermission(rank, permission)
end

function RankService.AssignRank(actor: Player, target: Player, targetRank: string): (boolean, string)
	local actorRank = RankService.GetRank(actor)
	if actorRank == nil or PlayerDataService.GetSession(target) == nil then
		return false, "session_unavailable"
	end
	if not RankRules.IsRank(targetRank) then
		return false, "invalid_rank"
	end
	if not RankRules.CanAssignRank(actorRank, targetRank) then
		return false, "permission_denied"
	end
	if not PlayerDataService.SetRank(target, targetRank) then
		return false, "session_unavailable"
	end

	local role = if targetRank == "Commander" then "Commander" else "Rifleman"
	PlayerDataService.SetRole(target, role)
	return true, "rank_assigned"
end

return table.freeze(RankService)