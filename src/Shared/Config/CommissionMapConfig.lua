--[[
	CommissionMapConfig — привязка геймплея к объектам заказной карты.
]]

local CommissionMapConfig = {
	DetectNames = { "Road Bridge", "MainTeleport", "WoodenLeaderboard" },

	Anchors = {
		-- Три Shop-площадки на карте + отдельные модели
		BattleTeleport = {
			Prefer = { "MainTeleport" },
			ObjectText = "Миссия",
			ActionText = "В бой",
			MaxDistance = 28,
		},
		Shop = {
			Prefer = { "Shop" },
			RequireClass = "BasePart",
			Pick = "ClosestToSpawn",
			ObjectText = "Weapon Shop",
			ActionText = "Оружие",
			MaxDistance = 22,
		},
		ArmorShop = {
			-- 2-я площадка Shop (рядом с витриной брони), НЕ модель PubgArmorLvl3
			Prefer = { "Shop" },
			RequireClass = "BasePart",
			Pick = "SecondClosestToSpawn",
			ObjectText = "Armor Shop",
			ActionText = "Броня",
			MaxDistance = 22,
		},
		UnitShop = {
			Prefer = { "Shop" },
			RequireClass = "BasePart",
			Pick = "ThirdClosestToSpawn",
			FallbackNames = { "base_model_of_gun" },
			ObjectText = "Unit Shop",
			ActionText = "Отряд",
			MaxDistance = 22,
		},
		Upgrade = {
			Prefer = { "base_model_of_unit" },
			FallbackNames = { "Bench" },
			ObjectText = "Тренировка",
			ActionText = "Прокачка",
			MaxDistance = 22,
		},
		Leaderboard = {
			Prefer = { "WoodenLeaderboard" },
			Pick = "ClosestToSpawn",
			ObjectText = "Лидерборд",
			ActionText = "Топ",
			MaxDistance = 20,
		},
		DailyReward = {
			Prefer = { "Pubg Air Drop" },
			ObjectText = "Награда",
			ActionText = "Забрать",
			MaxDistance = 18,
		},
		Promocode = {
			Prefer = { "WoodSign" },
			Pick = "FarthestOfPrefer",
			ObjectText = "Промокод",
			ActionText = "Ввести код",
			MaxDistance = 18,
		},
	},

	Battle = {
		BridgeName = "Road Bridge",
		-- Высота настила: брать медиану Y у «плоских» частей, не maxY (мачты/опоры)
		DeckYBand = 10,
		CharacterStandOffset = 3.2,
	},
}

return CommissionMapConfig
