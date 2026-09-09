--[[
	WeaponsConfig — типы оружия × 5 тиров (роли DPS сбалансированы).
]]

local WeaponsConfig = {
	Types = { "Pistol", "Revolver", "SMG", "Rifle", "Shotgun", "LMG", "Sniper", "Crossbow" },

	Icons = {
		Pistol = { Image = "rbxassetid://0", Emoji = "🔫", Color = Color3.fromRGB(180, 180, 190) },
		Revolver = { Image = "rbxassetid://0", Emoji = "🔫", Color = Color3.fromRGB(200, 160, 100) },
		SMG = { Image = "rbxassetid://0", Emoji = "💨", Color = Color3.fromRGB(100, 200, 255) },
		Rifle = { Image = "rbxassetid://0", Emoji = "🎯", Color = Color3.fromRGB(120, 220, 120) },
		Shotgun = { Image = "rbxassetid://0", Emoji = "💥", Color = Color3.fromRGB(255, 140, 60) },
		LMG = { Image = "rbxassetid://0", Emoji = "⚡", Color = Color3.fromRGB(255, 220, 80) },
		Sniper = { Image = "rbxassetid://0", Emoji = "🔭", Color = Color3.fromRGB(200, 120, 255) },
		Crossbow = { Image = "rbxassetid://0", Emoji = "🏹", Color = Color3.fromRGB(160, 120, 80) },
	},
	TierColors = {
		[1] = Color3.fromRGB(160, 160, 170),
		[2] = Color3.fromRGB(80, 200, 120),
		[3] = Color3.fromRGB(80, 140, 255),
		[4] = Color3.fromRGB(200, 100, 255),
		[5] = Color3.fromRGB(255, 190, 60),
		-- Элитные (престиж) тиры
		[6] = Color3.fromRGB(255, 120, 120),
		[7] = Color3.fromRGB(255, 90, 160),
		[8] = Color3.fromRGB(170, 240, 255),
		[9] = Color3.fromRGB(140, 255, 170),
		[10] = Color3.fromRGB(255, 255, 255),
	},

	-- Элитные тиры: T6+ требуют очков престижа (PrestigeRequired = tier - 5)
	MaxTier = 10,
	PrestigeTierStart = 6,

	Weapons = {
		Pistol = {
			[1] = { Name = "Glock T1", GoldCost = 0, Damage = 18, FireRate = 0.45, Range = 80, Accuracy = 0.85, Spread = 0.16 },
			[2] = { Name = "Glock T2", GoldCost = 400, Damage = 22, FireRate = 0.42, Range = 88, Accuracy = 0.87, Spread = 0.15 },
			[3] = { Name = "Glock T3", GoldCost = 1200, Damage = 28, FireRate = 0.38, Range = 96, Accuracy = 0.89, Spread = 0.14 },
			[4] = { Name = "Glock T4", GoldCost = 3200, Damage = 36, FireRate = 0.34, Range = 105, Accuracy = 0.91, Spread = 0.13 },
			[5] = { Name = "Glock T5", GoldCost = 8500, Damage = 46, FireRate = 0.30, Range = 115, Accuracy = 0.93, Spread = 0.12 },
		},
		Revolver = {
			[1] = { Name = "Револьвер T1", GoldCost = 600, Damage = 28, FireRate = 0.55, Range = 90, Accuracy = 0.82, Spread = 0.20 },
			[2] = { Name = "Револьвер T2", GoldCost = 1600, Damage = 36, FireRate = 0.50, Range = 100, Accuracy = 0.84, Spread = 0.19 },
			[3] = { Name = "Револьвер T3", GoldCost = 4000, Damage = 48, FireRate = 0.45, Range = 110, Accuracy = 0.86, Spread = 0.18 },
			[4] = { Name = "Револьвер T4", GoldCost = 9500, Damage = 62, FireRate = 0.40, Range = 120, Accuracy = 0.88, Spread = 0.17 },
			[5] = { Name = "Револьвер T5", GoldCost = 22000, Damage = 80, FireRate = 0.36, Range = 130, Accuracy = 0.90, Spread = 0.16 },
		},
		SMG = {
			[1] = { Name = "ПП T1", GoldCost = 700, Damage = 8, FireRate = 0.07, Range = 70, Accuracy = 0.72, Spread = 0.38 },
			[2] = { Name = "ПП T2", GoldCost = 1800, Damage = 10, FireRate = 0.065, Range = 78, Accuracy = 0.74, Spread = 0.36 },
			[3] = { Name = "ПП T3", GoldCost = 4500, Damage = 13, FireRate = 0.06, Range = 86, Accuracy = 0.76, Spread = 0.34 },
			[4] = { Name = "ПП T4", GoldCost = 11000, Damage = 17, FireRate = 0.055, Range = 95, Accuracy = 0.78, Spread = 0.32 },
			[5] = { Name = "ПП T5", GoldCost = 26000, Damage = 22, FireRate = 0.05, Range = 105, Accuracy = 0.80, Spread = 0.30 },
		},
		Rifle = {
			[1] = { Name = "Автомат T1", GoldCost = 800, Damage = 20, FireRate = 0.13, Range = 120, Accuracy = 0.80, Spread = 0.18 },
			[2] = { Name = "Автомат T2", GoldCost = 2000, Damage = 26, FireRate = 0.12, Range = 130, Accuracy = 0.82, Spread = 0.17 },
			[3] = { Name = "Автомат T3", GoldCost = 5000, Damage = 34, FireRate = 0.11, Range = 140, Accuracy = 0.84, Spread = 0.16 },
			[4] = { Name = "Автомат T4", GoldCost = 12000, Damage = 44, FireRate = 0.10, Range = 150, Accuracy = 0.86, Spread = 0.15 },
			[5] = { Name = "Автомат T5", GoldCost = 25000, Damage = 58, FireRate = 0.09, Range = 160, Accuracy = 0.88, Spread = 0.14 },
		},
		Shotgun = {
			[1] = { Name = "Дробовик T1", GoldCost = 900, Damage = 45, FireRate = 1.0, Range = 45, Accuracy = 0.55, Spread = 0.55 },
			[2] = { Name = "Дробовик T2", GoldCost = 2400, Damage = 58, FireRate = 0.95, Range = 50, Accuracy = 0.58, Spread = 0.52 },
			[3] = { Name = "Дробовик T3", GoldCost = 6000, Damage = 74, FireRate = 0.9, Range = 55, Accuracy = 0.61, Spread = 0.50 },
			[4] = { Name = "Дробовик T4", GoldCost = 14000, Damage = 95, FireRate = 0.85, Range = 60, Accuracy = 0.64, Spread = 0.48 },
			[5] = { Name = "Дробовик T5", GoldCost = 32000, Damage = 120, FireRate = 0.8, Range = 68, Accuracy = 0.68, Spread = 0.45 },
		},
		-- Пулемёт: та же дальность, что у автомата; выше разброс и скорострельность, ниже урон/пуля
		LMG = {
			[1] = { Name = "Пулемёт T1", GoldCost = 1500, Damage = 12, FireRate = 0.07, Range = 120, Accuracy = 0.62, Spread = 0.42 },
			[2] = { Name = "Пулемёт T2", GoldCost = 3500, Damage = 15, FireRate = 0.065, Range = 130, Accuracy = 0.64, Spread = 0.40 },
			[3] = { Name = "Пулемёт T3", GoldCost = 8000, Damage = 19, FireRate = 0.06, Range = 140, Accuracy = 0.66, Spread = 0.38 },
			[4] = { Name = "Пулемёт T4", GoldCost = 18000, Damage = 25, FireRate = 0.055, Range = 150, Accuracy = 0.68, Spread = 0.36 },
			[5] = { Name = "Пулемёт T5", GoldCost = 40000, Damage = 32, FireRate = 0.05, Range = 160, Accuracy = 0.70, Spread = 0.34 },
		},
		Sniper = {
			[1] = { Name = "Снайпер T1", GoldCost = 2000, Damage = 80, FireRate = 1.4, Range = 250, Accuracy = 0.95, Spread = 0.06 },
			[2] = { Name = "Снайпер T2", GoldCost = 5000, Damage = 100, FireRate = 1.3, Range = 280, Accuracy = 0.96, Spread = 0.05 },
			[3] = { Name = "Снайпер T3", GoldCost = 12000, Damage = 130, FireRate = 1.2, Range = 310, Accuracy = 0.97, Spread = 0.05 },
			[4] = { Name = "Снайпер T4", GoldCost = 28000, Damage = 165, FireRate = 1.1, Range = 340, Accuracy = 0.98, Spread = 0.04 },
			[5] = { Name = "Снайпер T5", GoldCost = 60000, Damage = 210, FireRate = 1.0, Range = 370, Accuracy = 0.99, Spread = 0.04 },
		},
		Crossbow = {
			[1] = { Name = "Арбалет T1", GoldCost = 1100, Damage = 50, FireRate = 1.5, Range = 160, Accuracy = 0.90, Spread = 0.12 },
			[2] = { Name = "Арбалет T2", GoldCost = 2800, Damage = 65, FireRate = 1.4, Range = 175, Accuracy = 0.91, Spread = 0.11 },
			[3] = { Name = "Арбалет T3", GoldCost = 7000, Damage = 85, FireRate = 1.3, Range = 190, Accuracy = 0.92, Spread = 0.10 },
			[4] = { Name = "Арбалет T4", GoldCost = 16000, Damage = 110, FireRate = 1.2, Range = 210, Accuracy = 0.94, Spread = 0.09 },
			[5] = { Name = "Арбалет T5", GoldCost = 36000, Damage = 140, FireRate = 1.1, Range = 230, Accuracy = 0.96, Spread = 0.08 },
		},
	},

	DefaultLoadout = {
		Pistol = 1,
		Revolver = 0,
		SMG = 0,
		Rifle = 0,
		Shotgun = 0,
		LMG = 0,
		Sniper = 0,
		Crossbow = 0,
	},
}

-- Генерация элитных тиров T6–T10 из T5: урон/цена растут, тир открывается престижем.
-- Модель тайкуна: после "ребёрса" открывается следующий этаж с заметно лучшим оружием.
local ELITE_DAMAGE_GROWTH = 1.22 -- +22% урона за тир
local ELITE_COST_GROWTH = 2.6 -- цена x2.6 за тир
local ELITE_FIRERATE_IMPROVE = 0.97 -- -3% интервала за тир
local ELITE_RANGE_GROWTH = 1.04

for weaponType, tiers in pairs(WeaponsConfig.Weapons) do
	local t5 = tiers[5]
	if t5 then
		for tier = 6, WeaponsConfig.MaxTier do
			local prev = tiers[tier - 1]
			tiers[tier] = {
				Name = (t5.Name:gsub(" T5", "")) .. " Elite T" .. tier,
				GoldCost = math.floor(prev.GoldCost * ELITE_COST_GROWTH / 100) * 100,
				Damage = math.floor(prev.Damage * ELITE_DAMAGE_GROWTH),
				FireRate = math.max(0.03, prev.FireRate * ELITE_FIRERATE_IMPROVE),
				Range = math.floor(prev.Range * ELITE_RANGE_GROWTH),
				Accuracy = math.min(0.99, prev.Accuracy + 0.005),
				Spread = math.max(0.03, (prev.Spread or 0.2) * 0.97),
				PrestigeRequired = tier - WeaponsConfig.PrestigeTierStart + 1,
			}
		end
	end
end

-- Сколько престижа нужно для тира (0 для обычных)
function WeaponsConfig.GetPrestigeRequired(tier: number): number
	if tier < WeaponsConfig.PrestigeTierStart then
		return 0
	end
	return tier - WeaponsConfig.PrestigeTierStart + 1
end

return WeaponsConfig
