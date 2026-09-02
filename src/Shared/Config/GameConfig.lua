--[[
	GameConfig — глобальные настройки MVP «Оборона Моста».
	Меняйте значения здесь без правки игровой логики.
]]

local GameConfig = {
	-- Идентификаторы place'ов (заполнить после публикации в Roblox Studio)
	PlaceIds = {
		Lobby = 0, -- TODO: заменить на PlaceId лобби
		Battle = 0, -- TODO: заменить на PlaceId боевой локации
	},

	-- Лимит игроков в лобби-сервере
	LobbyMaxPlayers = 100,

	-- Размер пати (игроки)
	PartySize = 4,

	-- Сколько ботов-защитников на мосту (всегда; игроки летают и не умирают)
	DefenseBotCount = 4,

	-- Кооп-множитель по ТЗ: Solo 1.0 / 1 друг 1.2 / 2 1.3 / 3 1.5
	CoopMultiplier = {
		Solo = 1.0,
		[1] = 1.2,
		[2] = 1.3,
		[3] = 1.5,
	},

	-- Чекпоинты каждые N волн
	CheckpointInterval = 5,

	-- Режим волн (админ может менять через AdminService → сохраняется в DataStore конфиге)
	Waves = {
		DefaultEndless = true,
		DefaultFixedCount = 20, -- используется если Endless = false
		InterWaveDelay = 8, -- секунд между волнами
		EnemiesPerWaveBase = 12, -- базовое число врагов; растёт с волной
		EnemiesPerWaveGrowth = 2, -- +N врагов за каждую волну
		MaxEnemiesPerWave = 100,
	},

	-- Боты наследуют прокачку хоста (HP / точность / перезарядка)
	BotsInheritHostUpgrades = true,

	-- Уровни сложности (выбор при входе в бой)
	Difficulties = {
		Easy = { Id = "Easy", Name = "Лёгкий", EnemyStatMultiplier = 0.8, RewardMultiplier = 0.9 },
		Normal = { Id = "Normal", Name = "Нормальный", EnemyStatMultiplier = 1.0, RewardMultiplier = 1.0 },
		Hard = { Id = "Hard", Name = "Сложный", EnemyStatMultiplier = 1.3, RewardMultiplier = 1.2 },
	},

	-- Ежедневные награды (7-дневный цикл)
	DailyRewards = {
		{ Gold = 100, XP = 50 },
		{ Gold = 150, XP = 75 },
		{ Gold = 200, XP = 100 },
		{ Gold = 250, XP = 125 },
		{ Gold = 300, XP = 150 },
		{ Gold = 400, XP = 200 },
		{ Gold = 500, XP = 300 },
	},

	-- DataStore ключи
	DataStore = {
		PlayerProfile = "BridgeDefense_Profile_v1",
		GlobalConfig = "BridgeDefense_GlobalConfig_v1",
		Promocodes = "BridgeDefense_Promocodes_v1",
		LeaderboardXP = "BridgeDefense_LB_XP_v1",
		LeaderboardWaves = "BridgeDefense_LB_Waves_v1",
	},

	-- Имена точек на карте (Folder Workspace.MapPoints)
	-- На Commission_place точки создаёт CommissionMapBinder в рантайме
	MapPointNames = {
		DefenseSpawns = { "DefenseSpawn1", "DefenseSpawn2", "DefenseSpawn3", "DefenseSpawn4" },
		EnemySpawn = "EnemySpawn",
		BridgePath = "BridgePath",
		BridgePathWaypoints = { "BridgePath1", "BridgePath2", "BridgePath3", "BridgePath4", "BridgePath5", "BridgePath6" },
		LobbyTeleportBattle = "LobbyTeleportBattle",
		LobbyShop = "LobbyShop",
		LobbyLeaderboard = "LobbyLeaderboard",
		LobbyUpgrade = "LobbyUpgrade",
		LobbyPromocode = "LobbyPromocode",
		LobbyDailyReward = "LobbyDailyReward",
	},

	-- Ориентиры заказной карты (имена Instance в Workspace)
	CommissionLandmarks = {
		Bridge = { "Road Bridge", "RoadBridge" },
		Shop = { "BackShop", "Shop" },
		Leaderboard = { "WoodenLeaderboard", "Leaderboard" },
	},

	-- Античит: макс. дистанция попадания (studs)
	MaxHitDistance = 500,

	-- Бой на мосту: защитники стреляют по длине моста; враги идут по waypoints
	Battle = {
		DefenseEngageRange = 350,
		PlayerEngageRange = 350,
		WaveStartDelay = 1.5,
		EnemySpawnInterval = 0.6,
	},

	-- XP за уровень (экспоненциальный рост через XPPerLevelGrowth)
	XPPerLevel = 150,
	XPPerLevelGrowth = 1.15,

	-- Бонус за прохождение волны (поверх наград за убийства)
	WaveRewards = {
		GoldBonus = 35,
		XPBonus = 15,
		BonusPerWave = 4, -- +N за каждый номер волны
		-- Утешительный бонус при поражении = доля от бонуса за победу на этой волне
		DefeatPercent = 0.25,
	},
}

return GameConfig
