--[[
	EnemiesConfig — базовые статы врагов и масштабирование по волнам.
]]

local EnemiesConfig = {
	BaseStats = {
		HP = 60,
		Damage = 8,
		FireRate = 0.6,
		Accuracy = 0.55,
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

	-- Бесконечный режим: после StartWave враги растут экспоненциально
	EndlessEra = {
		StartWave = 20,
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

	WeaponRotation = { "Pistol", "SMG", "Rifle", "Shotgun", "LMG", "Sniper", "Revolver", "Crossbow" },

	EnemyTypes = {
		Pistol = { DamageMult = 0.8, HPMult = 0.9, SpeedMult = 1.05, AccuracyMod = -0.05 },
		SMG = { DamageMult = 0.7, HPMult = 0.85, SpeedMult = 1.1, AccuracyMod = -0.1 },
		Rifle = { DamageMult = 1.0, HPMult = 1.0, SpeedMult = 1.0, AccuracyMod = 0 },
		Shotgun = { DamageMult = 1.3, HPMult = 1.1, SpeedMult = 0.9, AccuracyMod = -0.15 },
		LMG = { DamageMult = 1.1, HPMult = 1.2, SpeedMult = 0.85, AccuracyMod = 0.05 },
		Sniper = { DamageMult = 1.5, HPMult = 0.8, SpeedMult = 0.8, AccuracyMod = 0.1 },
		Revolver = { DamageMult = 1.15, HPMult = 0.95, SpeedMult = 1.0, AccuracyMod = 0 },
		Crossbow = { DamageMult = 1.2, HPMult = 0.9, SpeedMult = 0.95, AccuracyMod = 0.05 },
	},

	AttackRange = 180,
	StopRange = 42,
}

return EnemiesConfig
