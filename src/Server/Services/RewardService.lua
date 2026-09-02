--[[
	RewardService — золото/XP за киллы и волны.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local EnemiesConfig = require(ReplicatedStorage.Shared.Config.EnemiesConfig)
local CoopMultiplier = require(ReplicatedStorage.Shared.Util.CoopMultiplier)

local RewardService = {}
local DataService
local waveKillGold = {}
local waveKillXP = {}
local battleContext = { friendCount = 0, difficulty = "Normal" }

function RewardService.SetBattleContext(ctx)
	battleContext = ctx or battleContext
end

function RewardService.ClearWaveStats()
	table.clear(waveKillGold)
	table.clear(waveKillXP)
end

local function multipliers()
	local diff = GameConfig.Difficulties[battleContext.difficulty or "Normal"]
	local rewardMult = (diff and diff.RewardMultiplier) or 1
	local coop = CoopMultiplier.Compute(battleContext.friendCount or 0)
	return rewardMult * coop
end

function RewardService.OnEnemyKilled(player: Player)
	local m = multipliers()
	local gold = math.floor((EnemiesConfig.Rewards.Gold or 12) * m)
	local xp = math.floor((EnemiesConfig.Rewards.XP or 8) * m)
	DataService.AddGold(player, gold, "kill")
	DataService.AddXP(player, xp, "kill")
	waveKillGold[player.UserId] = (waveKillGold[player.UserId] or 0) + gold
	waveKillXP[player.UserId] = (waveKillXP[player.UserId] or 0) + xp
	local profile = DataService.GetProfile(player)
	if profile and profile.Stats then
		profile.Stats.TotalKills = (profile.Stats.TotalKills or 0) + 1
	end
end

function RewardService.GrantWaveClear(players: { Player }, wave: number)
	local m = multipliers()
	local wr = GameConfig.WaveRewards
	local gold = math.floor(((wr.GoldBonus or 35) + (wr.BonusPerWave or 4) * wave) * m)
	local xp = math.floor(((wr.XPBonus or 15) + (wr.BonusPerWave or 4) * wave) * m)
	for _, p in ipairs(players) do
		if p.Parent then
			DataService.AddGold(p, gold, "wave_clear")
			DataService.AddXP(p, xp, "wave_clear")
			local profile = DataService.GetProfile(p)
			if profile then
				profile.HighestWave = math.max(profile.HighestWave or 0, wave)
				if profile.Stats then
					profile.Stats.TotalWaves = (profile.Stats.TotalWaves or 0) + 1
				end
				if wave % (GameConfig.CheckpointInterval or 5) == 0 then
					profile.LastCheckpoint = wave
				end
				DataService.SaveProfile(p, true)
			end
		end
	end
end

function RewardService.GrantDefeatConsolation(players: { Player }, wave: number)
	local m = multipliers()
	local wr = GameConfig.WaveRewards
	local pct = wr.DefeatPercent or 0.25
	local gold = math.floor(((wr.GoldBonus or 35) + (wr.BonusPerWave or 4) * wave) * m * pct)
	local xp = math.floor(((wr.XPBonus or 15) + (wr.BonusPerWave or 4) * wave) * m * pct)
	for _, p in ipairs(players) do
		if p.Parent then
			DataService.AddGold(p, gold, "defeat_consolation")
			DataService.AddXP(p, xp, "defeat_consolation")
			DataService.SaveProfile(p, true)
		end
	end
end

function RewardService:Init(services)
	DataService = services.DataService
end

return RewardService
