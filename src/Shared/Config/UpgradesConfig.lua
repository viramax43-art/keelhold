--[[
	UpgradesConfig — бесконечная прокачка персонажа за XP.
	Модель: тайкун-подобная — уровень бесконечен, стоимость растёт,
	прирост линейный + милстоуны x2 каждые MilestoneEvery уровней.
	Новые статы открываются по мере престижей (UnlockPrestige).
	Вознесение (Ascension) — второй слой сброса поверх престижа.
]]

local UpgradesConfig = {
	Stats = {
		HP = {
			Name = "Жизнь",
			BaseValue = 100,
			PerLevel = 15,
			MaxLevel = 999999, -- бесконечно
			XPCostBase = 30,
			XPCostGrowth = 1.10,
			UnlockPrestige = 0,
		},
		Accuracy = {
			Name = "Точность",
			BaseValue = 0.75,
			PerLevel = 0.02,
			MaxLevel = 999999,
			XPCostBase = 25,
			XPCostGrowth = 1.08,
			UnlockPrestige = 0,
		},
		ReloadSpeed = {
			-- Legacy profile key kept for compatibility; gameplay changes shot interval.
			Name = "Скорострельность",
			BaseValue = 1.0, -- множитель: >1 = чаще выстрелы
			PerLevel = 0.03,
			MaxLevel = 999999,
			XPCostBase = 28,
			XPCostGrowth = 1.09,
			UnlockPrestige = 0,
		},
		CritChance = {
			Name = "Шанс крита",
			BaseValue = 0.05,
			PerLevel = 0.005,
			MaxLevel = 999999,
			XPCostBase = 60,
			XPCostGrowth = 1.11,
			UnlockPrestige = 1,
			Cap = 0.6, -- не более 60% шанса
			Format = "percent",
		},
		CritDamage = {
			Name = "Крит-урон",
			BaseValue = 1.5, -- множитель урона при крите
			PerLevel = 0.05,
			MaxLevel = 999999,
			XPCostBase = 60,
			XPCostGrowth = 1.11,
			UnlockPrestige = 1,
			Format = "multiplier",
		},
		GoldGain = {
			Name = "Добыча золота",
			BaseValue = 1.0,
			PerLevel = 0.04,
			MaxLevel = 999999,
			XPCostBase = 80,
			XPCostGrowth = 1.12,
			UnlockPrestige = 2,
			Format = "multiplier",
		},
		XPGain = {
			Name = "Добыча опыта",
			BaseValue = 1.0,
			PerLevel = 0.04,
			MaxLevel = 999999,
			XPCostBase = 80,
			XPCostGrowth = 1.12,
			UnlockPrestige = 2,
			Format = "multiplier",
		},
		BotDamage = {
			Name = "Урон отряда",
			BaseValue = 1.0,
			PerLevel = 0.05,
			MaxLevel = 999999,
			XPCostBase = 100,
			XPCostGrowth = 1.12,
			UnlockPrestige = 3,
			Format = "multiplier",
		},
	},

	-- Милстоуны: каждые N уровней статы эффект удваивается (как в тайкунах).
	Milestones = {
		Every = 25,
		Multiplier = 2,
	},

	-- Престиж: при достижении суммы уровней можно сбросить их в 0
	-- и получить PrestigePoints. Каждое очко: +2% к статам и +5% к доходу.
	-- Порог растёт с каждым сбросом (как rebirth в тайкунах).
	Prestige = {
		Enabled = true,
		Threshold = 120, -- базовый суммарный уровень всех статов для сброса
		ThresholdGrowth = 60, -- +60 к порогу за каждый уже имеющийся престиж
		PointsPerReset = 1,
		StatBonusPerPoint = 0.02, -- +2% к BaseValue каждой статы за очко
		IncomeBonusPerPoint = 0.05, -- +5% к золоту/XP за очко
	},

	-- Вознесение: сжигает очки престижа ради постоянного множителя.
	-- Сбрасывает престиж-очки и уровни, даёт +25% к статам и доходу за уровень.
	Ascension = {
		Enabled = true,
		BaseCost = 10, -- очков престижа за первое вознесение
		CostGrowth = 5, -- +5 к цене за каждое следующее
		StatBonusPerAscension = 0.25,
		IncomeBonusPerAscension = 0.25,
	},
}

-- Порог престижа с учётом уже имеющихся очков
function UpgradesConfig.GetPrestigeThreshold(currentPoints: number): number
	local p = UpgradesConfig.Prestige
	return (p.Threshold or 30) + (p.ThresholdGrowth or 15) * math.max(0, currentPoints or 0)
end

-- Цена вознесения (в очках престижа)
function UpgradesConfig.GetAscensionCost(ascensions: number): number
	local a = UpgradesConfig.Ascension
	return (a.BaseCost or 10) + (a.CostGrowth or 5) * math.max(0, ascensions or 0)
end

-- Открыта ли стата при текущем числе очков престижа
function UpgradesConfig.IsStatUnlocked(statName: string, prestigePoints: number?): boolean
	local cfg = UpgradesConfig.Stats[statName]
	if not cfg then
		return false
	end
	return (prestigePoints or 0) >= (cfg.UnlockPrestige or 0)
end

-- Милстоун-множитель эффекта статы: x2 каждые 25 уровней
function UpgradesConfig.GetMilestoneMultiplier(level: number): number
	local m = UpgradesConfig.Milestones
	if not m or (m.Every or 0) <= 0 then
		return 1
	end
	return (m.Multiplier or 2) ^ math.floor(math.max(0, level) / m.Every)
end

return UpgradesConfig
