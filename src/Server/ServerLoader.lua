--[[
	ServerLoader — явный порядок Init сервисов.
]]

local ServerLoader = {}

function ServerLoader.Load()
	local servicesFolder = script.Parent.Services

	local RemoteService = require(servicesFolder.RemoteService)
	local DataService = require(servicesFolder.DataService)
	local PartyService = require(servicesFolder.PartyService)
	local GlobalConfigService = require(servicesFolder.GlobalConfigService)
	local DebugLogService = require(servicesFolder.DebugLogService)
	local ShopService = require(servicesFolder.ShopService)
	local UpgradeService = require(servicesFolder.UpgradeService)
	local DailyRewardService = require(servicesFolder.DailyRewardService)
	local PromocodeService = require(servicesFolder.PromocodeService)
	local LeaderboardService = require(servicesFolder.LeaderboardService)
	local AdminService = require(servicesFolder.AdminService)
	local RewardService = require(servicesFolder.RewardService)
	local EnemyService = require(servicesFolder.EnemyService)
	local BotService = require(servicesFolder.BotService)
	local CombatService = require(servicesFolder.CombatService)
	local WaveService = require(servicesFolder.WaveService)
	local StudioBattleService = require(servicesFolder.StudioBattleService)
	local TeleportService = require(servicesFolder.TeleportService)

	local services = {
		RemoteService = RemoteService,
		DataService = DataService,
		PartyService = PartyService,
		GlobalConfigService = GlobalConfigService,
		DebugLogService = DebugLogService,
		ShopService = ShopService,
		UpgradeService = UpgradeService,
		DailyRewardService = DailyRewardService,
		PromocodeService = PromocodeService,
		LeaderboardService = LeaderboardService,
		AdminService = AdminService,
		RewardService = RewardService,
		EnemyService = EnemyService,
		BotService = BotService,
		CombatService = CombatService,
		WaveService = WaveService,
		StudioBattleService = StudioBattleService,
		TeleportService = TeleportService,
	}

	RemoteService:Init(services)
	GlobalConfigService:Init(services)
	DebugLogService:Init(services)
	DataService:Init(services)
	PartyService:Init(services)
	ShopService:Init(services)
	UpgradeService:Init(services)
	DailyRewardService:Init(services)
	PromocodeService:Init(services)
	LeaderboardService:Init(services)
	AdminService:Init(services)
	RewardService:Init(services)
	EnemyService:Init(services)
	BotService:Init(services)
	CombatService:Init(services)
	WaveService:Init(services)
	StudioBattleService:Init(services)
	TeleportService:Init(services)

	print("[BridgeDefense] Server services loaded OK")
	return services
end

return ServerLoader
