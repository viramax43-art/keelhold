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
	local nextEndless = endless and true or false
	local nextFixed = cfg.FixedCount
	if fixedCount then
		nextFixed = math.clamp(math.floor(tonumber(fixedCount) or 20), 1, 500)
	end
	cfg.Endless = nextEndless
	cfg.FixedCount = nextFixed

	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.DataStore.GlobalConfig)
	end)
	if ok and store then
		pcall(function()
			store:UpdateAsync("WaveMode", function(current)
				local base = if type(current) == "table" then current else {}
				base.Endless = nextEndless
				base.FixedCount = nextFixed
				return base
			end)
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
				cfg = {
					Endless = data.Endless == true,
					FixedCount = math.clamp(math.floor(tonumber(data.FixedCount) or 20), 1, 500),
				}
			end
		end)
	end
end

return GlobalConfigService
