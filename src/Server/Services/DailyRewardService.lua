local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)

local DailyRewardService = {}

local function calendarDay(ts: number): number
	return math.floor(ts / 86400)
end

function DailyRewardService:Init(services)
	local DataService = services.DataService
	local RemoteService = services.RemoteService
	local claim = RemoteService.GetRemote(RemoteNames.ClaimDailyReward)
	if claim then
		claim.OnServerInvoke = function(player)
			local profile = DataService.GetProfile(player)
			if not profile then
				return { success = false }
			end
			local now = os.time()
			local last = profile.DailyReward.LastClaimTime or 0
			if calendarDay(now) == calendarDay(last) then
				return { success = false, error = "Already claimed today" }
			end
			local streak = profile.DailyReward.StreakDay or 0
			if calendarDay(now) == calendarDay(last) + 1 then
				streak = (streak % 7) + 1
			else
				streak = 1
			end
			local reward = GameConfig.DailyRewards[streak] or GameConfig.DailyRewards[1]
			profile.DailyReward.LastClaimTime = now
			profile.DailyReward.StreakDay = streak
			DataService.AddGold(player, reward.Gold or 0, "daily")
			DataService.AddXP(player, reward.XP or 0, "daily")
			DataService.SaveProfile(player, true)
			return { success = true, streak = streak, reward = reward }
		end
	end
end

return DailyRewardService
