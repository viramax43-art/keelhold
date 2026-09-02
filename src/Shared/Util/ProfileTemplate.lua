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
	},

	OwnedWeapons = Util.DeepCopy(WeaponsConfig.DefaultLoadout),
	OwnedArmorTier = 0,
	EquippedArmorTier = 0,

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
