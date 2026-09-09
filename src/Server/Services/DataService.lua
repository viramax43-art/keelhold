--[[
	DataService — профили через Roblox DataStoreService (UpdateAsync + session lock).
	Публичный API сохранён: GetProfile, SaveProfile, AddGold, AddXP, ResetProfile, NotifyProfile.
	LogServer / StudioProfiles — только при AllowLegacyStudioFallback (не production).
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

local profiles = {} -- [userId] = profile Data
local saveStates = {} -- [userId] = state
local loadDone = {} -- [userId] = true after load attempt finished
local store = nil
local backupStore = nil
local RemoteService = nil

local DS = GameConfig.DataStore or {}
local SESSION_LOCK_TTL = DS.SessionLockTTL or 120
local SESSION_HEARTBEAT_INTERVAL = DS.SessionHeartbeatInterval or 45
local AUTO_SAVE_INTERVAL = DS.AutoSaveInterval or 60
local MAX_LOAD_RETRIES = DS.MaxLoadRetries or 8
local MAX_SAVE_RETRIES = DS.MaxSaveRetries or 5
local ALLOW_LEGACY = DS.AllowLegacyStudioFallback == true
local SCHEMA_VERSION = 2

local SESSION_ID = game.JobId
if SESSION_ID == "" then
	SESSION_ID = "Studio-" .. HttpService:GenerateGUID(false)
end

local LOAD_DELAYS = { 2, 4, 6, 8, 10, 12, 15, 20 }

local function dsCfg()
	return GameConfig.DataStore or DS
end

local function retryDelay(attempt: number): number
	local base = math.min(2 ^ (attempt - 1), 20)
	return base + math.random() * 0.5
end

local function shortSession(id: string?): string
	local s = tostring(id or "")
	if #s <= 12 then
		return s
	end
	return string.sub(s, 1, 8) .. "…"
end

local function getStore()
	if store ~= nil then
		return store
	end
	local name = (dsCfg().PlayerProfile) or "BridgeDefense_Profile_v1"
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(name)
	end)
	if ok then
		store = result
	else
		store = false
		Log.Write("Data", "PROFILE_LOAD_FAILED DataStore GetDataStore: " .. tostring(result), "ERROR")
	end
	return store
end

local function getBackupStore()
	if backupStore ~= nil then
		return backupStore
	end
	local name = (dsCfg().ProfileBackups) or "BridgeDefense_ProfileBackups_v1"
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(name)
	end)
	if ok then
		backupStore = result
	else
		backupStore = false
	end
	return backupStore
end

-- ─── Envelope / migration ───────────────────────────────────────────

local function isEnvelope(raw): boolean
	return type(raw) == "table" and type(raw.Data) == "table" and type(raw.Meta) == "table"
end

local function normalizeEnvelope(raw, _userId: number)
	if isEnvelope(raw) then
		local env = {
			SchemaVersion = tonumber(raw.SchemaVersion) or 1,
			Data = raw.Data,
			Meta = {
				Revision = tonumber(raw.Meta.Revision) or 0,
				CreatedAt = tonumber(raw.Meta.CreatedAt) or os.time(),
				UpdatedAt = tonumber(raw.Meta.UpdatedAt) or os.time(),
				SessionId = tostring(raw.Meta.SessionId or ""),
				SessionStartedAt = tonumber(raw.Meta.SessionStartedAt) or 0,
				LastHeartbeatAt = tonumber(raw.Meta.LastHeartbeatAt) or 0,
			},
		}
		return env
	end

	local legacyData = if type(raw) == "table" then raw else Util.DeepCopy(ProfileTemplate)
	return {
		SchemaVersion = 1,
		Data = legacyData,
		Meta = {
			Revision = 0,
			CreatedAt = os.time(),
			UpdatedAt = os.time(),
			SessionId = "",
			SessionStartedAt = 0,
			LastHeartbeatAt = 0,
		},
	}
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

local function materializeProfile(dataTable, rawSource)
	local profile = Util.ReconcileProfile(dataTable, ProfileTemplate)
	Util.NormalizeProfileMaps(profile)
	profile.Level = Util.LevelFromTotalXP(profile.TotalXP or 0, GameConfig.XPPerLevel, GameConfig.XPPerLevelGrowth)
	migrateInventory(profile, rawSource or dataTable)
	Util.NormalizeProfileMaps(profile)
	return profile
end

local function validateProfileNumbers(profile): (boolean, string?)
	if type(profile) ~= "table" then
		return false, "not a table"
	end
	local function nonNeg(name)
		local v = tonumber(profile[name])
		if v == nil or v ~= v or v < 0 then
			return false, name
		end
		return true
	end
	for _, key in ipairs({ "Gold", "XP", "TotalXP", "PrestigePoints", "Ascensions", "HighestWave" }) do
		local ok, bad = nonNeg(key)
		if not ok then
			return false, "invalid " .. tostring(bad)
		end
	end
	local level = tonumber(profile.Level)
	if level == nil or level < 1 or level > 10000 then
		return false, "invalid Level"
	end
	local okEnc, encErr = pcall(function()
		HttpService:JSONEncode(Util.PrepareProfileForStorage(profile))
	end)
	if not okEnc then
		return false, "JSONEncode failed: " .. tostring(encErr)
	end
	return true, nil
end

local function syncPlayerAttrs(player: Player, profile, ready: boolean?)
	if not player then
		return
	end
	if profile then
		player:SetAttribute("BD_Gold", tonumber(profile.Gold) or 0)
		player:SetAttribute("BD_XP", tonumber(profile.XP) or 0)
		player:SetAttribute("BD_TotalXP", tonumber(profile.TotalXP) or 0)
		player:SetAttribute("BD_Level", tonumber(profile.Level) or 1)
	end
	player:SetAttribute("BD_ProfileReady", ready == true)
end

-- ─── Legacy Studio fallback (optional) ──────────────────────────────

local function loadFromStudioModule(userId: number)
	local serverFolder = script.Parent and script.Parent.Parent
	local dataFolder = serverFolder and serverFolder:FindFirstChild("Data")
	local mod = dataFolder and dataFolder:FindFirstChild("StudioProfiles")
	if not mod or not mod:IsA("ModuleScript") then
		return nil
	end
	local ok, tbl = pcall(require, mod)
	if not ok or type(tbl) ~= "table" then
		return nil
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
	return nil
end

-- ─── Session acquire / save ─────────────────────────────────────────

local function tryAcquireSession(userId: number): (boolean, any?, string?)
	local ds = getStore()
	if not ds then
		return false, nil, "DataStore unavailable"
	end

	local acquired = false
	local ok, result = pcall(function()
		return ds:UpdateAsync(tostring(userId), function(current)
			local now = os.time()
			local envelope = normalizeEnvelope(current, userId)
			local meta = envelope.Meta
			local currentSession = meta.SessionId or ""
			local lastHeartbeat = tonumber(meta.LastHeartbeatAt) or 0

			local lockIsActive = currentSession ~= ""
				and currentSession ~= SESSION_ID
				and (now - lastHeartbeat) < SESSION_LOCK_TTL

			if lockIsActive then
				acquired = false
				return envelope
			end

			acquired = true
			local wasLegacy = not isEnvelope(current)
			if wasLegacy then
				Log.Write("Data", string.format("PROFILE_LEGACY_MIGRATED userId=%d", userId))
			end

			meta.SessionId = SESSION_ID
			meta.SessionStartedAt = if (tonumber(meta.SessionStartedAt) or 0) > 0
				then meta.SessionStartedAt
				else now
			meta.LastHeartbeatAt = now
			meta.UpdatedAt = now
			meta.Revision = (tonumber(meta.Revision) or 0) + 1
			envelope.Meta = meta
			envelope.SchemaVersion = math.max(tonumber(envelope.SchemaVersion) or 1, SCHEMA_VERSION)

			-- Новый игрок: пустой current → шаблон
			if type(current) ~= "table" then
				envelope.Data = Util.DeepCopy(ProfileTemplate)
			end

			return envelope
		end)
	end)

	if not ok then
		return false, nil, "DataStore UpdateAsync failed: " .. tostring(result)
	end
	if not acquired then
		return false, result, "Profile is locked by another server"
	end
	return true, result, nil
end

local function createBackup(userId: number, profile, revision: number, reason: string?)
	local bs = getBackupStore()
	if not bs then
		return false
	end
	local key = string.format("%d:%d", userId, revision)
	local payload = {
		Reason = reason or "backup",
		At = os.time(),
		SessionId = SESSION_ID,
		Data = Util.PrepareProfileForStorage(profile),
	}
	local ok, err = pcall(function()
		bs:SetAsync(key, payload)
	end)
	if ok then
		Log.Write("Data", string.format("PROFILE_BACKUP_CREATED userId=%d rev=%d reason=%s", userId, revision, tostring(reason)))
	else
		Log.Write("Data", "Backup failed: " .. tostring(err), "WARN")
	end
	return ok
end

local function saveProfileInternal(player: Player, reason: string?, releaseSession: boolean?): (boolean, string?)
	local userId = player.UserId
	local state = saveStates[userId]
	local profile = profiles[userId]
	if not state or not profile then
		return false, "Profile is not loaded"
	end

	local ds = getStore()
	if not ds then
		return false, "DataStore unavailable"
	end

	local valid, verr = validateProfileNumbers(profile)
	if not valid then
		Log.Write("Data", string.format("PROFILE_SAVE_FAILED userId=%d invalid=%s", userId, tostring(verr)), "ERROR")
		return false, verr
	end

	local snapshot = Util.DeepCopy(profile)
	local snapshotRevision = state.Revision
	local now = os.time()

	Log.Write(
		"Data",
		string.format(
			"PROFILE_SAVE_START userId=%d reason=%s rev=%d release=%s sess=%s",
			userId,
			tostring(reason),
			snapshotRevision,
			tostring(releaseSession == true),
			shortSession(SESSION_ID)
		)
	)

	local lostOwnership = false
	local ok, result = pcall(function()
		return ds:UpdateAsync(tostring(userId), function(current)
			local envelope = normalizeEnvelope(current, userId)
			if envelope.Meta.SessionId ~= SESSION_ID then
				lostOwnership = true
				return nil
			end
			envelope.Data = Util.PrepareProfileForStorage(snapshot)
			envelope.SchemaVersion = SCHEMA_VERSION
			envelope.Meta.Revision = (tonumber(envelope.Meta.Revision) or 0) + 1
			envelope.Meta.UpdatedAt = now
			if releaseSession then
				envelope.Meta.SessionId = ""
				envelope.Meta.SessionStartedAt = 0
				envelope.Meta.LastHeartbeatAt = 0
			else
				envelope.Meta.LastHeartbeatAt = now
			end
			return envelope
		end)
	end)

	if not ok then
		Log.Write("Data", string.format("PROFILE_SAVE_FAILED userId=%d err=%s", userId, tostring(result)), "ERROR")
		return false, tostring(result)
	end
	if result == nil then
		local msg = if lostOwnership then "Lost session ownership" else "UpdateAsync returned nil"
		Log.Write("Data", string.format("PROFILE_SAVE_FAILED userId=%d err=%s", userId, msg), "ERROR")
		return false, msg
	end

	state.LastSavedRevision = snapshotRevision
	if state.Revision == snapshotRevision then
		state.Dirty = false
	else
		state.Dirty = true
	end

	Log.Write("Data", string.format("PROFILE_SAVE_SUCCESS userId=%d rev=%d", userId, snapshotRevision))
	if releaseSession then
		Log.Write("Data", string.format("PROFILE_LOCK_RELEASED userId=%d", userId))
	end
	return true, nil
end

local function runSaveQueue(player: Player, reason: string?)
	local userId = player.UserId
	local state = saveStates[userId]
	if not state or state.SaveInProgress then
		if state then
			state.SaveRequested = true
		end
		return
	end

	state.SaveInProgress = true
	state.SaveRequested = false

	task.spawn(function()
		local attempt = 0
		while attempt < MAX_SAVE_RETRIES do
			attempt += 1
			local release = state.Closing == true
			local ok, err = saveProfileInternal(player, reason or "queue", release)
			if ok then
				break
			end
			Log.Write(
				"Data",
				string.format("PROFILE_SAVE_RETRY userId=%d attempt=%d err=%s", userId, attempt, tostring(err)),
				"WARN"
			)
			if state.Closing and attempt >= MAX_SAVE_RETRIES then
				break
			end
			task.wait(retryDelay(attempt))
		end

		-- Leaderboard push (best-effort)
		pcall(function()
			local LB = require(script.Parent.LeaderboardService)
			if LB and LB.PushPlayer and player.Parent then
				LB.PushPlayer(player)
			end
		end)

		state.SaveInProgress = false
		if state.SaveRequested or (state.Dirty and not state.Closing) then
			state.SaveRequested = false
			if profiles[userId] then
				runSaveQueue(player, "followup")
			end
		end
	end)
end

-- ─── Public API ─────────────────────────────────────────────────────

function DataService.IsProfileLoaded(player: Player): boolean
	return profiles[player.UserId] ~= nil and player:GetAttribute("BD_ProfileReady") == true
end

function DataService.GetProfileStatus(player: Player)
	local state = saveStates[player.UserId]
	return {
		Loaded = profiles[player.UserId] ~= nil,
		Dirty = state and state.Dirty or false,
		Revision = state and state.Revision or 0,
		LastSavedRevision = state and state.LastSavedRevision or 0,
		SaveInProgress = state and state.SaveInProgress or false,
		SessionId = SESSION_ID,
	}
end

function DataService.GetProfile(player: Player)
	return profiles[player.UserId]
end

function DataService.MarkDirty(player: Player, _reason: string?)
	local state = saveStates[player.UserId]
	if not state then
		return
	end
	state.Revision += 1
	state.Dirty = true
end

function DataService.NotifyProfile(player: Player)
	local profile = profiles[player.UserId]
	if not profile then
		return
	end
	syncPlayerAttrs(player, profile, true)
	if RemoteService then
		RemoteService.FireClient(player, RemoteNames.ProfileUpdated, Util.DeepCopy(profile))
	end
end

function DataService.BackupProfile(player: Player, reason: string?): boolean
	local userId = player.UserId
	local profile = profiles[userId]
	local state = saveStates[userId]
	if not profile or not state then
		return false
	end
	return createBackup(userId, profile, state.Revision, reason)
end

--[[
	SaveProfile(player, immediate?, force?, reason?)
	Не вызывает MarkDirty — вызывающий код должен MarkDirty после изменения профиля.
	immediate/force ставят сохранение в очередь без debounce.
]]
function DataService.SaveProfile(player: Player, immediate: boolean?, force: boolean?, reason: any?)
	local userId = player.UserId
	if not profiles[userId] or not saveStates[userId] then
		return
	end
	if typeof(force) == "string" and reason == nil then
		reason = force
		force = true
	end

	local reasonStr = if typeof(reason) == "string" then reason else nil

	if not immediate and not force then
		-- debounce: схлопываем частые AddGold/AddXP
		local state = saveStates[userId]
		if state.DebouncePending then
			return
		end
		state.DebouncePending = true
		task.delay(2.5, function()
			local st = saveStates[userId]
			if st then
				st.DebouncePending = false
			end
			if player.Parent and profiles[userId] and st and st.Dirty then
				runSaveQueue(player, reasonStr or "debounce")
			end
		end)
		return
	end

	runSaveQueue(player, reasonStr or "immediate")
end

function DataService.ReleaseProfile(player: Player)
	local userId = player.UserId
	-- память чистится снаружи после save; здесь только страховка release если ещё владеем
	local state = saveStates[userId]
	if state and profiles[userId] and not state.SaveInProgress then
		state.Closing = true
		saveProfileInternal(player, "ReleaseProfile", true)
	end
end

function DataService.ResetProfile(player: Player)
	local userId = player.UserId
	local state = saveStates[userId]
	local existing = profiles[userId]
	if not existing or not state then
		Log.Write("Data", "ResetProfile blocked: profile not loaded", "WARN")
		return nil
	end

	createBackup(userId, existing, state.Revision, "ResetProfile")

	local fresh = Util.DeepCopy(ProfileTemplate)
	fresh.Level = Util.LevelFromTotalXP(0, GameConfig.XPPerLevel, GameConfig.XPPerLevelGrowth)
	profiles[userId] = fresh
	state.Revision += 1
	state.Dirty = true
	syncPlayerAttrs(player, fresh, true)
	DataService.NotifyProfile(player)
	runSaveQueue(player, "ResetProfile")
	Log.Write("Data", player.Name .. " profile reset")
	return fresh
end

function DataService.AddGold(player: Player, amount: number, reason: string?)
	local profile = profiles[player.UserId]
	if not profile or not DataService.IsProfileLoaded(player) then
		return
	end
	local before = profile.Gold or 0
	profile.Gold = before + amount
	Log.Write("Gold", string.format("%s %+d (%s) %d → %d", player.Name, amount, reason or "?", before, profile.Gold))
	DataService.MarkDirty(player, reason or "Gold")
	DataService.NotifyProfile(player)
	DataService.SaveProfile(player, false)
end

function DataService.AddXP(player: Player, amount: number, reason: string?)
	local profile = profiles[player.UserId]
	if not profile or not DataService.IsProfileLoaded(player) then
		return
	end
	profile.XP = (profile.XP or 0) + amount
	profile.TotalXP = (profile.TotalXP or 0) + amount
	profile.Level = Util.LevelFromTotalXP(profile.TotalXP, GameConfig.XPPerLevel, GameConfig.XPPerLevelGrowth)
	Log.Write("XP", string.format("%s %+d (%s) XP=%d Lv=%d", player.Name, amount, reason or "?", profile.XP, profile.Level))
	DataService.MarkDirty(player, reason or "XP")
	DataService.NotifyProfile(player)
	DataService.SaveProfile(player, false)
end

-- ─── Load ───────────────────────────────────────────────────────────

local function loadProfile(player: Player): boolean
	local userId = player.UserId
	Log.Write("Data", string.format("PROFILE_LOAD_START userId=%d sess=%s", userId, shortSession(SESSION_ID)))
	syncPlayerAttrs(player, nil, false)

	local ds = getStore()

	-- Optional Studio migration path
	if not ds and ALLOW_LEGACY and RunService:IsStudio() then
		Log.Write("Data", "PROFILE_LOAD using legacy StudioProfiles fallback", "WARN")
		local legacy = loadFromStudioModule(userId)
		local profile = materializeProfile(legacy, legacy)
		profiles[userId] = profile
		saveStates[userId] = {
			Dirty = true,
			Revision = 1,
			LastSavedRevision = 0,
			SaveInProgress = false,
			SaveRequested = false,
			Closing = false,
			DebouncePending = false,
		}
		loadDone[userId] = true
		syncPlayerAttrs(player, profile, true)
		Log.Write("Data", "PROFILE_LOAD_SUCCESS (legacy fallback) userId=" .. userId)
		return true
	end

	if not ds then
		Log.Write("Data", "PROFILE_LOAD_FAILED userId=" .. userId .. " no DataStore", "ERROR")
		loadDone[userId] = true
		syncPlayerAttrs(player, nil, false)
		player:Kick("Не удалось загрузить профиль (DataStore). Включите API Services в Studio или переподключитесь.")
		return false
	end

	local acquired, envelope, err
	for attempt = 1, MAX_LOAD_RETRIES do
		acquired, envelope, err = tryAcquireSession(userId)
		if acquired and type(envelope) == "table" then
			break
		end
		Log.Write(
			"Data",
			string.format(
				"PROFILE_LOAD_RETRY userId=%d attempt=%d err=%s",
				userId,
				attempt,
				tostring(err)
			),
			"WARN"
		)
		local delaySec = LOAD_DELAYS[attempt] or (10 + attempt)
		task.wait(delaySec)
		if not player.Parent then
			loadDone[userId] = true
			return false
		end
	end

	if not acquired or type(envelope) ~= "table" then
		Log.Write("Data", string.format("PROFILE_LOAD_FAILED userId=%d err=%s", userId, tostring(err)), "ERROR")
		loadDone[userId] = true
		syncPlayerAttrs(player, nil, false)
		player:Kick("Не удалось загрузить профиль. Пожалуйста, переподключитесь.")
		return false
	end

	Log.Write("Data", string.format("PROFILE_LOCK_ACQUIRED userId=%d rev=%s", userId, tostring(envelope.Meta and envelope.Meta.Revision)))

	local profile = materializeProfile(envelope.Data, envelope.Data)
	local metaRev = tonumber(envelope.Meta and envelope.Meta.Revision) or 0

	profiles[userId] = profile
	saveStates[userId] = {
		Dirty = false,
		Revision = metaRev,
		LastSavedRevision = metaRev,
		SaveInProgress = false,
		SaveRequested = false,
		Closing = false,
		DebouncePending = false,
	}
	loadDone[userId] = true
	syncPlayerAttrs(player, profile, true)

	Log.Write(
		"Data",
		string.format(
			"PROFILE_LOAD_SUCCESS userId=%d Gold=%s TotalXP=%s Wave=%s",
			userId,
			tostring(profile.Gold),
			tostring(profile.TotalXP),
			tostring(profile.HighestWave)
		)
	)
	return true
end

local function notifyWhenClientReady(player: Player)
	task.spawn(function()
		for i = 1, 8 do
			if not player.Parent then
				return
			end
			task.wait(if i == 1 then 0.5 else 1.0)
			if profiles[player.UserId] and player:GetAttribute("BD_ProfileReady") then
				DataService.NotifyProfile(player)
			end
		end
	end)
end

function DataService:Init(services)
	RemoteService = services.RemoteService
	Log.Write(
		"Data",
		string.format(
			"Profile DB = DataStore(%s) UpdateAsync+SessionLock sess=%s legacyFallback=%s",
			tostring((dsCfg().PlayerProfile)),
			shortSession(SESSION_ID),
			tostring(ALLOW_LEGACY)
		)
	)

	local getProfile = RemoteService.GetRemote(RemoteNames.GetProfile)
	if getProfile and getProfile:IsA("RemoteFunction") then
		getProfile.OnServerInvoke = function(player)
			local deadline = os.clock() + 15
			while player.Parent and not loadDone[player.UserId] and os.clock() < deadline do
				task.wait(0.1)
			end
			if not DataService.IsProfileLoaded(player) then
				return nil
			end
			return Util.DeepCopy(profiles[player.UserId])
		end
	end

	local lastReset = {}
	local resetProfile = RemoteService.GetRemote(RemoteNames.ResetProfile)
	if resetProfile and resetProfile:IsA("RemoteFunction") then
		resetProfile.OnServerInvoke = function(player)
			if not DataService.IsProfileLoaded(player) then
				return { success = false, error = "Профиль не загружен" }
			end
			local uid = player.UserId
			local now = os.clock()
			if lastReset[uid] and (now - lastReset[uid]) < 2 then
				return { success = false, error = "Подожди секунду" }
			end
			lastReset[uid] = now
			local profile = DataService.ResetProfile(player)
			if not profile then
				return { success = false, error = "Сброс недоступен" }
			end
			return { success = true, profile = Util.DeepCopy(profile) }
		end
	end

	local function onPlayer(player: Player)
		task.spawn(function()
			local ok = loadProfile(player)
			if ok then
				DataService.NotifyProfile(player)
				notifyWhenClientReady(player)
			end
		end)
	end

	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
		local state = saveStates[userId]
		if state then
			state.Closing = true
			state.Dirty = true
			state.Revision += 1
		end
		-- Синхронная попытка в этом потоке + очередь
		if profiles[userId] and state then
			local deadline = os.clock() + 8
			while state.SaveInProgress and os.clock() < deadline do
				task.wait(0.05)
			end
			saveProfileInternal(player, "PlayerRemoving", true)
		end
		profiles[userId] = nil
		saveStates[userId] = nil
		loadDone[userId] = nil
	end)

	game:BindToClose(function()
		local list = Players:GetPlayers()
		local remaining = #list
		for _, player in ipairs(list) do
			task.spawn(function()
				local userId = player.UserId
				local state = saveStates[userId]
				if state then
					state.Closing = true
					state.Dirty = true
					state.Revision += 1
				end
				if profiles[userId] then
					local attempts = 0
					while attempts < MAX_SAVE_RETRIES do
						attempts += 1
						local ok = saveProfileInternal(player, "BindToClose", true)
						if ok then
							break
						end
						task.wait(retryDelay(attempts))
					end
				end
				remaining -= 1
			end)
		end
		local deadline = os.clock() + 25
		while remaining > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)

	-- Autosave (live + Studio)
	task.spawn(function()
		while true do
			task.wait(AUTO_SAVE_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				local state = saveStates[player.UserId]
				if state and state.Dirty and not state.Closing and not state.SaveInProgress then
					DataService.SaveProfile(player, true, true, "AutoSave")
				end
			end
		end
	end)

	-- Session heartbeat (one loop for all)
	task.spawn(function()
		while true do
			task.wait(SESSION_HEARTBEAT_INTERVAL)
			local ds = getStore()
			if not ds then
				continue
			end
			for userId, state in pairs(saveStates) do
				if state.Closing or state.SaveInProgress then
					continue
				end
				-- Heartbeat без перезаписи Data (только Meta), если не dirty
				if state.Dirty then
					local player = Players:GetPlayerByUserId(userId)
					if player then
						runSaveQueue(player, "HeartbeatDirty")
					end
				else
					local player = Players:GetPlayerByUserId(userId)
					local hbOk, hbResult = pcall(function()
						return ds:UpdateAsync(tostring(userId), function(current)
							local envelope = normalizeEnvelope(current, userId)
							if envelope.Meta.SessionId ~= SESSION_ID then
								return nil
							end
							envelope.Meta.LastHeartbeatAt = os.time()
							return envelope
						end)
					end)
					if (not hbOk) or hbResult == nil then
						Log.Write(
							"Data",
							string.format(
								"PROFILE_LOCK_LOST userId=%d sess=%s",
								userId,
								shortSession(SESSION_ID)
							),
							"ERROR"
						)
						profiles[userId] = nil
						saveStates[userId] = nil
						if player then
							syncPlayerAttrs(player, nil, false)
							player:Kick("Сессия профиля потеряна. Пожалуйста, переподключитесь.")
						end
					end
				end
			end
		end
	end)
end

return DataService
