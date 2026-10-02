--[[
	EnemiesConfig — базовые статы врагов и масштабирование по волнам.
]]

local EnemiesConfig = {
	-- Базовые статы «среднего» врага волны 1 (до множителей типа/оружия).
	-- HP 108 подобран так, чтобы стартовый пистолет Glock T1 (18 урона,
	-- 0 брони у врага) убивал обычного врага за ~6 попаданий: 18 * 6 = 108.
	BaseStats = {
		HP = 108,
		Damage = 13, -- ~7-8 попаданий по боту с 100 HP (до брони)
		FireRate = 0.7, -- медленнее ботов: боты должны выигрывать перестрелку
		Accuracy = 0.55, -- база (профиль стрелка ещё умножается в HitChance)
		Armor = 0,
		WalkSpeed = 12,
	},

	PerWaveScaling = {
		HP = 0.12,
		Damage = 0.035,
		FireRate = -0.008,
		Accuracy = 0.006,
		Armor = 0.6,
		WalkSpeed = 0.002,
	},

	MinFireRate = 0.15,

	-- Бесконечный режим: включается ПОСЛЕ всех рангов
	-- (EndlessEra.StartWave = GameConfig.Waves.RankCount * WavesPerRank = 500),
	-- чтобы 100 волн внутри ранга оставались проходимыми (структура заказчика).
	EndlessEra = {
		StartWave = 500,
		HPGrowth = 1.04, -- +4% HP за волну сверх линейного роста
		DamageGrowth = 1.03, -- +3% урона за волну
	},

	Rewards = {
		Gold = 12,
		XP = 8,
		-- Тайкун-модель: доход растёт с волной (+8% за волну, мягкий кап x6)
		WaveGrowth = 0.08,
		MaxWaveMult = 6,
	},

	WeaponRotation = { "Pistol", "Revolver", "SMG", "Rifle", "Shotgun", "LMG", "Sniper", "Crossbow" },

	-- Оружие ВРАГОВ — отдельные статы, а не статы игрока (WeaponsConfig).
	-- Враги стреляют заметно хуже ботов: низкая Accuracy + высокий Spread.
	-- DamageMult — множитель к BaseStats.Damage, FireRateMult — к BaseStats.FireRate.
	EnemyWeapons = {
		Pistol = { DamageMult = 0.85, Accuracy = 0.60, Spread = 0.30, Range = 90, FireRateMult = 1.00 },
		Revolver = { DamageMult = 1.10, Accuracy = 0.58, Spread = 0.32, Range = 95, FireRateMult = 1.20 },
		SMG = { DamageMult = 0.60, Accuracy = 0.52, Spread = 0.46, Range = 70, FireRateMult = 0.35 },
		Rifle = { DamageMult = 1.00, Accuracy = 0.62, Spread = 0.26, Range = 120, FireRateMult = 0.55 },
		Shotgun = { DamageMult = 1.25, Accuracy = 0.48, Spread = 0.55, Range = 50, FireRateMult = 1.30 },
		LMG = { DamageMult = 0.90, Accuracy = 0.56, Spread = 0.42, Range = 120, FireRateMult = 0.30 },
		Sniper = { DamageMult = 1.60, Accuracy = 0.68, Spread = 0.14, Range = 200, FireRateMult = 1.80 },
		Crossbow = { DamageMult = 1.35, Accuracy = 0.64, Spread = 0.20, Range = 140, FireRateMult = 1.90 },
	},

	-- Дальность оружия врагов медленно растёт по волнам (кап RangeGrowthCap)
	RangeGrowthPerWave = 0.006,
	RangeGrowthCap = 1.35,

	-- Архетипы врагов: HP/скорость/точность. Урон берётся из EnemyWeapons.
	EnemyTypes = {
		Pistol = { HPMult = 0.9, SpeedMult = 1.05, AccuracyMod = -0.05 },
		SMG = { HPMult = 0.85, SpeedMult = 1.1, AccuracyMod = -0.1 },
		Rifle = { HPMult = 1.0, SpeedMult = 1.0, AccuracyMod = 0 },
		Shotgun = { HPMult = 1.1, SpeedMult = 0.9, AccuracyMod = -0.15 },
		LMG = { HPMult = 1.2, SpeedMult = 0.85, AccuracyMod = 0.05 },
		Sniper = { HPMult = 0.8, SpeedMult = 0.8, AccuracyMod = 0.1 },
		Revolver = { HPMult = 0.95, SpeedMult = 1.0, AccuracyMod = 0 },
		Crossbow = { HPMult = 0.9, SpeedMult = 0.95, AccuracyMod = 0.05 },
	},

	-- Радиус, с которого враг вообще берёт защитника на прицел.
	-- Реальная дальность выстрела = enemy.Range (из EnemyWeapons).
	AttackRange = 160,
	-- Линия атаки у обороны
	StopRange = 16,
	MeleeRange = 18,
	-- Ближний бой всегда попадает — он должен быть наказанием, но не казнью
	MeleeDamageMult = 1.1,
	MeleeFireRate = 0.9,
	-- Полосы моста + очередь атаки
	LaneCount = 6,
	MinSpacing = 5.5,
	MaxAttackers = 4,
	AttackSlotsPerLane = 1,
	QueueSpacing = 5.5,
	AttackSpacing = 4.5,
	AttackArriveDistance = 1.5,
}

return EnemiesConfig
