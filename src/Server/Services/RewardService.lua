--[[
	RewardService — золото/XP за урон, киллы и волны.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local EnemiesConfig = require(ReplicatedStorage.Shared.Config.EnemiesConfig)
local UpgradesConfig = require(ReplicatedStorage.Shared.Config.UpgradesConfig)
local StatCalculator = require(ReplicatedStorage.Shared.Util.StatCalculator)
local CoopMultiplier = require(ReplicatedStorage.Shared.Util.CoopMultiplier)

local RewardService = {}
local DataService
local waveKillGold = {}
local waveKillXP = {}
local sessionGold = {}
local sessionXP = {}
local fracGold = {}
local fracXP = {}
local battleContext = { friendCount = 0, difficulty = "Normal" }
local currentWave = 1

function RewardService.SetBattleContext(ctx)
	battleContext = ctx or battleContext
	currentWave = 1
	table.clear(sessionGold)
	table.clear(sessionXP)
	table.clear(fracGold)
	table.clear(fracXP)
	table.clear(waveKillGold)
	table.clear(waveKillXP)
end

function RewardService.SetCurrentWave(wave: number)
	currentWave = math.max(1, tonumber(wave) or 1)
end

function RewardService.ClearWaveStats()
	table.clear(waveKillGold)
	table.clear(waveKillXP)
	table.clear(fracGold)
	table.clear(fracXP)
end

local function multipliers()
	local diff = GameConfig.Difficulties[battleContext.difficulty or "Normal"]
	local rewardMult = (diff and diff.RewardMultiplier) or 1
	local coop = CoopMultiplier.Compute(battleContext.friendCount or 0)
	-- Тайкун-скейлинг дохода от номера волны
	local rw = EnemiesConfig.Rewards or {}
	local waveMult = math.min(1 + (rw.WaveGrowth or 0) * (currentWave - 1), rw.MaxWaveMult or 6)
	return rewardMult * coop * waveMult
end

-- Персональный множитель дохода: престиж (+5%/очко) + вознесение (+25%/ур.)
-- + прокачанные статы GoldGain / XPGain.
local function incomeMults(player: Player): (number, number)
	local profile = DataService and DataService.GetProfile(player)
	if not profile then
		return 1, 1
	end
	local points = (profile.PrestigePoints or 0)
	local asc = (profile.Ascensions or 0)
	local upgrades = profile.Upgrades or {}
	local prestigeCfg = UpgradesConfig.Prestige
	local ascCfg = UpgradesConfig.Ascension
	local base = 1
		+ points * (prestigeCfg.IncomeBonusPerPoint or 0.05)
		+ asc * (ascCfg.IncomeBonusPerAscension or 0.25)
	local goldStat = StatCalculator.GetUpgradeStat("GoldGain", upgrades.GoldGain or 0, points, asc)
	local xpStat = StatCalculator.GetUpgradeStat("XPGain", upgrades.XPGain or 0, points, asc)
	return base * math.max(1, goldStat), base * math.max(1, xpStat)
end

local function credit(player: Player, goldAdd: number, xpAdd: number, reason: string)
	if goldAdd <= 0 and xpAdd <= 0 then
		return
	end
	local gm, xm = incomeMults(player)
	goldAdd = math.floor(goldAdd * gm)
	xpAdd = math.floor(xpAdd * xm)
	if goldAdd <= 0 and xpAdd <= 0 then
		return
	end
	local uid = player.UserId
	if goldAdd > 0 then
		DataService.AddGold(player, goldAdd, reason)
		waveKillGold[uid] = (waveKillGold[uid] or 0) + goldAdd
		sessionGold[uid] = (sessionGold[uid] or 0) + goldAdd
	end
	if xpAdd > 0 then
		DataService.AddXP(player, xpAdd, reason)
		waveKillXP[uid] = (waveKillXP[uid] or 0) + xpAdd
		sessionXP[uid] = (sessionXP[uid] or 0) + xpAdd
	end
end

-- Награда пропорционально урону (доля от награды за килл)
function RewardService.OnEnemyDamaged(player: Player, damage: number, maxHP: number)
	if not player or not player.Parent or damage <= 0 then
		return
	end
	maxHP = math.max(maxHP or 1, 1)
	local m = multipliers()
	local uid = player.UserId
	local gShare = ((EnemiesConfig.Rewards.Gold or 12) * m) * (damage / maxHP)
	local xShare = ((EnemiesConfig.Rewards.XP or 8) * m) * (damage / maxHP)
	fracGold[uid] = (fracGold[uid] or 0) + gShare
	fracXP[uid] = (fracXP[uid] or 0) + xShare
	local payG = math.floor(fracGold[uid])
	local payX = math.floor(fracXP[uid])
	if payG > 0 then
		fracGold[uid] -= payG
	end
	if payX > 0 then
		fracXP[uid] -= payX
	end
	credit(player, payG, payX, "damage")
end

function RewardService.OnEnemyKilled(player: Player)
	local profile = DataService.GetProfile(player)
	if profile and DataService.IsProfileLoaded(player) and profile.Stats then
		profile.Stats.TotalKills = (profile.Stats.TotalKills or 0) + 1
		DataService.MarkDirty(player, "TotalKills")
		DataService.SaveProfile(player, false)
	end
	-- добираем дробные остатки за этот удар
	local uid = player.UserId
	local payG = math.floor((fracGold[uid] or 0) + 0.001)
	local payX = math.floor((fracXP[uid] or 0) + 0.001)
	if payG > 0 or payX > 0 then
		fracGold[uid] = (fracGold[uid] or 0) - payG
		fracXP[uid] = (fracXP[uid] or 0) - payX
		credit(player, payG, payX, "kill_remainder")
	end
end

function RewardService.GetWaveEarnings(player: Player): (number, number)
	local uid = player.UserId
	return waveKillGold[uid] or 0, waveKillXP[uid] or 0
end

function RewardService.GetSessionEarnings(player: Player): (number, number)
	local uid = player.UserId
	return sessionGold[uid] or 0, sessionXP[uid] or 0
end

function RewardService.GrantWaveClear(players: { Player }, wave: number): { [number]: { gold: number, xp: number } }
	local m = multipliers()
	local wr = GameConfig.WaveRewards
	-- Чекпоинт-волны (каждые CheckpointInterval) дают усиленную награду — milestone как в тайкунах
	local isCheckpoint = wave % (GameConfig.CheckpointInterval or 5) == 0
	local checkpointMult = isCheckpoint and (wr.CheckpointMult or 3) or 1
	local gold = math.floor(((wr.GoldBonus or 35) + (wr.BonusPerWave or 4) * wave) * m * checkpointMult)
	local xp = math.floor(((wr.XPBonus or 15) + (wr.BonusPerWave or 4) * wave) * m * checkpointMult)
	local perPlayer = {}
	for _, p in ipairs(players) do
		if p.Parent then
			local beforeG, beforeX = RewardService.GetWaveEarnings(p)
			credit(p, gold, xp, "wave_clear")
			local profile = DataService.GetProfile(p)
			if profile and DataService.IsProfileLoaded(p) then
				profile.HighestWave = math.max(profile.HighestWave or 0, wave)
				if profile.Stats then
					profile.Stats.TotalWaves = (profile.Stats.TotalWaves or 0) + 1
				end
				if wave % (GameConfig.CheckpointInterval or 5) == 0 then
					profile.LastCheckpoint = wave
				end
				DataService.MarkDirty(p, "WaveClear")
				task.spawn(function()
					DataService.SaveProfile(p, true, true, "WaveClear")
				end)
			end
			perPlayer[p.UserId] = {
				gold = beforeG + gold,
				xp = beforeX + xp,
			}
		end
	end
	return perPlayer
end

function RewardService.GrantDefeatConsolation(players: { Player }, wave: number): { [number]: { gold: number, xp: number } }
	local m = multipliers()
	local wr = GameConfig.WaveRewards
	local pct = wr.DefeatPercent or 0.25
	local gold = math.floor(((wr.GoldBonus or 35) + (wr.BonusPerWave or 4) * wave) * m * pct)
	local xp = math.floor(((wr.XPBonus or 15) + (wr.BonusPerWave or 4) * wave) * m * pct)
	local perPlayer = {}
	for _, p in ipairs(players) do
		if p.Parent then
			local sessG, sessX = RewardService.GetSessionEarnings(p)
			credit(p, gold, xp, "defeat_consolation")
			task.spawn(function()
				DataService.SaveProfile(p, true)
			end)
			perPlayer[p.UserId] = {
				gold = sessG + gold,
				xp = sessX + xp,
			}
		end
	end
	return perPlayer
end

function RewardService:Init(services)
	DataService = services.DataService
end

return RewardService
