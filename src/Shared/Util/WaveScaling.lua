local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local EnemiesConfig = require(ReplicatedStorage.Shared.Config.EnemiesConfig)

local WaveScaling = {}

function WaveScaling.EnemyCount(wave: number): number
	local w = GameConfig.Waves
	local n = (w.EnemiesPerWaveBase or 12) + (w.EnemiesPerWaveGrowth or 2) * math.max(0, wave - 1)
	return math.clamp(math.floor(n), 1, w.MaxEnemiesPerWave or 100)
end

function WaveScaling.EnemyStats(wave: number, difficultyMult: number)
	local base = EnemiesConfig.BaseStats
	local scale = EnemiesConfig.PerWaveScaling
	difficultyMult = difficultyMult or 1
	local w = math.max(0, wave - 1)
	local fireRate = base.FireRate * (1 + (scale.FireRate or 0) * w)
	fireRate = math.max(EnemiesConfig.MinFireRate or 0.15, fireRate)
	return {
		HP = base.HP * (1 + (scale.HP or 0) * w) * difficultyMult,
		Damage = base.Damage * (1 + (scale.Damage or 0) * w) * difficultyMult,
		FireRate = fireRate,
		Accuracy = math.clamp(base.Accuracy + (scale.Accuracy or 0) * w, 0.2, 0.95),
		Armor = (base.Armor or 0) + (scale.Armor or 0) * w,
		WalkSpeed = base.WalkSpeed * (1 + (scale.WalkSpeed or 0) * w),
	}
end

return WaveScaling
