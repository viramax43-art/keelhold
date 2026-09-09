--[[
	DataService — профили через БД:
	  Studio → LogServer http://127.0.0.1:8765/profile/{userId} (основное)
	  Live   → DataStore
	  Плюс атрибуты BD_* на игроке, чтобы HUD не зависел от гонки RemoteEvent.
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ProfileTemplate = require(ReplicatedStorage.Shared.Util.ProfileTemplate)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local Log = require(ReplicatedStorage.Shared.Util.Log)
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)

local DataService = {}
local profiles = {}
local loadDone = {} -- [userId] = true after first load attempt finished
local store = nil
local RemoteService = nil
local STUDIO_URL = "http://127.0.0.1:8765/profile/"
local saveDebounce = {}
local lastSaveClock = {}
local forcedSaveQueued = {}

local function safeCall(fn, ...)
	local args = table.pack(...)
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return fn(table.unpack(args, 1, args.n))
		end)
		if ok then
			return true, result
		end
		Log.Write("Data", string.format("Attempt %d failed: %s", attempt, tostring(result)), "WARN")
		if attempt < 3 then
			task.wait(1 * attempt)
		end
	end
	return false, nil
end

local function getStore()
	if store ~= nil then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.DataStore.PlayerProfile)
	end)
	if ok then
		store = result
	else
		store = false
		Log.Write("Data", "DataStore unavailable; Studio LogServer is the profile DB")
	end
	return store
end

local function loadFromStudioModule(userId: number)
	local serverFolder = script.Parent and script.Parent.Parent
	local dataFolder = serverFolder and serverFolder:FindFirstChild("Data")
	local mod = dataFolder and dataFolder:FindFirstChild("StudioProfiles")
	if not mod or not mod:IsA("ModuleScript") then
		Log.Write("Data", "StudioProfiles module missing under Server.Data", "WARN")
		return nil
	end
	-- Clone + require, иначе Rojo-обновление Source не видно из-за кэша require
	local ok, tbl = pcall(function()
		local holder = Instance.new("Folder")
		holder.Name = "_StudioProfilesLoad"
		holder.Parent = script
		local clone = mod:Clone()
		clone.Parent = holder
		local result = require(clone)
		holder:Destroy()
		return result
	end)
	if not ok or type(tbl) ~= "table" then
		ok, tbl = pcall(require, mod)
		if not ok or type(tbl) ~= "table" then
			Log.Write("Data", "StudioProfiles require failed: " .. tostring(tbl), "WARN")
			return nil
		end
	end
	local rawJson = tbl[userId] or tbl[tostring(userId)]
	if type(rawJson) ~= "string" or rawJson == "" then
		return nil
	end
	local okJ, data = pcall(function()
		return HttpService:JSONDecode(rawJson)
	end)
	if okJ and type(data) == "table" then
		return data
	end
	Log.Write("Data", "StudioProfiles JSON decode failed for " .. tostring(userId), "WARN")
	return nil
end

local function profileScore(p): number
	if type(p) ~= "table" then
		return -1
	end
	return (tonumber(p.TotalXP) or 0)
		+ (tonumber(p.Gold) or 0)
		+ (tonumber(p.HighestWave) or 0) * 1000
		+ (tonumber(p.PrestigePoints) or 0) * 500
		+ (tonumber(p.OwnedArmorTier) or 0) * 50
end

-- Устаревший снимок (меньше TotalXP) нельзя писать поверх прогресса.
-- Gold может падать (шоп) — смотрим TotalXP / HighestWave.
local function isStaleVsExisting(incoming, existing): boolean
	if type(incoming) ~= "table" or type(existing) ~= "table" then
		return false
	end
	local inXp = tonumber(incoming.TotalXP) or 0
	local exXp = tonumber(existing.TotalXP) or 0
	if inXp < exXp then
		return true
	end
	if inXp == exXp then
		local inWave = tonumber(incoming.HighestWave) or 0
		local exWave = tonumber(existing.HighestWave) or 0
		if inWave < exWave then
			return true
		end
	end
	return false
end

local function httpLoadProfile(userId: number)
	local urls = {
		"http://127.0.0.1:8765/profile/" .. tostring(userId),
		"http://localhost:8765/profile/" .. tostring(userId),
	}
	for _, url in ipairs(urls) do
		local ok, body = pcall(function()
			return HttpService:GetAsync(url)
		end)
		if ok and body and body ~= "" and body ~= "missing" then
			local okJ, data = pcall(function()
				return HttpService:JSONDecode(body)
			end)
			if okJ and type(data) == "table" then
				return data
			end
		end
	end
	return nil
end

-- Не ждать вечно, если LogServer тупит; модуль StudioProfiles — основной fallback
local function httpLoadProfileTimed(userId: number, timeoutSec: number?)
	local result = nil
	local done = false
	task.spawn(function()
		result = httpLoadProfile(userId)
		done = true
	end)
	local deadline = os.clock() + (timeoutSec or 1.5)
	while not done and os.clock() < deadline do
		task.wait(0.05)
	end
	return result
end

local function studioLoad(userId: number)
	-- Берём САМЫЙ богатый источник: модуль Rojo и/или LogServer HTTP
	local best = nil
	local bestScore = -1
	local function consider(data, src: string)
		if type(data) ~= "table" then
			return
		end
		local s = profileScore(data)
		if s > bestScore then
			best = data
			bestScore = s
			Log.Write("Data", string.format("studioLoad candidate %s score=%d Gold=%s", src, s, tostring(data.Gold)))
		end
	end
	-- Сначала модуль (мгновенно), потом HTTP
	consider(loadFromStudioModule(userId), "StudioProfiles")
	consider(httpLoadProfileTimed(userId, 1.5), "LogServer")
	return best
end

local function studioLoadWithRetry(userId: number)
	local data = studioLoad(userId)
	if data then
		return data
	end
	for attempt = 1, 4 do
		task.wait(0.3 * attempt)
		data = studioLoad(userId)
		if data then
			return data
		end
	end
	return nil
end

local function studioSave(userId: number, profile, force: boolean?): boolean
	local clean = Util.PrepareProfileForStorage(profile)
	local ok, json = pcall(function()
		return HttpService:JSONEncode(clean)
	end)
	if not ok or type(json) ~= "string" then
		Log.Write("Data", "studioSave JSONEncode failed: " .. tostring(json), "WARN")
		return false
	end

	local gold = tonumber(clean.Gold) or 0
	local xp = tonumber(clean.XP) or 0
	local totalXp = tonumber(clean.TotalXP) or 0
	local wave = tonumber(clean.HighestWave) or 0

	-- Только модуль Rojo (без HTTP) — иначе зависший LogServer блокирует сейв навсегда
	if not force then
		local existing = loadFromStudioModule(userId)
		if existing and isStaleVsExisting(clean, existing) then
			Log.Write(
				"Data",
				string.format(
					"Skip stale studioSave userId=%d inXP=%d diskXP=%d",
					userId,
					totalXp,
					tonumber(existing.TotalXP) or 0
				),
				"WARN"
			)
			return true
		end
	end

	-- Маркеры в Output (Watch-Logs). Полный JSON только print — НЕ через /log
	-- (иначе старые батчи Log.Write дают Skip stale и рвут соединения).
	local meta = string.format("__BD_PROFILE_META__|%d|%d|%d|%d|%d", userId, gold, xp, totalXp, wave)
	print(string.format("[BridgeDefense][Data] %s", meta))
	if #json < 12000 then
		print(string.format("[BridgeDefense][Data] __BD_PROFILE_SAVE__|%d|%s", userId, json))
	end
	-- Короткий META в /log (без полного JSON) — запасной канал
	Log.Write("Data", meta)

	-- HTTP профиль в фоне (один POST)
	task.spawn(function()
		pcall(function()
			HttpService.HttpEnabled = true
		end)
		local url = string.format("http://127.0.0.1:8765/profile/%d%s", userId, force and "?force=1" or "")
		local okPost, err = pcall(function()
			HttpService:PostAsync(url, json, Enum.HttpContentType.ApplicationJson)
		end)
		if okPost then
			-- без лишнего Log.Write — меньше /log спама во время боя
		else
			local ok2 = pcall(function()
				HttpService:PostAsync(
					string.format("http://localhost:8765/profile/%d%s", userId, force and "?force=1" or ""),
					json,
					Enum.HttpContentType.ApplicationJson
				)
			end)
			if not ok2 then
				Log.Write("Data", "LogServer POST fail (markers still emitted): " .. tostring(err), "WARN")
			end
		end
	end)

	return true
end

local function isNearFreshTemplate(p): boolean
	if type(p) ~= "table" then
		return true
	end
	local templateGold = ProfileTemplate.Gold or 100
	return (tonumber(p.TotalXP) or 0) == 0
		and (tonumber(p.HighestWave) or 0) == 0
		and (tonumber(p.PrestigePoints) or 0) == 0
		and (tonumber(p.Gold) or 0) <= templateGold
end

local function syncPlayerAttrs(player: Player, profile)
	if not player or not profile then
		return
	end
	player:SetAttribute("BD_Gold", tonumber(profile.Gold) or 0)
	player:SetAttribute("BD_XP", tonumber(profile.XP) or 0)
	player:SetAttribute("BD_TotalXP", tonumber(profile.TotalXP) or 0)
	player:SetAttribute("BD_Level", tonumber(profile.Level) or 1)
	player:SetAttribute("BD_ProfileReady", true)
end

local function migrateInventory(profile, raw)
	profile.WeaponCopies = profile.WeaponCopies or {}
	profile.ArmorCopies = profile.ArmorCopies or {}
	profile.SquadArmor = profile.SquadArmor or { [1] = 0, [2] = 0, [3] = 0, [4] = 0 }
	local rawHadCopies = type(raw) == "table" and type(raw.WeaponCopies) == "table"
	local copyStock = 0
	if rawHadCopies then
		for _, tiers in pairs(raw.WeaponCopies) do
			if type(tiers) == "table" then
				for _, n in pairs(tiers) do
					copyStock += tonumber(n) or 0
				end
			end
		end
	end
	if copyStock == 0 then
		profile.WeaponCopies = {}
		for wType, maxTier in pairs(profile.OwnedWeapons or {}) do
			local t = tonumber(maxTier) or 0
			if t > 0 then
				profile.WeaponCopies[wType] = { [t] = 1 }
			end
		end
		profile.WeaponCopies.Pistol = profile.WeaponCopies.Pistol or {}
		profile.WeaponCopies.Pistol[1] = math.max(profile.WeaponCopies.Pistol[1] or 0, 4)
	end
	local armorStock = 0
	for _, n in pairs(profile.ArmorCopies) do
		armorStock += tonumber(n) or 0
	end
	if armorStock == 0 and (profile.OwnedArmorTier or 0) > 0 then
		local t = profile.OwnedArmorTier
		profile.ArmorCopies[t] = 1
		if (profile.EquippedArmorTier or 0) > 0 then
			for s = 1, 4 do
				if (profile.SquadArmor[s] or 0) == 0 then
					profile.SquadArmor[s] = profile.EquippedArmorTier
					break
				end
			end
		end
	end
end

local function loadProfile(player: Player)
	local userId = player.UserId
	local studioRaw = nil
	local dsRaw = nil

	if RunService:IsStudio() then
		studioRaw = studioLoadWithRetry(userId)
		if studioRaw then
			Log.Write(
				"Data",
				string.format(
					"DB load OK userId=%d %s Gold=%s XP=%s Wave=%s",
					userId,
					player.Name,
					tostring(studioRaw.Gold),
					tostring(studioRaw.XP),
					tostring(studioRaw.HighestWave)
				)
			)
		else
			Log.Write(
				"Data",
				string.format("DB load MISS userId=%d %s — check StudioProfiles.lua / Watch-Logs", userId, player.Name),
				"WARN"
			)
		end
	end

	-- В Studio DataStore часто пустой/устаревший — берём только если богаче LogServer
	local ds = getStore()
	if ds then
		local ok, data = safeCall(ds.GetAsync, ds, tostring(userId))
		if ok and type(data) == "table" then
			dsRaw = data
		end
	end

	local raw = nil
	if RunService:IsStudio() then
		if studioRaw and dsRaw then
			raw = if profileScore(studioRaw) >= profileScore(dsRaw) then studioRaw else dsRaw
		else
			raw = studioRaw or dsRaw
		end
	else
		raw = dsRaw or studioRaw
	end

	local loadedFromDb = raw ~= nil
	local profile = Util.ReconcileProfile(raw, ProfileTemplate)
	Util.NormalizeProfileMaps(profile)
	profile.Level = Util.LevelFromTotalXP(profile.TotalXP or 0, GameConfig.XPPerLevel, GameConfig.XPPerLevelGrowth)
	migrateInventory(profile, raw)
	Util.NormalizeProfileMaps(profile)

	profiles[userId] = profile
	loadDone[userId] = true
	syncPlayerAttrs(player, profile)

	-- Не пишем на диск при загрузке: stale StudioProfiles + studioSave затирали свежий JSON.
	if RunService:IsStudio() and not loadedFromDb and not isNearFreshTemplate(profile) then
		studioSave(userId, profile)
	elseif RunService:IsStudio() and not loadedFromDb then
		Log.Write("Data", "Skip initial DB write for fresh template (keep existing file if any)")
	end
	return profile
end

function DataService.GetProfile(player: Player)
	return profiles[player.UserId]
end

function DataService.SaveProfile(player: Player, immediate: boolean?, bypassRateLimit: boolean?)
	local profile = profiles[player.UserId]
	if not profile then
		return
	end
	local userId = player.UserId
	if not immediate then
		if saveDebounce[userId] then
			return
		end
		saveDebounce[userId] = true
		task.delay(3.0, function()
			saveDebounce[userId] = nil
			DataService.SaveProfile(player, true)
		end)
		return
	end
	local now = os.clock()
	if not bypassRateLimit and lastSaveClock[userId] and (now - lastSaveClock[userId]) < 2.0 then
		if not forcedSaveQueued[userId] then
			forcedSaveQueued[userId] = true
			local waitTime = math.max(0.05, 2.0 - (now - lastSaveClock[userId]))
			task.delay(waitTime, function()
				forcedSaveQueued[userId] = nil
				if profiles[userId] and player.Parent then
					DataService.SaveProfile(player, true)
				end
			end)
		end
		return
	end
	lastSaveClock[userId] = now
	syncPlayerAttrs(player, profile)

	-- Обновить лидерборд при каждом реальном сейве
	task.defer(function()
		pcall(function()
			local LB = require(script.Parent.LeaderboardService)
			if LB and LB.PushPlayer then
				LB.PushPlayer(player)
			end
		end)
	end)

	local ds = getStore()
	if ds then
		local ok = safeCall(ds.SetAsync, ds, tostring(userId), Util.PrepareProfileForStorage(profile))
		if not ok then
			Log.Write("Data", "CRITICAL: Failed to save DataStore for " .. player.Name, "ERROR")
		end
	end

	if RunService:IsStudio() then
		local existing = loadFromStudioModule(userId)
		if existing and isStaleVsExisting(profile, existing) then
			Log.Write(
				"Data",
				string.format(
					"Skip DB overwrite: disk richer (diskXP=%s memXP=%s)",
					tostring(existing.TotalXP),
					tostring(profile.TotalXP)
				),
				"WARN"
			)
		else
			local saved = studioSave(userId, profile)
			if not saved then
				Log.Write("Data", "CRITICAL: LogServer DB save failed for " .. player.Name, "ERROR")
			end
		end
	end
end

function DataService.ResetProfile(player: Player)
	local fresh = Util.DeepCopy(ProfileTemplate)
	fresh.Level = Util.LevelFromTotalXP(0, GameConfig.XPPerLevel, GameConfig.XPPerLevelGrowth)
	profiles[player.UserId] = fresh
	loadDone[player.UserId] = true
	saveDebounce[player.UserId] = nil
	forcedSaveQueued[player.UserId] = nil
	syncPlayerAttrs(player, fresh)
	DataService.NotifyProfile(player)
	-- Force overwrite DB on explicit reset
	if RunService:IsStudio() then
		studioSave(player.UserId, fresh, true)
	end
	local ds = getStore()
	if ds then
		safeCall(ds.SetAsync, ds, tostring(player.UserId), fresh)
	end
	Log.Write("Data", player.Name .. " profile reset (new player)")
	return fresh
end

function DataService.NotifyProfile(player: Player)
	local profile = profiles[player.UserId]
	if not profile then
		return
	end
	syncPlayerAttrs(player, profile)
	if RemoteService then
		RemoteService.FireClient(player, RemoteNames.ProfileUpdated, Util.DeepCopy(profile))
	end
end

local function notifyWhenClientReady(player: Player)
	task.spawn(function()
		-- Клиент часто пропускает первый FireClient — шлём несколько раз
		for i = 1, 8 do
			if not player.Parent then
				return
			end
			if i == 1 then
				task.wait(0.5)
			else
				task.wait(1.0)
			end
			if profiles[player.UserId] then
				DataService.NotifyProfile(player)
			end
		end
	end)
end

function DataService.AddGold(player: Player, amount: number, reason: string?)
	local profile = profiles[player.UserId]
	if not profile then
		return
	end
	local before = profile.Gold or 0
	profile.Gold = before + amount
	Log.Write("Gold", string.format("%s %+d (%s) %d → %d", player.Name, amount, reason or "?", before, profile.Gold))
	DataService.NotifyProfile(player)
	DataService.SaveProfile(player, false)
end

function DataService.AddXP(player: Player, amount: number, reason: string?)
	local profile = profiles[player.UserId]
	if not profile then
		return
	end
	profile.XP = (profile.XP or 0) + amount
	profile.TotalXP = (profile.TotalXP or 0) + amount
	profile.Level = Util.LevelFromTotalXP(profile.TotalXP, GameConfig.XPPerLevel, GameConfig.XPPerLevelGrowth)
	Log.Write("XP", string.format("%s %+d (%s) XP=%d Lv=%d", player.Name, amount, reason or "?", profile.XP, profile.Level))
	DataService.NotifyProfile(player)
	DataService.SaveProfile(player, false)
end

function DataService:Init(services)
	RemoteService = services.RemoteService
	if RunService:IsStudio() then
		Log.Write("Data", "Studio DB = LogServer(:8765) + Watch-Logs + StudioProfiles (автономно через open-studio.ps1)")
		pcall(function()
			HttpService.HttpEnabled = true
		end)
	else
		Log.Write("Data", "Profile DB = DataStore")
	end

	local getProfile = RemoteService.GetRemote(RemoteNames.GetProfile)
	if getProfile and getProfile:IsA("RemoteFunction") then
		getProfile.OnServerInvoke = function(player)
			local deadline = os.clock() + 12
			while player.Parent and not loadDone[player.UserId] and os.clock() < deadline do
				task.wait(0.1)
			end
			local profile = profiles[player.UserId]
			return profile and Util.DeepCopy(profile) or nil
		end
	end

	local lastReset = {}
	local resetProfile = RemoteService.GetRemote(RemoteNames.ResetProfile)
	if resetProfile and resetProfile:IsA("RemoteFunction") then
		resetProfile.OnServerInvoke = function(player)
			local uid = player.UserId
			local now = os.clock()
			if lastReset[uid] and (now - lastReset[uid]) < 2 then
				return { success = false, error = "Подожди секунду" }
			end
			lastReset[uid] = now
			local profile = DataService.ResetProfile(player)
			return { success = true, profile = Util.DeepCopy(profile) }
		end
	end

	local function onPlayer(player: Player)
		task.spawn(function()
			loadProfile(player)
			DataService.NotifyProfile(player)
			notifyWhenClientReady(player)
		end)
	end

	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		DataService.SaveProfile(player, true, true)
		profiles[player.UserId] = nil
		loadDone[player.UserId] = nil
		saveDebounce[player.UserId] = nil
		forcedSaveQueued[player.UserId] = nil
	end)

	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			DataService.SaveProfile(player, true, true)
		end
		task.wait(1.5)
	end)

	-- Автосейв в Studio каждые 8с
	if RunService:IsStudio() then
		task.spawn(function()
			while true do
				task.wait(8)
				for _, player in ipairs(Players:GetPlayers()) do
					if profiles[player.UserId] then
						DataService.SaveProfile(player, true, true)
					end
				end
			end
		end)
	end
end

return DataService
