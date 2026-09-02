local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)

local LeaderboardService = {}
local xpStore, waveStore

local function getOrdered(name)
	local ok, s = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	return ok and s or nil
end

function LeaderboardService:Init(services)
	local DataService = services.DataService
	local RemoteService = services.RemoteService
	xpStore = getOrdered(GameConfig.DataStore.LeaderboardXP)
	waveStore = getOrdered(GameConfig.DataStore.LeaderboardWaves)

	local getLb = RemoteService.GetRemote(RemoteNames.GetLeaderboard)
	if getLb then
		getLb.OnServerInvoke = function(_player, kind)
			local store = kind == "Waves" and waveStore or xpStore
			if not store then
				return { success = true, entries = {} }
			end
			local ok, pages = pcall(function()
				return store:GetSortedAsync(false, 20)
			end)
			if not ok then
				return { success = true, entries = {} }
			end
			local entries = {}
			for _, item in ipairs(pages:GetCurrentPage()) do
				table.insert(entries, { UserId = tonumber(item.key), Value = item.value })
			end
			return { success = true, entries = entries }
		end
	end

	local function push(player)
		local profile = DataService.GetProfile(player)
		if not profile then
			return
		end
		if xpStore then
			pcall(function()
				xpStore:SetAsync(tostring(player.UserId), profile.TotalXP or 0)
			end)
		end
		if waveStore then
			pcall(function()
				waveStore:SetAsync(tostring(player.UserId), profile.HighestWave or 0)
			end)
		end
	end

	Players.PlayerRemoving:Connect(push)
	game:BindToClose(function()
		for _, p in ipairs(Players:GetPlayers()) do
			push(p)
		end
	end)
end

return LeaderboardService
