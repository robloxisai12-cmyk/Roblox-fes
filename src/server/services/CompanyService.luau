--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RankService = require(script.Parent.RankService)

local shared = ReplicatedStorage:WaitForChild("Shared")
local configFolder = shared:WaitForChild("config")
local configModule = configFolder:WaitForChild("OrganizationConfig") :: ModuleScript
local config = require(configModule)

local CompanyService = {}

function CompanyService.GetDefinitions()
	local definitions = {}
	for _, company in ipairs(config.Companies) do
		table.insert(definitions, {
			Id = company.Id,
			Name = company.Name,
		})
	end
	return definitions
end

function CompanyService.ResolveRequestedCompany(player: Player, companyId: any): (string?, string?)
	if companyId == nil then
		return config.DefaultCompanyId, nil
	end
	if type(companyId) ~= "string" then
		return nil, "invalid_company"
	end

	local knownCompany = false
	for _, company in ipairs(config.Companies) do
		if company.Id == companyId then
			knownCompany = true
			break
		end
	end
	if not knownCompany then
		return nil, "invalid_company"
	end
	if companyId ~= config.DefaultCompanyId and not RankService.HasPermission(player, "company.assign") then
		return nil, "permission_denied"
	end

	return companyId, nil
end

function CompanyService.GetPublicCompanies(registry: any)
	local companies = {}
	for _, company in ipairs(config.Companies) do
		table.insert(companies, {
			id = company.Id,
			name = company.Name,
			squadCount = registry:GetCompanySquadCount(company.Id),
		})
	end
	return companies
end

return table.freeze(CompanyService)