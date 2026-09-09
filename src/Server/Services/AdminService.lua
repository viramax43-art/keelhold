local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AdminConfig = require(ReplicatedStorage.Shared.Config.AdminConfig)
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)

local AdminService = {}

local function isAdmin(player: Player): boolean
	for _, id in ipairs(AdminConfig.AdminUserIds or {}) do
		if player.UserId == id then
			return true
		end
	end
	return false
end

function AdminService:Init(services)
	local RemoteService = services.RemoteService
	local GlobalConfigService = services.GlobalConfigService
	local PromocodeService = services.PromocodeService
	local DataService = services.DataService

	local getCfg = RemoteService.GetRemote(RemoteNames.AdminGetConfig)
	if getCfg then
		getCfg.OnServerInvoke = function(player)
			if not isAdmin(player) then
				return { success = false }
			end
			return { success = true, waveMode = GlobalConfigService.GetWaveMode() }
		end
	end

	local action = RemoteService.GetRemote(RemoteNames.AdminAction)
	if action then
		action.OnServerInvoke = function(player, actionName, payload)
			if not isAdmin(player) then
				return { success = false, error = "Not admin" }
			end
			payload = type(payload) == "table" and payload or {}
			if actionName == "SetWaveMode" then
				local fixedCount = math.clamp(math.floor(tonumber(payload.FixedCount) or 20), 1, 500)
				GlobalConfigService.SetWaveMode(payload.Endless == true, fixedCount)
				return { success = true }
			elseif actionName == "SetPromocode" then
				if type(payload.Code) ~= "string" or type(payload.Def) ~= "table" then
					return { success = false, error = "Bad promocode" }
				end
				PromocodeService.SetCode(payload.Code, payload.Def)
				return { success = true }
			elseif actionName == "GiveGold" then
				local target = game:GetService("Players"):FindFirstChild(tostring(payload.Name or ""))
				if target then
					local amount = math.clamp(math.floor(tonumber(payload.Amount) or 0), -1000000, 1000000)
					DataService.AddGold(target, amount, "admin")
					return { success = true }
				end
				return { success = false, error = "Player not found" }
			end
			return { success = false }
		end
	end
end

return AdminService
