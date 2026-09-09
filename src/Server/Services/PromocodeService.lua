local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local AdminConfig = require(ReplicatedStorage.Shared.Config.AdminConfig)
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)
local Util = require(ReplicatedStorage.Shared.Util.Util)

local PromocodeService = {}
local codes = {} -- code -> { Type, Amount, Multiplier, Duration }
local store = nil

local DEFAULT_CODES = {
	BRIDGE100 = { Type = "Gold", Amount = 100 },
	XP50 = { Type = "XP", Amount = 50 },
}

local function getStore()
	if store ~= nil then
		return store
	end
	local ok, s = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.DataStore.Promocodes)
	end)
	store = ok and s or false
	return store
end

local function persistCodes()
	local s = getStore()
	if not s then
		return false
	end
	local snapshot = codes
	local ok = pcall(function()
		s:UpdateAsync("All", function(current)
			local merged = if type(current) == "table" then current else {}
			for code, def in pairs(snapshot) do
				merged[code] = def
			end
			return merged
		end)
	end)
	return ok
end

function PromocodeService:Init(services)
	local DataService = services.DataService
	local RemoteService = services.RemoteService

	local ds = getStore()
	if ds then
		pcall(function()
			local data = ds:GetAsync("All")
			if type(data) == "table" then
				codes = data
			end
		end)
	end

	if next(codes) == nil then
		for code, def in pairs(DEFAULT_CODES) do
			codes[code] = def
		end
	end

	local redeem = RemoteService.GetRemote(RemoteNames.RedeemPromocode)
	if redeem then
		redeem.OnServerInvoke = function(player, code)
			code = string.upper(tostring(code or ""):sub(1, AdminConfig.PromocodeMaxLength or 32))
			local def = codes[code]
			if not def then
				return { success = false, error = "Invalid code" }
			end
			local profile = DataService.GetProfile(player)
			if not profile or not DataService.CanMutateProfile(player) then
				return { success = false }
			end
			if profile.UsedPromocodes[code] then
				return { success = false, error = "Already used" }
			end
			local before = Util.DeepCopy(profile)
			profile.UsedPromocodes[code] = os.time()
			if def.Type == "Gold" then
				profile.Gold = (profile.Gold or 0) + (def.Amount or 0)
			elseif def.Type == "XP" then
				profile.XP = (profile.XP or 0) + (def.Amount or 0)
				profile.TotalXP = (profile.TotalXP or 0) + (def.Amount or 0)
				profile.Level = Util.LevelFromTotalXP(
					profile.TotalXP,
					GameConfig.XPPerLevel,
					GameConfig.XPPerLevelGrowth
				)
			end
			DataService.MarkDirty(player, "Promocode")
			DataService.NotifyProfile(player)
			local ok, err = DataService.FlushProfile(player, "Promocode", false)
			if not ok then
				DataService.RestoreSnapshot(player, before)
				return { success = false, error = err or "Не удалось сохранить профиль" }
			end
			return { success = true }
		end
	end

	function PromocodeService.SetCode(code, def)
		if type(code) ~= "string" or type(def) ~= "table" then
			return false
		end
		local normalized = string.upper(code:sub(1, AdminConfig.PromocodeMaxLength or 32))
		if normalized == "" or (def.Type ~= "Gold" and def.Type ~= "XP") then
			return false
		end
		codes[normalized] = {
			Type = def.Type,
			Amount = math.clamp(math.floor(tonumber(def.Amount) or 0), 0, 1000000),
		}
		return persistCodes()
	end

	if RunService:IsServer() then
		game:BindToClose(function()
			persistCodes()
		end)
	end
end

return PromocodeService
