local UpgradesConfig = require(script.Parent.Parent.Config.UpgradesConfig)
local WeaponsConfig = require(script.Parent.Parent.Config.WeaponsConfig)
local ArmorConfig = require(script.Parent.Parent.Config.ArmorConfig)
local AccuracyHelper = require(script.Parent.AccuracyHelper)

local StatCalculator = {}

function StatCalculator.GetUpgradeStat(statName: string, level: number): number
	local cfg = UpgradesConfig.Stats[statName]
	if not cfg then
		return 0
	end
	level = math.clamp(level, 0, cfg.MaxLevel)
	return cfg.BaseValue + cfg.PerLevel * level
end

function StatCalculator.GetUpgradeCost(statName: string, currentLevel: number): number
	local cfg = UpgradesConfig.Stats[statName]
	if not cfg then
		return math.huge
	end
	if currentLevel >= cfg.MaxLevel then
		return math.huge
	end
	return math.floor(cfg.XPCostBase * (cfg.XPCostGrowth ^ currentLevel))
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
	local accuracy = StatCalculator.GetUpgradeStat("Accuracy", upgrades.Accuracy or 0)
	local reloadMult = StatCalculator.GetUpgradeStat("ReloadSpeed", upgrades.ReloadSpeed or 0)
	local hp = StatCalculator.GetUpgradeStat("HP", upgrades.HP or 0)
	local armor = StatCalculator.GetArmorValue((profile and profile.EquippedArmorTier) or 0)

	local weaponAcc = weapon and weapon.Accuracy or 0.75
	local finalAccuracy = AccuracyHelper.ComputeBaseAccuracy(weaponAcc, accuracy)

	return {
		MaxHP = hp,
		Armor = armor,
		Damage = weapon and weapon.Damage or 10,
		FireRate = weapon and (weapon.FireRate / math.max(reloadMult, 0.1)) or 0.5,
		Range = weapon and weapon.Range or 80,
		Accuracy = finalAccuracy,
		WeaponType = loadout.WeaponType,
		WeaponTier = loadout.Tier or 1,
	}
end

return StatCalculator
