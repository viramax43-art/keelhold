--[[
	LeaderboardService — XP / HighestWave.
	Пишет сразу после боя и сейва; в Studio держит память (OrderedDataStore часто недоступен).
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)
local Log = require(ReplicatedStorage.Shared.Util.Log)

local LeaderboardService = {}
local xpStore, waveStore
local DataService

-- userId -> { xp, wave, name, at }
local memory = {}

local function getOrdered(name)
	local ok, s = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	return ok and s or nil
end

local function resolveName(userId: number, fallback: string?): string
	local online = Players:GetPlayerByUserId(userId)
	if online then
		return online.DisplayName ~= "" and online.DisplayName or online.Name
	end
	if fallback and fallback ~= "" then
		return fallback
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and type(name) == "string" and name ~= "" then
		return name
	end
	return "Player" .. tostring(userId)
end

function LeaderboardService.PushPlayer(player: Player)
	if not player or not DataService then
		return
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	local userId = player.UserId
	local xp = math.max(0, math.floor(tonumber(profile.TotalXP) or 0))
	local wave = math.max(0, math.floor(tonumber(profile.HighestWave) or 0))
	local name = player.DisplayName ~= "" and player.DisplayName or player.Name

	memory[userId] = {
		xp = xp,
		wave = wave,
		name = name,
		at = os.clock(),
	}

	if xpStore then
		pcall(function()
			xpStore:SetAsync(tostring(userId), xp)
		end)
	end
	if waveStore then
		pcall(function()
			waveStore:SetAsync(tostring(userId), wave)
		end)
	end
end

function LeaderboardService.PushAllOnline()
	for _, p in ipairs(Players:GetPlayers()) do
		LeaderboardService.PushPlayer(p)
	end
end

local function buildFromMemory(kind: string): { any }
	local rows = {}
	for userId, row in pairs(memory) do
		table.insert(rows, {
			UserId = userId,
			Name = row.name,
			Value = kind == "Waves" and row.wave or row.xp,
			Wave = row.wave,
			XP = row.xp,
		})
	end
	table.sort(rows, function(a, b)
		if a.Value == b.Value then
			return (a.Wave or 0) > (b.Wave or 0)
		end
		return a.Value > b.Value
	end)
	local top = {}
	for i = 1, math.min(20, #rows) do
		table.insert(top, rows[i])
	end
	return top
end

local function mergeStorePage(kind: string, storeEntries: { any }): { any }
	-- Объединяем DataStore + память (память актуальнее для онлайн)
	local byId = {}
	for _, e in ipairs(storeEntries) do
		local uid = tonumber(e.UserId) or 0
		if uid > 0 then
			byId[uid] = {
				UserId = uid,
				Name = e.Name,
				Value = tonumber(e.Value) or 0,
				Wave = tonumber(e.Wave) or 0,
				XP = tonumber(e.XP) or 0,
			}
		end
	end
	for userId, row in pairs(memory) do
		local existing = byId[userId]
		local value = kind == "Waves" and row.wave or row.xp
		if not existing or value >= (existing.Value or 0) then
			byId[userId] = {
				UserId = userId,
				Name = row.name,
				Value = value,
				Wave = row.wave,
				XP = row.xp,
			}
		else
			existing.Name = existing.Name or row.name
			existing.Wave = math.max(existing.Wave or 0, row.wave)
			existing.XP = math.max(existing.XP or 0, row.xp)
		end
	end
	local rows = {}
	for _, e in pairs(byId) do
		if not e.Name or e.Name == "" or e.Name == tostring(e.UserId) then
			e.Name = resolveName(e.UserId, e.Name)
		end
		table.insert(rows, e)
	end
	table.sort(rows, function(a, b)
		if a.Value == b.Value then
			return (a.Wave or 0) > (b.Wave or 0)
		end
		return a.Value > b.Value
	end)
	local top = {}
	for i = 1, math.min(20, #rows) do
		table.insert(top, rows[i])
	end
	return top
end

local function fetchStore(kind: string): { any }
	local store = kind == "Waves" and waveStore or xpStore
	if not store then
		return {}
	end
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, 20)
	end)
	if not ok or not pages then
		return {}
	end
	local entries = {}
	for _, item in ipairs(pages:GetCurrentPage()) do
		local uid = tonumber(item.key) or 0
		local mem = memory[uid]
		table.insert(entries, {
			UserId = uid,
			Value = item.value,
			Name = mem and mem.name or nil,
			Wave = mem and mem.wave or (kind == "Waves" and item.value or 0),
			XP = mem and mem.xp or (kind == "XP" and item.value or 0),
		})
	end
	return entries
end

function LeaderboardService:Init(services)
	DataService = services.DataService
	local RemoteService = services.RemoteService
	xpStore = getOrdered(GameConfig.DataStore.LeaderboardXP)
	waveStore = getOrdered(GameConfig.DataStore.LeaderboardWaves)
	if not xpStore or not waveStore then
		Log.Write("Leaderboard", "OrderedDataStore unavailable — using in-memory board (Studio OK)", "WARN")
	else
		Log.Write("Leaderboard", "OrderedDataStore ready")
	end

	local getLb = RemoteService.GetRemote(RemoteNames.GetLeaderboard)
	if getLb then
		getLb.OnServerInvoke = function(_player, kind)
			kind = kind == "Waves" and "Waves" or "XP"
			-- Всегда свежие онлайн-профили; кэш чтения не используем в рамках сессии
			LeaderboardService.PushAllOnline()
			local entries = buildFromMemory(kind)
			-- Дополнить оффлайн-игроками из DataStore (онлайн уже в memory и побеждают)
			local storeEntries = fetchStore(kind)
			if #storeEntries > 0 then
				entries = mergeStorePage(kind, storeEntries)
			end
			return { success = true, entries = entries }
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		LeaderboardService.PushPlayer(player)
	end)
	game:BindToClose(function()
		LeaderboardService.PushAllOnline()
	end)

	-- После Init всех сервисов — докинуть онлайн в топ
	task.defer(function()
		task.wait(1)
		pcall(function()
			LeaderboardService.PushAllOnline()
		end)
	end)

	-- Периодический пуш (Studio без leave)
	task.spawn(function()
		while true do
			task.wait(30)
			pcall(LeaderboardService.PushAllOnline)
		end
	end)
end

return LeaderboardService
