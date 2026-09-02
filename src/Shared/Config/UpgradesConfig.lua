--[[
	UpgradesConfig — прокачка персонажа за XP.
]]

local UpgradesConfig = {
	Stats = {
		HP = {
			Name = "Жизнь",
			BaseValue = 100,
			PerLevel = 15,
			MaxLevel = 50,
			XPCostBase = 30,
			XPCostGrowth = 1.10,
		},
		Accuracy = {
			Name = "Точность",
			BaseValue = 0.75,
			PerLevel = 0.02,
			MaxLevel = 40,
			XPCostBase = 25,
			XPCostGrowth = 1.08,
		},
		ReloadSpeed = {
			Name = "Скорость перезарядки",
			BaseValue = 1.0, -- множитель: >1 = быстрее
			PerLevel = 0.03,
			MaxLevel = 25,
			XPCostBase = 28,
			XPCostGrowth = 1.09,
		},
	},
}

return UpgradesConfig
