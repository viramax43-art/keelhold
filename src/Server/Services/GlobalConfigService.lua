local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local GlobalConfigService = {}
local cfg = {
	Endless = GameConfig.Waves.DefaultEndless,
	FixedCount = GameConfig.Waves.DefaultFixedCount,
}

function GlobalConfigService.GetWaveMode()
	return cfg
end

function GlobalConfigService.SetWaveMode(endless: boolean, fixedCount: number?)
	cfg.Endless = endless and true or false
	if fixedCount then
		cfg.FixedCount = fixedCount
	end
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.DataStore.GlobalConfig)
	end)
	if ok and store then
		pcall(function()
			store:SetAsync("WaveMode", cfg)
		end)
	end
end

function GlobalConfigService:Init()
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.DataStore.GlobalConfig)
	end)
	if ok and store then
		pcall(function()
			local data = store:GetAsync("WaveMode")
			if type(data) == "table" then
				cfg = data
			end
		end)
	end
end

return GlobalConfigService
