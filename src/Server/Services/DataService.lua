--[[
	DataService — профили: DataStore или Studio backup (HTTP/файл).
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
local store = nil
local RemoteService = nil
local STUDIO_URL = "http://127.0.0.1:8765/profile/"
local saveDebounce = {}
local lastSaveClock = {}

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
		Log.Write("Data", "DataStore unavailable (place not published); using Studio backup persistence")
	end
	return store
end

local function studioLoad(userId: number)
	local ok, body = pcall(function()
		return HttpService:GetAsync(STUDIO_URL .. tostring(userId))
	end)
	if ok and body and body ~= "" then
		local okJ, data = pcall(function()
			return HttpService:JSONDecode(body)
		end)
		if okJ and type(data) == "table" then
			return data
		end
	end
	return nil
end

local function studioSave(userId: number, profile)
	local clean = Util.DeepCopy(profile)
	local ok, json = pcall(function()
		return HttpService:JSONEncode(clean)
	end)
	if not ok then
		return
	end
	pcall(function()
		HttpService:PostAsync(STUDIO_URL .. tostring(userId), json, Enum.HttpContentType.ApplicationJson)
	end)
end

local function loadProfile(player: Player)
	local userId = player.UserId
	local raw = nil
	local ds = getStore()
	if ds then
		for attempt = 1, 3 do
			local ok, data = safeCall(ds.GetAsync, ds, tostring(userId))
			if ok then
				raw = data
				break
			end
			task.wait(0.4 * attempt)
		end
	elseif RunService:IsStudio() then
		raw = studioLoad(userId)
		if raw then
			Log.Write("Data", string.format("Loaded Studio backup %s Gold=%s XP=%s", player.Name, tostring(raw.Gold), tostring(raw.XP)))
		end
	end
	local profile = Util.ReconcileProfile(raw, ProfileTemplate)
	profile.Level = Util.LevelFromTotalXP(profile.TotalXP or 0, GameConfig.XPPerLevel, GameConfig.XPPerLevelGrowth)
	profiles[userId] = profile
	return profile
end

function DataService.GetProfile(player: Player)
	return profiles[player.UserId]
end

function DataService.SaveProfile(player: Player, immediate: boolean?)
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
		task.delay(1.5, function()
			saveDebounce[userId] = nil
			DataService.SaveProfile(player, true)
		end)
		return
	end
	local now = os.clock()
	-- Rate-limit non-critical forced saves (leave/BindToClose still pass if >0.5s apart)
	if lastSaveClock[userId] and (now - lastSaveClock[userId]) < 0.5 then
		return
	end
	lastSaveClock[userId] = now
	local ds = getStore()
	if ds then
		local ok = safeCall(ds.SetAsync, ds, tostring(userId), profile)
		if not ok then
			Log.Write("Data", "CRITICAL: Failed to save profile for " .. player.Name, "ERROR")
		end
	elseif RunService:IsStudio() then
		studioSave(userId, profile)
	end
end

function DataService.NotifyProfile(player: Player)
	if RemoteService then
		RemoteService.FireClient(player, RemoteNames.ProfileUpdated, DataService.GetProfile(player))
	end
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
	Log.Write("Data", RunService:IsStudio() and "Studio profile backup via LogServer :8765" or "DataStore mode")

	local getProfile = RemoteService.GetRemote(RemoteNames.GetProfile)
	if getProfile and getProfile:IsA("RemoteFunction") then
		getProfile.OnServerInvoke = function(player)
			return DataService.GetProfile(player)
		end
	end

	Players.PlayerAdded:Connect(function(player)
		loadProfile(player)
		DataService.NotifyProfile(player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			loadProfile(player)
			DataService.NotifyProfile(player)
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		DataService.SaveProfile(player, true)
		profiles[player.UserId] = nil
		saveDebounce[player.UserId] = nil
	end)

	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			DataService.SaveProfile(player, true)
		end
		task.wait(1)
	end)
end

return DataService
