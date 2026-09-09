--[[
	ProfileTemplate — структура сохраняемого профиля.
]]

local WeaponsConfig = require(script.Parent.Parent.Config.WeaponsConfig)
local Util = require(script.Parent.Util)

local ProfileTemplate = {
	Gold = 100,
	XP = 0,
	TotalXP = 0,
	Level = 1,

	Upgrades = {
		HP = 0,
		Accuracy = 0,
		ReloadSpeed = 0,
		CritChance = 0,
		CritDamage = 0,
		GoldGain = 0,
		XPGain = 0,
		BotDamage = 0,
	},

	PrestigePoints = 0,
	Ascensions = 0,

	-- Макс. открытый тир по типу (для прогрессии покупок T1→T2…)
	OwnedWeapons = Util.DeepCopy(WeaponsConfig.DefaultLoadout),
	-- Копии оружия: WeaponCopies[type][tier] = count
	WeaponCopies = {
		Pistol = { [1] = 4 },
	},

	-- Устарело как «на всех»; оставлено для миграции
	OwnedArmorTier = 0,
	EquippedArmorTier = 0,
	-- Копии брони: ArmorCopies[tier] = count
	ArmorCopies = {},
	-- Броня на слот отряда 1..4
	SquadArmor = {
		[1] = 0,
		[2] = 0,
		[3] = 0,
		[4] = 0,
	},

	SquadLoadout = {
		[1] = { WeaponType = "Pistol", Tier = 1 },
		[2] = { WeaponType = "Pistol", Tier = 1 },
		[3] = { WeaponType = "Pistol", Tier = 1 },
		[4] = { WeaponType = "Pistol", Tier = 1 },
	},

	LastCheckpoint = 0,
	HighestWave = 0,

	DailyReward = {
		LastClaimTime = 0,
		StreakDay = 0,
	},

	UsedPromocodes = {},
	ActiveBuffs = {},

	Stats = {
		TotalKills = 0,
		TotalWaves = 0,
	},
}

return ProfileTemplate
