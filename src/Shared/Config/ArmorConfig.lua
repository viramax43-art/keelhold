--[[
	ArmorConfig — броня: лёгкая / средняя / тяжёлая линии (10 позиций).
]]

local ArmorConfig = {
	Tiers = {
		[1] = { Name = "Лёгкий жилет", GoldCost = 250, Armor = 4 },
		[2] = { Name = "Лёгкий жилет II", GoldCost = 600, Armor = 8 },
		[3] = { Name = "Лёгкий жилет III", GoldCost = 1200, Armor = 12 },
		[4] = { Name = "Средняя броня", GoldCost = 2200, Armor = 18 },
		[5] = { Name = "Средняя броня II", GoldCost = 4000, Armor = 24 },
		[6] = { Name = "Средняя броня III", GoldCost = 7000, Armor = 32 },
		[7] = { Name = "Тяжёлая броня", GoldCost = 11000, Armor = 40 },
		[8] = { Name = "Тяжёлая броня II", GoldCost = 17000, Armor = 48 },
		[9] = { Name = "Тяжёлая броня III", GoldCost = 26000, Armor = 58 },
		[10] = { Name = "Экзоскелет", GoldCost = 40000, Armor = 70 },
	},
}

return ArmorConfig
