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
			if actionName == "SetWaveMode" then
				GlobalConfigService.SetWaveMode(payload.Endless, payload.FixedCount)
				return { success = true }
			elseif actionName == "SetPromocode" then
				PromocodeService.SetCode(payload.Code, payload.Def)
				return { success = true }
			elseif actionName == "GiveGold" then
				local target = game:GetService("Players"):FindFirstChild(payload.Name or "")
				if target then
					DataService.AddGold(target, payload.Amount or 0, "admin")
				end
				return { success = true }
			end
			return { success = false }
		end
	end
end

return AdminService
