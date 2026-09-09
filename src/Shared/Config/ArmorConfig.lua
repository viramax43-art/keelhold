--[[
	ArmorConfig — броня: лёгкая / средняя / тяжёлая линии (10 позиций).
]]

local ArmorConfig = {
	Tiers = {
		[1] = { Name = "Лёгкий жилет", GoldCost = 250, Armor = 4, Class = "Light", Icon = "rbxassetid://0", Emoji = "🦺" },
		[2] = { Name = "Лёгкий жилет II", GoldCost = 600, Armor = 8, Class = "Light", Icon = "rbxassetid://0", Emoji = "🦺" },
		[3] = { Name = "Лёгкий жилет III", GoldCost = 1200, Armor = 12, Class = "Light", Icon = "rbxassetid://0", Emoji = "🦺" },
		[4] = { Name = "Средняя броня", GoldCost = 2200, Armor = 18, Class = "Medium", Icon = "rbxassetid://0", Emoji = "🛡️" },
		[5] = { Name = "Средняя броня II", GoldCost = 4000, Armor = 24, Class = "Medium", Icon = "rbxassetid://0", Emoji = "🛡️" },
		[6] = { Name = "Средняя броня III", GoldCost = 7000, Armor = 32, Class = "Medium", Icon = "rbxassetid://0", Emoji = "🛡️" },
		[7] = { Name = "Тяжёлая броня", GoldCost = 11000, Armor = 40, Class = "Heavy", Icon = "rbxassetid://0", Emoji = "🦾" },
		[8] = { Name = "Тяжёлая броня II", GoldCost = 17000, Armor = 48, Class = "Heavy", Icon = "rbxassetid://0", Emoji = "🦾" },
		[9] = { Name = "Тяжёлая броня III", GoldCost = 26000, Armor = 58, Class = "Heavy", Icon = "rbxassetid://0", Emoji = "🦾" },
		[10] = { Name = "Экзоскелет", GoldCost = 40000, Armor = 70, Class = "Exo", Icon = "rbxassetid://0", Emoji = "🤖" },
	},
	ClassColors = {
		Light = Color3.fromRGB(120, 200, 120),
		Medium = Color3.fromRGB(80, 150, 255),
		Heavy = Color3.fromRGB(200, 120, 255),
		Exo = Color3.fromRGB(255, 190, 60),
	},
}

return ArmorConfig
