--[[
	AdminConfig — whitelist админов и дефолтные настройки промокодов.
]]

local AdminConfig = {
	-- UserId заказчика / стримера — заменить на реальный
	AdminUserIds = {
		-- 123456789,
	},

	-- Макс. длина промокода
	PromocodeMaxLength = 32,

	-- Типы наград промокода
	RewardTypes = {
		Gold = "Gold",
		XP = "XP",
		XPMultiplier = "XPMultiplier", -- временный множитель опыта
		GoldMultiplier = "GoldMultiplier",
	},
}

return AdminConfig
