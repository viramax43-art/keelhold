local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)
local Util = require(ReplicatedStorage.Shared.Util.Util)

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
			if not profile or not DataService.CanMutateProfile(player) then
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
			local before = Util.DeepCopy(profile)
			profile.DailyReward.LastClaimTime = now
			profile.DailyReward.StreakDay = streak
			profile.Gold = (profile.Gold or 0) + (reward.Gold or 0)
			profile.XP = (profile.XP or 0) + (reward.XP or 0)
			profile.TotalXP = (profile.TotalXP or 0) + (reward.XP or 0)
			profile.Level = Util.LevelFromTotalXP(profile.TotalXP, GameConfig.XPPerLevel, GameConfig.XPPerLevelGrowth)
			DataService.MarkDirty(player, "DailyReward")
			DataService.NotifyProfile(player)
			local ok, err = DataService.FlushProfile(player, "DailyReward", false)
			if not ok then
				DataService.RestoreSnapshot(player, before)
				return { success = false, error = err or "Не удалось сохранить профиль" }
			end
			return { success = true, streak = streak, reward = reward }
		end
	end
end

return DailyRewardService
