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
		InterWaveDelay = 6, -- секунд между волнами (короче = плотнее темп)
		-- Число врагов = EnemiesPerWaveBase + EnemiesPerWaveGrowth * (wave - 1),
		-- но EnemiesPerWaveOverride ниже имеет приоритет (ручная подстройка).
		EnemiesPerWaveBase = 4, -- волна 1 = 4 врага
		EnemiesPerWaveGrowth = 1, -- +1 враг за волну: 4, 5, 6, 7, 8, ... до 100
		MaxEnemiesPerWave = 100,
		-- Структура прогрессии заказчика: 100 волн = 1 ранг, всего 5 рангов.
		-- Ранги 2..5 повторяют волны 1..100, но враги сильнее (см. RankEnemy*).
		-- После 5-го ранга (волна 500) включается бесконечный режим усиления.
		WavesPerRank = 100,
		RankCount = 5,
		-- Скалирование врагов по рангу. Ранг 1 = 1.0 (текущий баланс не меняется).
		RankEnemyHPGrowth = 0.35,
		RankEnemyDamageGrowth = 0.20,
		-- Ручная подстройка первых волн (1-5) — перебивает формулу.
		-- Очистить ({}), чтобы вернуться к формуле base + growth.
		EnemiesPerWaveOverride = {
			[1] = 4,
			[2] = 5,
			[3] = 6,
			[4] = 7,
			[5] = 8,
		},
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

	-- DataStore ключи и политика сохранения профилей
	DataStore = {
		PlayerProfile = "BridgeDefense_Profile_v1",
		ProfileBackups = "BridgeDefense_ProfileBackups_v1",
		GlobalConfig = "BridgeDefense_GlobalConfig_v1",
		Promocodes = "BridgeDefense_Promocodes_v1",
		LeaderboardXP = "BridgeDefense_LB_XP_v1",
		LeaderboardWaves = "BridgeDefense_LB_Waves_v1",

		AutoSaveInterval = 60,
		SessionLockTTL = 120,
		SessionHeartbeatInterval = 45,
		MaxLoadRetries = 8,
		MaxSaveRetries = 5,
		-- true только для локальной миграции Studio → DataStore; не production
		AllowLegacyStudioFallback = false,
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
		-- Дистанция, с которой защитники открывают огонь. Дальность оружия
		-- всё равно ограничивает сверху (CombatRange: weaponRange * 1.8).
		DefenseEngageRange = 240,
		PlayerEngageRange = 240,
		WaveStartDelay = 0.4,
		-- Темп спавна: interval между врагами внутри пачки, groupGap — пауза
		-- между пачками по groupSize врагов.
		EnemySpawnInterval = 0.5,
		EnemyGroupSize = 3,
		EnemyGroupGap = 1.2,

		-- Диагностика боя: писать в лог каждый выстрел/урон (WARN). В проде false.
		DebugCombatDamage = false,
		-- Заглушки для теста урона: включать ТОЛЬКО чтобы проверить, что
		-- урон вообще проходит (каждый выстрел с чистой линией = попадание).
		ForceBotHitsForTest = false,
		ForceEnemyHitsForTest = false,

		-- Точность выстрела — одна кривая для ботов и врагов:
		--   chance = (base + bonus) * ProfileMult - штраф_дистанции - штраф_движения
		-- Боты — эталон (1.0), враги заметно хуже (0.8): стреляет толпа, но мажет.
		HitChance = {
			Enabled = true, -- false = старая (слишком щедрая) кривая, для сравнения
			BotProfileMult = 1.0,
			EnemyProfileMult = 0.8,
			-- До этой доли дальности точность почти не падает (0.15 = 15% range)
			NearFalloffStart = 0.15,
			-- Форма падения: 1 = линейно, >1 = резкий обвал у предела дальности
			FalloffPower = 1.35,
			-- Макс. штраф дистанции на пределе дальности (в долях от шанса)
			MaxDistancePenalty = 0.55,
			-- Разброс оружия усиливает штраф: mult = SpreadBase + spread * SpreadWeight
			SpreadBase = 0.55,
			SpreadWeight = 0.85,
			MovingShooterPenalty = 0.10,
			MovingTargetPenalty = 0.07,
			MinChance = 0.05,
			MaxChance = 0.92,
			-- Визуальный трассер: разброс только по горизонтали, вертикали нет.
			-- (именно так просил заказчик: угол вбок, высота всегда ровно в цель)
			HorizontalOnlySpread = true,
			VisualSpreadMaxDeg = 5,
			VisualSpreadMinDeg = 0.6,
		},

		-- Линия огня (LOS): части с Transparency >= порога не считаются укрытием.
		-- У заказной карты у самой обороны стоит почти невидимая панель
		-- (0.1x28x101, Transparency = 0.8), а поперёк моста — невидимая стена
		-- (0.3x70x252, Transparency = 1): обе «съедали» выстрелы у ствола,
		-- из-за чего боты и враги не наносили урона вообще.
		LosGhostTransparency = 0.7,

		-- Коридор боя: у невидимых деталей внутри зоны боя снимается коллизия,
		-- чтобы они не держали NPC и не ловили пули (см. MapBind).
		CorridorClear = {
			Enabled = true,
			-- Порог невидимости детали
			Transparency = 0.7,
			-- Запас вдоль моста от крайних точек пути врагов
			AlongPad = 12,
			-- Поперёк: ширина настила * 0.5 + запас
			LateralPad = 2,
			-- По высоте: от настила вниз Below и вверх Above (уровень груди)
			Below = 3,
			Above = 9,
		},

		-- «Раненый» вместо смерти: юнит падает, но не исчезает и не стреляет.
		-- Встаёт сам через ReviveDelaySec с ReviveHPPercent от MaxHP.
		-- Поражение (wipe) — только если ВСЕ боты одновременно Downed.
		Downed = {
			Enabled = true,
			ReviveDelaySec = 12,
			ReviveHPPercent = 0.35,
			-- Между волнами все раненые встают (передышка)
			ReviveOnWaveStart = true,
		},
		-- Debug VFX: workspace:SetAttribute("BD_DebugCombat", true)
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
		-- Чекпоинт-волна (каждая CheckpointInterval) даёт усиленную награду
		CheckpointMult = 3,
	},
}

return GameConfig
