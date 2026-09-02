--[[
	EnemiesConfig — базовые статы врагов и масштабирование по волнам.
]]

local EnemiesConfig = {
	BaseStats = {
		HP = 80,
		Damage = 10,
		FireRate = 0.5,
		Accuracy = 0.65,
		Armor = 0,
		WalkSpeed = 14,
	},

	-- Множители за каждую волну (волна 1 = базовые статы)
	PerWaveScaling = {
		HP = 0.08, -- +8% HP за волну
		Damage = 0.05,
		FireRate = -0.01, -- быстрее стреляют (меньше интервал)
		Accuracy = 0.008,
		Armor = 0.5, -- +0.5 брони за волну
		WalkSpeed = 0.003,
	},

	-- Минимальный интервал между выстрелами врага
	MinFireRate = 0.15,

	-- Награды за убийство (до кооп-множителя и difficulty)
	Rewards = {
		Gold = 12,
		XP = 8,
	},

	-- Типы оружия у врагов (циклически по индексу моба)
	WeaponRotation = { "Pistol", "SMG", "Rifle", "Shotgun", "LMG", "Sniper", "Revolver", "Crossbow" },

	-- Стреляют на подходе (но не со всего моста ≈320 — иначе не идут)
	AttackRange = 180,
	-- Остановка у линии обороны
	StopRange = 55,
}

return EnemiesConfig
