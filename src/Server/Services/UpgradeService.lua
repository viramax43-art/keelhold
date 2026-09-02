local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UpgradesConfig = require(ReplicatedStorage.Shared.Config.UpgradesConfig)
local StatCalculator = require(ReplicatedStorage.Shared.Util.StatCalculator)
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)

local UpgradeService = {}

function UpgradeService:Init(services)
	local DataService = services.DataService
	local RemoteService = services.RemoteService
	local upgrade = RemoteService.GetRemote(RemoteNames.UpgradeStat)
	if upgrade then
		upgrade.OnServerInvoke = function(player, statName)
			local profile = DataService.GetProfile(player)
			if not profile or not UpgradesConfig.Stats[statName] then
				return { success = false }
			end
			local level = profile.Upgrades[statName] or 0
			local cost = StatCalculator.GetUpgradeCost(statName, level)
			if cost == math.huge then
				return { success = false, error = "Max level" }
			end
			if (profile.XP or 0) < cost then
				return { success = false, error = "Not enough XP" }
			end
			profile.XP -= cost
			profile.Upgrades[statName] = level + 1
			DataService.NotifyProfile(player)
			DataService.SaveProfile(player, true)
			return { success = true, level = level + 1 }
		end
	end
end

return UpgradeService
