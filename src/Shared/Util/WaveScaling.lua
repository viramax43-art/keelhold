local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local EnemiesConfig = require(ReplicatedStorage.Shared.Config.EnemiesConfig)

local WaveScaling = {}

function WaveScaling.EnemyCount(wave: number): number
	local w = GameConfig.Waves
	local override = w.EnemiesPerWaveOverride
	if type(override) == "table" then
		local fixed = tonumber(override[wave])
		if fixed then
			return math.clamp(math.floor(fixed), 1, w.MaxEnemiesPerWave or 100)
		end
	end
	local n = (w.EnemiesPerWaveBase or 12) + (w.EnemiesPerWaveGrowth or 2) * math.max(0, wave - 1)
	return math.clamp(math.floor(n), 1, w.MaxEnemiesPerWave or 100)
end

--[[
	Ранг = номер «сотни» волн (WavesPerRank): 1..100 → 1, 101..200 → 2, ...
	Структура заказчика: 100 волн = 1 ранг, всего RankCount рангов.
]]
function WaveScaling.RankForWave(wave: number): number
	local per = math.max(1, (GameConfig.Waves and GameConfig.Waves.WavesPerRank) or 100)
	return math.max(1, math.ceil(math.max(1, wave) / per))
end

function WaveScaling.EnemyStats(wave: number, difficultyMult: number)
	local base = EnemiesConfig.BaseStats
	local scale = EnemiesConfig.PerWaveScaling
	difficultyMult = difficultyMult or 1
	local w = math.max(0, wave - 1)
	local fireRate = base.FireRate * (1 + (scale.FireRate or 0) * w)
	fireRate = math.max(EnemiesConfig.MinFireRate or 0.15, fireRate)

	-- Ранг: ранг 1 = 1.0 (базовый баланс), каждый следующий ранг усиливает врагов.
	local rank = WaveScaling.RankForWave(wave)
	local rankW = rank - 1
	local wavesCfg = GameConfig.Waves or {}
	local rankHPMult = 1 + (wavesCfg.RankEnemyHPGrowth or 0) * rankW
	local rankDmgMult = 1 + (wavesCfg.RankEnemyDamageGrowth or 0) * rankW

	-- Бесконечный режим включается только ПОСЛЕ последнего ранга
	-- (EndlessEra.StartWave = RankCount * WavesPerRank = 500), иначе 100 волн
	-- внутри ранга стали бы непроходимыми из-за экспоненты.
	local era = EnemiesConfig.EndlessEra or {}
	local eraStart = era.StartWave or 20
	local hpMult = 1 + (scale.HP or 0) * w
	local dmgMult = 1 + (scale.Damage or 0) * w
	if wave > eraStart then
		local over = wave - eraStart
		hpMult = hpMult * ((era.HPGrowth or 1.07) ^ over)
		dmgMult = dmgMult * ((era.DamageGrowth or 1.03) ^ over)
	end

	return {
		HP = base.HP * hpMult * rankHPMult * difficultyMult,
		Damage = base.Damage * dmgMult * rankDmgMult * difficultyMult,
		FireRate = fireRate,
		Accuracy = math.clamp(base.Accuracy + (scale.Accuracy or 0) * w, 0.2, 0.95),
		Armor = (base.Armor or 0) + (scale.Armor or 0) * w,
		WalkSpeed = base.WalkSpeed * (1 + (scale.WalkSpeed or 0) * w),
	}
end

return WaveScaling
