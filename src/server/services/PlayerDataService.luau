--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

type SessionDefaults = {
	Rank: string,
	Role: string,
}

type SessionData = {
	UserId: number,
	Name: string,
	DisplayName: string,
	JoinedAt: number,
	Rank: string,
	Role: string,
	Inventory: { [string]: string },
	Permissions: { [string]: boolean },
}

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local configFolder = sharedFolder:WaitForChild("config")
local defaultsModule = configFolder:WaitForChild("PlayerSessionDefaults") :: ModuleScript
local defaults = require(defaultsModule) :: SessionDefaults
local organizationModule = configFolder:WaitForChild("OrganizationConfig") :: ModuleScript
local organizationConfig = require(organizationModule)

local sessions: { [Player]: SessionData } = {}
local connections: { RBXScriptConnection } = {}
local isStarted = false

local PlayerDataService = {}

local function createSession(player: Player): SessionData?
	local userId = player.UserId
	local name = player.Name
	local displayName = player.DisplayName

	if userId <= 0 or userId % 1 ~= 0 or name == "" or displayName == "" then
		warn(`PlayerDataService: invalid player data for {player}`)
		return nil
	end

	return {
		UserId = userId,
		Name = name,
		DisplayName = displayName,
		JoinedAt = os.time(),
		Rank = defaults.Rank,
		Role = defaults.Role,
		Inventory = {},
		Permissions = {},
	}
end

local function addPlayer(player: Player)
	if sessions[player] ~= nil or player.Parent ~= Players then
		return
	end

	local session = createSession(player)
	if session ~= nil then
		sessions[player] = session
	end
end

local function removePlayer(player: Player)
	sessions[player] = nil
end

local function copySession(session: SessionData): SessionData
	return {
		UserId = session.UserId,
		Name = session.Name,
		DisplayName = session.DisplayName,
		JoinedAt = session.JoinedAt,
		Rank = session.Rank,
		Role = session.Role,
		Inventory = table.clone(session.Inventory),
		Permissions = table.clone(session.Permissions),
	}
end

function PlayerDataService.Start()
	if isStarted then
		return
	end

	isStarted = true
	table.insert(connections, Players.PlayerAdded:Connect(addPlayer))
	table.insert(connections, Players.PlayerRemoving:Connect(removePlayer))

	for _, player in ipairs(Players:GetPlayers()) do
		addPlayer(player)
	end
end

function PlayerDataService.GetSession(player: Player): SessionData?
	local session = sessions[player]
	if session == nil then
		return nil
	end

	return copySession(session)
end

function PlayerDataService.SetRole(player: Player, role: string): boolean
	if type(role) ~= "string" or organizationConfig.Roles[role] ~= true then
		return false
	end

	local session = sessions[player]
	if session == nil then
		return false
	end

	session.Role = role
	return true
end

function PlayerDataService.SetRank(player: Player, rank: string): boolean
	if type(rank) ~= "string" or rank == "" or #rank > 32 then
		return false
	end

	local session = sessions[player]
	if session == nil then
		return false
	end

	session.Rank = rank
	return true
end

function PlayerDataService.Stop()
	if not isStarted then
		return
	end

	isStarted = false
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(sessions)
end

return PlayerDataService