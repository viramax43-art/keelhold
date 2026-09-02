local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local AdminConfig = require(ReplicatedStorage.Shared.Config.AdminConfig)
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)

local PromocodeService = {}
local codes = {} -- code -> { Type, Amount, Multiplier, Duration }
local store = nil

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

	-- Studio defaults
	if next(codes) == nil then
		codes["BRIDGE100"] = { Type = "Gold", Amount = 100 }
		codes["XP50"] = { Type = "XP", Amount = 50 }
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
			if not profile then
				return { success = false }
			end
			if profile.UsedPromocodes[code] then
				return { success = false, error = "Already used" }
			end
			profile.UsedPromocodes[code] = os.time()
			if def.Type == "Gold" then
				DataService.AddGold(player, def.Amount or 0, "promo")
			elseif def.Type == "XP" then
				DataService.AddXP(player, def.Amount or 0, "promo")
			end
			DataService.SaveProfile(player, true)
			return { success = true }
		end
	end

	function PromocodeService.SetCode(code, def)
		codes[string.upper(code)] = def
		local s = getStore()
		if s then
			pcall(function()
				s:SetAsync("All", codes)
			end)
		end
	end

	if RunService:IsServer() then
		game:BindToClose(function()
			local s = getStore()
			if s then
				pcall(function()
					s:SetAsync("All", codes)
				end)
			end
		end)
	end
end

return PromocodeService
