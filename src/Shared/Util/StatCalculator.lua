local UpgradesConfig = require(script.Parent.Parent.Config.UpgradesConfig)
local WeaponsConfig = require(script.Parent.Parent.Config.WeaponsConfig)
local ArmorConfig = require(script.Parent.Parent.Config.ArmorConfig)
local AccuracyHelper = require(script.Parent.AccuracyHelper)

local StatCalculator = {}

function StatCalculator.GetUpgradeStat(statName: string, level: number, prestigePoints: number?, ascensions: number?): number
	local cfg = UpgradesConfig.Stats[statName]
	if not cfg then
		return 0
	end
	-- Бесконечная прокачка: уровень не ограничен жёстко, но разумно clamp'им для безопасности.
	level = math.clamp(level, 0, 999999)
	local base = cfg.BaseValue + cfg.PerLevel * level
	-- Милстоуны: каждые 25 уровней эффект статы удваивается.
	base = base * UpgradesConfig.GetMilestoneMultiplier(level)
	-- Тайкун-престиж: каждое очко престижа усиливает значение.
	local prestige = math.max(0, prestigePoints or 0)
	if prestige > 0 and UpgradesConfig.Prestige.Enabled then
		base = base * (1 + prestige * UpgradesConfig.Prestige.StatBonusPerPoint)
	end
	-- Вознесение: постоянный множитель поверх всего.
	local asc = math.max(0, ascensions or 0)
	if asc > 0 and UpgradesConfig.Ascension.Enabled then
		base = base * (1 + asc * UpgradesConfig.Ascension.StatBonusPerAscension)
	end
	-- Мягкий кап для процентных статов (шанс крита и т.п.)
	if cfg.Cap then
		base = math.min(base, cfg.Cap)
	end
	return base
end

function StatCalculator.GetUpgradeCost(statName: string, currentLevel: number): number
	local cfg = UpgradesConfig.Stats[statName]
	if not cfg then
		return math.huge
	end
	-- Бесконечный рост стоимости по экспоненте.
	return math.floor(cfg.XPCostBase * (cfg.XPCostGrowth ^ currentLevel))
end

-- Суммарная стоимость покупки count уровней подряд (геометрическая прогрессия)
function StatCalculator.GetBulkUpgradeCost(statName: string, currentLevel: number, count: number): number
	local cfg = UpgradesConfig.Stats[statName]
	if not cfg or count <= 0 then
		return math.huge
	end
	local g = cfg.XPCostGrowth
	-- sum = base * g^level * (g^count - 1) / (g - 1)
	local sum = cfg.XPCostBase * (g ^ currentLevel) * ((g ^ count) - 1) / (g - 1)
	return math.floor(sum)
end

-- Сколько уровней можно купить на budget XP (макс. 10000 за раз)
function StatCalculator.GetAffordableUpgradeCount(statName: string, currentLevel: number, budget: number): number
	local cfg = UpgradesConfig.Stats[statName]
	if not cfg or budget < StatCalculator.GetUpgradeCost(statName, currentLevel) then
		return 0
	end
	local g = cfg.XPCostGrowth
	-- budget >= base * g^level * (g^n - 1)/(g - 1)  =>  n <= log_g(1 + budget*(g-1)/(base*g^level))
	local n = math.log(1 + budget * (g - 1) / (cfg.XPCostBase * (g ^ currentLevel))) / math.log(g)
	return math.clamp(math.floor(n), 0, 10000)
end

function StatCalculator.GetWeaponStats(weaponType: string, tier: number)
	local weaponTable = WeaponsConfig.Weapons[weaponType]
	if not weaponTable then
		return nil
	end
	return weaponTable[tier]
end

function StatCalculator.GetArmorValue(tier: number): number
	if tier <= 0 then
		return 0
	end
	local data = ArmorConfig.Tiers[tier]
	return data and data.Armor or 0
end

function StatCalculator.BuildCombatStats(profile, slotIndex: number?)
	slotIndex = slotIndex or 1
	local loadout = profile and profile.SquadLoadout and profile.SquadLoadout[slotIndex]
	if type(loadout) ~= "table" or not loadout.WeaponType then
		loadout = { WeaponType = "Pistol", Tier = 1 }
	end
	local weapon = StatCalculator.GetWeaponStats(loadout.WeaponType, loadout.Tier or 1)

	local upgrades = (profile and profile.Upgrades) or {}
	local prestige = (profile and profile.PrestigePoints) or 0
	local ascensions = (profile and profile.Ascensions) or 0
	local function stat(name)
		return StatCalculator.GetUpgradeStat(name, upgrades[name] or 0, prestige, ascensions)
	end

	local accuracy = stat("Accuracy")
	local reloadMult = stat("ReloadSpeed")
	local hp = stat("HP")
	local armorTier = 0
	if profile and profile.SquadArmor and profile.SquadArmor[slotIndex] then
		armorTier = profile.SquadArmor[slotIndex] or 0
	elseif profile then
		armorTier = profile.EquippedArmorTier or 0
	end
	local armor = StatCalculator.GetArmorValue(armorTier)

	local weaponAcc = weapon and weapon.Accuracy or 0.75
	local finalAccuracy = AccuracyHelper.ComputeBaseAccuracy(weaponAcc, accuracy)

	return {
		MaxHP = hp,
		Armor = armor,
		Damage = weapon and weapon.Damage or 10,
		FireRate = weapon and (weapon.FireRate / math.max(reloadMult, 0.1)) or 0.5,
		Range = weapon and weapon.Range or 80,
		Accuracy = finalAccuracy,
		Spread = weapon and (weapon.Spread or 0.2) or 0.2,
		CritChance = stat("CritChance"),
		CritDamage = stat("CritDamage"),
		BotDamageMult = stat("BotDamage"),
		WeaponType = loadout.WeaponType,
		WeaponTier = loadout.Tier or 1,
	}
end

return StatCalculator
