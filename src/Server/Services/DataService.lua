--[[
	DataService — профили через Roblox DataStoreService (UpdateAsync + session lock).
	Один UpdateAsync на игрока: очередь + FlushProfile / FlushAndReleaseProfile.
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
-- Бюджет одной серии save/retry должен быть заметно меньше TTL lock
local SAVE_TIME_BUDGET = math.min(55, math.floor(SESSION_LOCK_TTL * 0.45))
local FLUSH_TIMEOUT = 20
local BIND_CLOSE_TIMEOUT = 25
local BACKUP_RETRIES = 5
-- Studio без Enable Studio Access to API Services → локальный LogServer/StudioProfiles
local studioLocalMode = false
local STUDIO_PROFILE_URLS = {
	"http://127.0.0.1:8765/profile/",
	"http://localhost:8765/profile/",
}

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

local function newSaveState(revision: number)
	return {
		Dirty = false,
		Revision = revision,
		LastSavedRevision = revision,
		SaveInProgress = false,
		SaveRequested = false,
		Closing = false,
		TransferPending = false,
		ReleaseRequested = false,
		SessionReleased = false,
		FailedSaveCount = 0,
		LastSaveError = nil,
		NextRetryAt = 0,
		DebouncePending = false,
	}
end

-- ─── Envelope / migration ───────────────────────────────────────────

local function isEnvelope(raw): boolean
	return type(raw) == "table" and type(raw.Data) == "table" and type(raw.Meta) == "table"
end

local function normalizeEnvelope(raw, _userId: number)
	if isEnvelope(raw) then
		return {
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

local function isApiServicesError(err): boolean
	local msg = string.lower(tostring(err or ""))
	if msg == "" then
		return false
	end
	return string.find(msg, "api services", 1, true) ~= nil
		or string.find(msg, "studio access", 1, true) ~= nil
		or string.find(msg, "403", 1, true) ~= nil
		or string.find(msg, "must publish", 1, true) ~= nil
		or string.find(msg, "connectfail", 1, true) ~= nil
		or string.find(msg, "http 501", 1, true) ~= nil
		or string.find(msg, "http 502", 1, true) ~= nil
end

local function enableStudioLocalMode(reason: string?)
	if studioLocalMode then
		return
	end
	if not RunService:IsStudio() then
		return
	end
	studioLocalMode = true
	Log.Write(
		"Data",
		"PROFILE_STUDIO_LOCAL_MODE "
			.. tostring(reason or "DataStore unavailable")
			.. " — using LogServer/StudioProfiles (enable Game Settings → Security → Enable Studio Access to API Services for cloud DataStore)",
		"WARN"
	)
end

local function studioHttpLoad(userId: number)
	for _, base in ipairs(STUDIO_PROFILE_URLS) do
		local ok, body = pcall(function()
			return HttpService:GetAsync(base .. tostring(userId))
		end)
		if ok and type(body) == "string" and body ~= "" and body ~= "missing" then
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

local function studioHttpSave(userId: number, profile, force: boolean?): (boolean, string?)
	local payload = Util.PrepareProfileForStorage(profile)
	local okEnc, jsonOrErr = pcall(function()
		return HttpService:JSONEncode(payload)
	end)
	if not okEnc then
		return false, "JSONEncode failed: " .. tostring(jsonOrErr)
	end
	local suffix = if force then "?force=1" else ""
	local lastErr = "LogServer unreachable"
	for _, base in ipairs(STUDIO_PROFILE_URLS) do
		local ok, res = pcall(function()
			return HttpService:RequestAsync({
				Url = base .. tostring(userId) .. suffix,
				Method = "POST",
				Headers = { ["Content-Type"] = "application/json" },
				Body = jsonOrErr,
			})
		end)
		if ok and type(res) == "table" and res.Success and (res.StatusCode or 0) >= 200 and (res.StatusCode or 0) < 300 then
			return true, nil
		end
		lastErr = if ok and type(res) == "table"
			then string.format("HTTP %s %s", tostring(res.StatusCode), tostring(res.Body))
			else tostring(res)
	end
	return false, lastErr
end

local function probeDataStoreAvailable(): boolean
	local ds = getStore()
	if not ds then
		return false
	end
	local ok, err = pcall(function()
		ds:GetAsync("__BridgeDefense_Probe__")
	end)
	if ok then
		return true
	end
	if isApiServicesError(err) then
		return false
	end
	-- Другие временные ошибки: store есть, пробуем дальше на load
	return true
end

local function handleOwnershipLost(userId: number, player: Player?)
	Log.Write("Data", string.format("PROFILE_LOCK_LOST userId=%d sess=%s", userId, shortSession(SESSION_ID)), "ERROR")
	profiles[userId] = nil
	saveStates[userId] = nil
	if player and player.Parent then
		syncPlayerAttrs(player, nil, false)
		player:Kick("Сессия профиля потеряна. Пожалуйста, переподключитесь.")
	end
end
local function tryAcquireSession(userId: number): (boolean, any?, string?)
	local ds = getStore()
	if not ds then
		return false, nil, "DataStore unavailable"
	end

	local acquired = false
	local lockedByAnotherServer = false
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
				lockedByAnotherServer = true
				return nil
			end

			acquired = true
			if type(current) == "table" and not isEnvelope(current) then
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

			if type(current) ~= "table" then
				envelope.Data = Util.DeepCopy(ProfileTemplate)
			end

			return envelope
		end)
	end)

	if not ok then
		return false, nil, "DataStore UpdateAsync failed: " .. tostring(result)
	end
	if lockedByAnotherServer or not acquired then
		return false, nil, "Profile is locked by another server"
	end
	if type(result) ~= "table" then
		return false, nil, "Acquire returned empty"
	end
	return true, result, nil
end

local function createBackup(userId: number, profile, revision: number, reason: string?): boolean
	if studioLocalMode then
		-- В Studio local backup не в облаке; не блокируем Prestige/Reset
		Log.Write(
			"Data",
			string.format("PROFILE_BACKUP_SKIPPED studioLocal userId=%d reason=%s", userId, tostring(reason)),
			"WARN"
		)
		return true
	end
	local bs = getBackupStore()
	if not bs then
		Log.Write("Data", "PROFILE_BACKUP_FAILED no backup store", "ERROR")
		return false
	end
	local key = string.format("%d:%d", userId, revision)
	local payload = {
		Reason = reason or "backup",
		At = os.time(),
		SessionId = SESSION_ID,
		Data = Util.PrepareProfileForStorage(profile),
	}
	for attempt = 1, BACKUP_RETRIES do
		local ok, err = pcall(function()
			bs:SetAsync(key, payload)
		end)
		if ok then
			Log.Write(
				"Data",
				string.format("PROFILE_BACKUP_CREATED userId=%d rev=%d reason=%s", userId, revision, tostring(reason))
			)
			return true
		end
		if isApiServicesError(err) and RunService:IsStudio() then
			enableStudioLocalMode(tostring(err))
			return true
		end
		Log.Write(
			"Data",
			string.format("PROFILE_BACKUP_RETRY userId=%d attempt=%d err=%s", userId, attempt, tostring(err)),
			"WARN"
		)
		task.wait(retryDelay(attempt))
	end
	Log.Write("Data", string.format("PROFILE_BACKUP_FAILED userId=%d reason=%s", userId, tostring(reason)), "ERROR")
	return false
end

local function saveProfileInternal(player: Player, reason: string?, releaseSession: boolean?): (boolean, string?)
	local userId = player.UserId
	local state = saveStates[userId]
	local profile = profiles[userId]
	if not state or not profile then
		return false, "Profile is not loaded"
	end

	local valid, verr = validateProfileNumbers(profile)
	if not valid then
		Log.Write("Data", string.format("PROFILE_SAVE_FAILED userId=%d invalid=%s", userId, tostring(verr)), "ERROR")
		return false, verr
	end

	local snapshot = Util.DeepCopy(profile)
	local snapshotRevision = state.Revision
	local shouldRelease = releaseSession == true or state.ReleaseRequested == true

	Log.Write(
		"Data",
		string.format(
			"PROFILE_SAVE_START userId=%d reason=%s rev=%d release=%s mode=%s",
			userId,
			tostring(reason),
			snapshotRevision,
			tostring(shouldRelease),
			if studioLocalMode then "StudioLocal" else "DataStore"
		)
	)

	if studioLocalMode then
		local ok, err = studioHttpSave(userId, snapshot, shouldRelease)
		if not ok then
			Log.Write("Data", string.format("PROFILE_SAVE_FAILED userId=%d err=%s", userId, tostring(err)), "ERROR")
			return false, err
		end
		state.LastSavedRevision = snapshotRevision
		if state.Revision == snapshotRevision then
			state.Dirty = false
		else
			state.Dirty = true
		end
		if shouldRelease then
			state.SessionReleased = true
			Log.Write("Data", string.format("PROFILE_LOCK_RELEASED userId=%d (studioLocal)", userId))
		end
		Log.Write("Data", string.format("PROFILE_SAVE_SUCCESS userId=%d rev=%d (studioLocal)", userId, snapshotRevision))
		return true, nil
	end

	local ds = getStore()
	if not ds then
		if RunService:IsStudio() then
			enableStudioLocalMode("DataStore missing on save")
			return saveProfileInternal(player, reason, releaseSession)
		end
		return false, "DataStore unavailable"
	end

	local now = os.time()
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
			if shouldRelease then
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
		if RunService:IsStudio() and isApiServicesError(result) then
			enableStudioLocalMode(tostring(result))
			return saveProfileInternal(player, reason, releaseSession)
		end
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
	if shouldRelease then
		state.SessionReleased = true
		Log.Write("Data", string.format("PROFILE_LOCK_RELEASED userId=%d", userId))
	end

	Log.Write("Data", string.format("PROFILE_SAVE_SUCCESS userId=%d rev=%d", userId, snapshotRevision))
	return true, nil
end

local function heartbeatInternal(userId: number): (boolean, string?)
	if studioLocalMode then
		return true, nil
	end
	local ds = getStore()
	if not ds then
		return false, "DataStore unavailable"
	end
	local lostOwnership = false
	local ok, result = pcall(function()
		return ds:UpdateAsync(tostring(userId), function(current)
			local envelope = normalizeEnvelope(current, userId)
			if envelope.Meta.SessionId ~= SESSION_ID then
				lostOwnership = true
				return nil
			end
			envelope.Meta.LastHeartbeatAt = os.time()
			return envelope
		end)
	end)
	if not ok then
		if RunService:IsStudio() and isApiServicesError(result) then
			enableStudioLocalMode(tostring(result))
			return true, nil
		end
		return false, tostring(result)
	end
	if result == nil then
		return false, if lostOwnership then "Lost session ownership" else "Heartbeat nil"
	end
	return true, nil
end

--[[
	Единый цикл операций DataStore для игрока.
	alreadyHolding = true, если вызывающий уже выставил SaveInProgress.
]]
local function runCoordinatorCycle(player: Player, reason: string?, preferRelease: boolean?, alreadyHolding: boolean?): (boolean, string?)
	local userId = player.UserId
	local state = saveStates[userId]
	if not state or not profiles[userId] then
		if alreadyHolding and state then
			state.SaveInProgress = false
		end
		return false, "Profile is not loaded"
	end

	if not alreadyHolding then
		if state.SaveInProgress then
			-- Не форсируем SaveRequested на чистом heartbeat-конфликте
			if state.Dirty or preferRelease or state.ReleaseRequested or state.Closing then
				state.SaveRequested = true
			end
			return false, "Save in progress"
		end
		state.SaveInProgress = true
	end

	local lastErr: string? = nil
	local overallOk = false
	local budgetDeadline = os.clock() + SAVE_TIME_BUDGET

	local function finish(ok: boolean, err: string?)
		state.SaveInProgress = false
		return ok, err
	end

	-- Если dirty или release — сохраняем; иначе heartbeat
	local needDataSave = state.Dirty or state.SaveRequested or preferRelease or state.ReleaseRequested or state.Closing
	state.SaveRequested = false

	if needDataSave then
		local attempt = 0
		while attempt < MAX_SAVE_RETRIES and os.clock() < budgetDeadline do
			attempt += 1
			local release = preferRelease == true or state.ReleaseRequested == true or state.Closing == true
			local ok, err = saveProfileInternal(player, reason or "queue", release)
			if ok then
				state.FailedSaveCount = 0
				state.LastSaveError = nil
				state.NextRetryAt = 0
				overallOk = true
				lastErr = nil
				pcall(function()
					local LB = require(script.Parent.LeaderboardService)
					if LB and LB.PushPlayer and player.Parent and not state.SessionReleased then
						LB.PushPlayer(player)
					end
				end)
				break
			end
			lastErr = err
			Log.Write(
				"Data",
				string.format("PROFILE_SAVE_RETRY userId=%d attempt=%d err=%s", userId, attempt, tostring(err)),
				"WARN"
			)
			if err == "Lost session ownership" then
				handleOwnershipLost(userId, player)
				return finish(false, err)
			end
			if os.clock() >= budgetDeadline then
				break
			end
			task.wait(retryDelay(attempt))
		end

		if not overallOk then
			state.FailedSaveCount += 1
			state.LastSaveError = lastErr
			state.NextRetryAt = os.clock() + math.min(60, retryDelay(math.max(3, state.FailedSaveCount)))
			-- Немедленный follow-up запрещён — только autosave / Flush после cooldown
			return finish(false, lastErr or "Save failed")
		end

		-- Успех: если снова dirty (изменения во время save) — ещё один проход без рекурсии task.spawn
		if state.Dirty and not state.SessionReleased and os.clock() < budgetDeadline then
			state.SaveRequested = false
			local ok2, err2 = saveProfileInternal(
				player,
				"followup",
				preferRelease == true or state.ReleaseRequested == true or state.Closing == true
			)
			if ok2 then
				if state.Revision == state.LastSavedRevision then
					state.Dirty = false
				end
			else
				state.Dirty = true
				state.FailedSaveCount += 1
				state.LastSaveError = err2
				state.NextRetryAt = os.clock() + math.min(60, retryDelay(3))
				if err2 == "Lost session ownership" then
					handleOwnershipLost(userId, player)
				end
				return finish(false, err2)
			end
		end

		return finish(true, nil)
	end

	-- Heartbeat-only
	local hbOk, hbErr = heartbeatInternal(userId)
	if hbOk then
		Log.Write("Data", string.format("PROFILE_HEARTBEAT_SUCCESS userId=%d", userId))
		return finish(true, nil)
	end
	Log.Write("Data", string.format("PROFILE_HEARTBEAT_FAILED userId=%d err=%s", userId, tostring(hbErr)), "WARN")
	if hbErr == "Lost session ownership" then
		handleOwnershipLost(userId, player)
	end
	return finish(false, hbErr)
end

local function enqueueSave(player: Player, reason: string?)
	local userId = player.UserId
	local state = saveStates[userId]
	if not state or not profiles[userId] then
		return
	end
	if state.SessionReleased then
		return
	end
	state.SaveRequested = true
	if state.SaveInProgress then
		return
	end
	if not state.Closing and os.clock() < (state.NextRetryAt or 0) then
		return
	end
	task.spawn(function()
		local st = saveStates[userId]
		if not st or st.SaveInProgress or not profiles[userId] then
			return
		end
		if not st.Closing and os.clock() < (st.NextRetryAt or 0) then
			return
		end
		runCoordinatorCycle(player, reason or "enqueue", false, false)
	end)
end

-- ─── Public API ─────────────────────────────────────────────────────

function DataService.IsProfileLoaded(player: Player): boolean
	local state = saveStates[player.UserId]
	return profiles[player.UserId] ~= nil
		and player:GetAttribute("BD_ProfileReady") == true
		and state ~= nil
		and not state.SessionReleased
end

function DataService.CanMutateProfile(player: Player): boolean
	local state = saveStates[player.UserId]
	return DataService.IsProfileLoaded(player)
		and state ~= nil
		and not state.Closing
		and not state.TransferPending
		and not state.SessionReleased
end

function DataService.GetProfileStatus(player: Player)
	local state = saveStates[player.UserId]
	return {
		Loaded = profiles[player.UserId] ~= nil,
		Dirty = state and state.Dirty or false,
		Revision = state and state.Revision or 0,
		LastSavedRevision = state and state.LastSavedRevision or 0,
		SaveInProgress = state and state.SaveInProgress or false,
		TransferPending = state and state.TransferPending or false,
		FailedSaveCount = state and state.FailedSaveCount or 0,
		LastSaveError = state and state.LastSaveError or nil,
		SessionId = SESSION_ID,
	}
end

function DataService.GetProfile(player: Player)
	return profiles[player.UserId]
end

function DataService.MarkDirty(player: Player, _reason: string?)
	local state = saveStates[player.UserId]
	if not state or state.SessionReleased then
		return
	end
	state.Revision += 1
	state.Dirty = true
end

--- Откат in-memory профиля к snapshot после неудачного Flush (datastore без изменений).
function DataService.RestoreSnapshot(player: Player, snapshot)
	local userId = player.UserId
	local state = saveStates[userId]
	if type(snapshot) ~= "table" or not state then
		return
	end
	profiles[userId] = Util.DeepCopy(snapshot)
	state.Revision = state.LastSavedRevision
	state.Dirty = false
	DataService.NotifyProfile(player)
end

function DataService.NotifyProfile(player: Player)
	local profile = profiles[player.UserId]
	if not profile then
		return
	end
	local state = saveStates[player.UserId]
	local ready = state ~= nil and not state.SessionReleased and not state.TransferPending
	syncPlayerAttrs(player, profile, ready)
	if RemoteService and ready then
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
	Очередь (не ждёт). immediate=true — без debounce.
	Сигнатуры: SaveProfile(player, immediate?, forceOrReason?, reason?)
]]
function DataService.SaveProfile(player: Player, immediate: boolean?, force: any?, reason: any?)
	local userId = player.UserId
	if not profiles[userId] or not saveStates[userId] then
		return
	end
	if typeof(force) == "string" and reason == nil then
		reason = force
		force = true
	end
	local reasonStr = if typeof(reason) == "string" then reason else nil
	local skipDebounce = immediate == true or force == true

	if not skipDebounce then
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
			if profiles[userId] and st and st.Dirty and not st.SessionReleased then
				enqueueSave(player, reasonStr or "debounce")
			end
		end)
		return
	end

	enqueueSave(player, reasonStr or "immediate")
end

--[[
	Дождаться фактического UpdateAsync. releaseSession снимает lock только при успехе.
]]
function DataService.FlushProfile(player: Player, reason: string?, releaseSession: boolean?): (boolean, string?)
	local userId = player.UserId
	local state = saveStates[userId]
	if not state or not profiles[userId] then
		return false, "Profile is not loaded"
	end
	if state.SessionReleased and releaseSession then
		return true, nil
	end

	state.Dirty = true
	state.SaveRequested = true
	if releaseSession then
		state.Closing = true
		state.ReleaseRequested = true
	end

	local deadline = os.clock() + FLUSH_TIMEOUT
	local lastErr: string? = nil

	while os.clock() < deadline do
		if state.SaveInProgress then
			task.wait(0.05)
			continue
		end

		if state.SessionReleased then
			return true, nil
		end

		local need = state.Dirty or state.SaveRequested or (releaseSession == true and not state.SessionReleased)
		if not need then
			return true, nil
		end

		state.SaveInProgress = true
		local ok, err = runCoordinatorCycle(player, reason or "Flush", releaseSession == true, true)
		if ok then
			if releaseSession then
				if state.SessionReleased then
					return true, nil
				end
			elseif not state.Dirty then
				return true, nil
			end
			-- dirty again — ещё круг до дедлайна
		else
			lastErr = err
			if err == "Lost session ownership" then
				return false, err
			end
			if releaseSession then
				task.wait(0.2)
			else
				return false, err or "Flush failed"
			end
		end
	end

	return false, lastErr or "Flush timed out"
end

function DataService.FlushAndReleaseProfile(player: Player, reason: string?): (boolean, string?)
	local userId = player.UserId
	local state = saveStates[userId]
	if not state or not profiles[userId] then
		return false, "Profile is not loaded"
	end
	state.TransferPending = true
	syncPlayerAttrs(player, profiles[userId], false)
	local ok, err = DataService.FlushProfile(player, reason or "Transfer", true)
	if not ok then
		state.TransferPending = false
		state.ReleaseRequested = false
		-- Closing мог остаться — сбрасываем, если телепорт отменён на этом сервере
		if not state.Closing or reason == "Teleport" then
			state.Closing = false
		end
		if player.Parent and profiles[userId] then
			syncPlayerAttrs(player, profiles[userId], true)
		end
		return false, err
	end
	return true, nil
end

function DataService.ReacquireProfile(player: Player): (boolean, string?)
	local userId = player.UserId
	syncPlayerAttrs(player, nil, false)
	profiles[userId] = nil
	saveStates[userId] = nil

	if studioLocalMode or (RunService:IsStudio() and not probeDataStoreAvailable()) then
		enableStudioLocalMode("reacquire")
		local raw = studioHttpLoad(userId) or loadFromStudioModule(userId)
		local profile = materializeProfile(raw, raw)
		profiles[userId] = profile
		saveStates[userId] = newSaveState(1)
		loadDone[userId] = true
		syncPlayerAttrs(player, profile, true)
		DataService.NotifyProfile(player)
		return true, nil
	end

	local acquired, envelope, err
	for attempt = 1, math.min(4, MAX_LOAD_RETRIES) do
		acquired, envelope, err = tryAcquireSession(userId)
		if acquired and type(envelope) == "table" then
			break
		end
		if RunService:IsStudio() and isApiServicesError(err) then
			enableStudioLocalMode(tostring(err))
			return DataService.ReacquireProfile(player)
		end
		task.wait(LOAD_DELAYS[attempt] or 4)
		if not player.Parent then
			return false, "Player left"
		end
	end
	if not acquired or type(envelope) ~= "table" then
		return false, err or "Reacquire failed"
	end

	local profile = materializeProfile(envelope.Data, envelope.Data)
	local metaRev = tonumber(envelope.Meta and envelope.Meta.Revision) or 0
	profiles[userId] = profile
	saveStates[userId] = newSaveState(metaRev)
	loadDone[userId] = true
	syncPlayerAttrs(player, profile, true)
	Log.Write("Data", string.format("PROFILE_LOCK_ACQUIRED userId=%d (reacquire)", userId))
	DataService.NotifyProfile(player)
	return true, nil
end

function DataService.ReleaseProfile(player: Player)
	DataService.FlushProfile(player, "ReleaseProfile", true)
end

function DataService.ResetProfile(player: Player): (any, string?)
	local userId = player.UserId
	local state = saveStates[userId]
	local existing = profiles[userId]
	if not existing or not state then
		return nil, "Profile is not loaded"
	end
	if not DataService.CanMutateProfile(player) then
		return nil, "Profile is locked for transfer"
	end

	local backupOk = createBackup(userId, existing, state.Revision, "ResetProfile")
	if not backupOk then
		return nil, "Не удалось создать резервную копию профиля"
	end

	local fresh = Util.DeepCopy(ProfileTemplate)
	fresh.Level = Util.LevelFromTotalXP(0, GameConfig.XPPerLevel, GameConfig.XPPerLevelGrowth)
	profiles[userId] = fresh
	state.Revision += 1
	state.Dirty = true
	syncPlayerAttrs(player, fresh, true)
	DataService.NotifyProfile(player)

	local ok, err = DataService.FlushProfile(player, "ResetProfile", false)
	if not ok then
		profiles[userId] = existing
		state.Revision = state.LastSavedRevision
		state.Dirty = false
		DataService.NotifyProfile(player)
		return nil, err or "Не удалось сохранить сброс профиля"
	end

	Log.Write("Data", player.Name .. " profile reset")
	return fresh, nil
end

function DataService.AddGold(player: Player, amount: number, reason: string?)
	local profile = profiles[player.UserId]
	if not profile or not DataService.CanMutateProfile(player) then
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
	if not profile or not DataService.CanMutateProfile(player) then
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

	local function loadStudioLocal(): boolean
		enableStudioLocalMode("load fallback")
		local raw = studioHttpLoad(userId) or loadFromStudioModule(userId)
		local profile = materializeProfile(raw, raw)
		profiles[userId] = profile
		saveStates[userId] = newSaveState(1)
		if raw == nil then
			saveStates[userId].Dirty = true
		end
		loadDone[userId] = true
		syncPlayerAttrs(player, profile, true)
		Log.Write(
			"Data",
			string.format(
				"PROFILE_LOAD_SUCCESS (studioLocal) userId=%d Gold=%s TotalXP=%s source=%s",
				userId,
				tostring(profile.Gold),
				tostring(profile.TotalXP),
				if raw then "local" else "template"
			)
		)
		-- Сразу пробуем записать в LogServer, чтобы следующий Play видел профиль
		task.spawn(function()
			studioHttpSave(userId, profile, true)
		end)
		return true
	end

	-- Studio: без API Services или с явным legacy-флагом — сразу локальный режим
	if RunService:IsStudio() then
		local dsOk = probeDataStoreAvailable()
		if not dsOk or ALLOW_LEGACY or studioLocalMode then
			return loadStudioLocal()
		end
	end

	local ds = getStore()
	if not ds then
		if RunService:IsStudio() then
			return loadStudioLocal()
		end
		Log.Write("Data", "PROFILE_LOAD_FAILED userId=" .. userId .. " no DataStore", "ERROR")
		loadDone[userId] = true
		syncPlayerAttrs(player, nil, false)
		player:Kick("Не удалось загрузить профиль (DataStore). Переподключитесь позже.")
		return false
	end

	local acquired, envelope, err
	for attempt = 1, MAX_LOAD_RETRIES do
		acquired, envelope, err = tryAcquireSession(userId)
		if acquired and type(envelope) == "table" then
			break
		end
		if RunService:IsStudio() and isApiServicesError(err) then
			return loadStudioLocal()
		end
		Log.Write(
			"Data",
			string.format("PROFILE_LOAD_RETRY userId=%d attempt=%d err=%s", userId, attempt, tostring(err)),
			"WARN"
		)
		-- В Studio при ошибке lock/API не тянем полный backoff на минуты
		local delaySec = if RunService:IsStudio() then math.min(LOAD_DELAYS[attempt] or 2, 3) else (LOAD_DELAYS[attempt] or (10 + attempt))
		task.wait(delaySec)
		if not player.Parent then
			loadDone[userId] = true
			return false
		end
	end

	if not acquired or type(envelope) ~= "table" then
		if RunService:IsStudio() then
			Log.Write("Data", "PROFILE_LOAD DataStore failed in Studio, falling back to local", "WARN")
			return loadStudioLocal()
		end
		Log.Write("Data", string.format("PROFILE_LOAD_FAILED userId=%d err=%s", userId, tostring(err)), "ERROR")
		loadDone[userId] = true
		syncPlayerAttrs(player, nil, false)
		player:Kick("Не удалось загрузить профиль. Пожалуйста, переподключитесь.")
		return false
	end

	Log.Write(
		"Data",
		string.format("PROFILE_LOCK_ACQUIRED userId=%d rev=%s", userId, tostring(envelope.Meta and envelope.Meta.Revision))
	)

	local profile = materializeProfile(envelope.Data, envelope.Data)
	local metaRev = tonumber(envelope.Meta and envelope.Meta.Revision) or 0
	profiles[userId] = profile
	saveStates[userId] = newSaveState(metaRev)
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
			if DataService.IsProfileLoaded(player) then
				DataService.NotifyProfile(player)
			end
		end
	end)
end

function DataService:Init(services)
	RemoteService = services.RemoteService

	if RunService:IsStudio() and not probeDataStoreAvailable() then
		enableStudioLocalMode("Init probe failed")
	end

	Log.Write(
		"Data",
		string.format(
			"Profile DB = %s sess=%s studioLocal=%s",
			if studioLocalMode then "StudioLocal(LogServer:8765)" else ("DataStore(" .. tostring((dsCfg().PlayerProfile)) .. ")"),
			shortSession(SESSION_ID),
			tostring(studioLocalMode)
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
			local profile, err = DataService.ResetProfile(player)
			if not profile then
				return { success = false, error = err or "Сброс недоступен" }
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
		if profiles[userId] and state and not state.SessionReleased then
			state.Closing = true
			state.SaveRequested = true
			state.Dirty = true
			local ok, err = DataService.FlushProfile(player, "PlayerRemoving", true)
			if not ok then
				Log.Write(
					"Data",
					string.format("PROFILE_SAVE_FAILED userId=%d PlayerRemoving err=%s (lock kept)", userId, tostring(err)),
					"ERROR"
				)
			end
		end
		profiles[userId] = nil
		saveStates[userId] = nil
		loadDone[userId] = nil
	end)

	game:BindToClose(function()
		local list = Players:GetPlayers()
		local remaining = #list
		local started = os.clock()
		for _, player in ipairs(list) do
			task.spawn(function()
				local userId = player.UserId
				local state = saveStates[userId]
				if state and profiles[userId] and not state.SessionReleased then
					state.Closing = true
					state.SaveRequested = true
					state.Dirty = true
					-- Не начинаем новые попытки после общего дедлайна
					if os.clock() - started < BIND_CLOSE_TIMEOUT then
						DataService.FlushProfile(player, "BindToClose", true)
					end
				end
				remaining -= 1
			end)
		end
		local deadline = os.clock() + BIND_CLOSE_TIMEOUT
		while remaining > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(AUTO_SAVE_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				local state = saveStates[player.UserId]
				if
					state
					and state.Dirty
					and not state.Closing
					and not state.TransferPending
					and not state.SessionReleased
					and not state.SaveInProgress
					and os.clock() >= (state.NextRetryAt or 0)
				then
					enqueueSave(player, "AutoSave")
				end
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(SESSION_HEARTBEAT_INTERVAL)
			for userId, state in pairs(saveStates) do
				if state.Closing or state.TransferPending or state.SessionReleased then
					continue
				end
				if state.SaveInProgress then
					continue
				end
				local player = Players:GetPlayerByUserId(userId)
				if not player or not profiles[userId] then
					continue
				end
				-- Через тот же coordinator (SaveInProgress)
				runCoordinatorCycle(player, if state.Dirty then "HeartbeatDirty" else "Heartbeat", false, false)
			end
		end
	end)
end

return DataService
