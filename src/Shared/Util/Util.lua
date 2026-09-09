--[[
	Util — общие хелперы.
]]

local Util = {}

function Util.DeepCopy(t)
	if type(t) ~= "table" then
		return t
	end
	local copy = {}
	for k, v in pairs(t) do
		copy[k] = Util.DeepCopy(v)
	end
	return copy
end

function Util.ReconcileProfile(profile, template)
	if type(profile) ~= "table" then
		return Util.DeepCopy(template)
	end
	local result = Util.DeepCopy(template)
	local function merge(dst, src)
		for k, v in pairs(src) do
			if type(v) == "table" and type(dst[k]) == "table" then
				merge(dst[k], v)
			else
				dst[k] = Util.DeepCopy(v)
			end
		end
	end
	merge(result, profile)
	return result
end

function Util.XPForLevel(level: number, baseXP: number?, growth: number?): number
	baseXP = math.max(1, baseXP or 150)
	growth = growth or 1.15
	level = math.max(1, level)
	return math.floor(baseXP * (growth ^ (level - 1)))
end

function Util.LevelFromTotalXP(totalXP: number, xpPerLevel: number?, growth: number?): number
	totalXP = totalXP or 0
	xpPerLevel = math.max(1, xpPerLevel or 150)
	growth = growth or 1.15
	local level = 1
	local remaining = totalXP
	-- Cap iterations to avoid infinite loop
	for _ = 1, 500 do
		local need = Util.XPForLevel(level, xpPerLevel, growth)
		if remaining < need then
			break
		end
		remaining -= need
		level += 1
	end
	return level
end

function Util.XPProgressInLevel(totalXP: number, xpPerLevel: number?, growth: number?): (number, number, number)
	totalXP = totalXP or 0
	xpPerLevel = math.max(1, xpPerLevel or 150)
	growth = growth or 1.15
	local level = 1
	local remaining = totalXP
	for _ = 1, 500 do
		local need = Util.XPForLevel(level, xpPerLevel, growth)
		if remaining < need then
			return level, remaining, need
		end
		remaining -= need
		level += 1
	end
	local need = Util.XPForLevel(level, xpPerLevel, growth)
	return level, 0, need
end

-- JSON (HttpService/DataStore) превращает {[1]=4} в массив и ключи "1"/"2".
-- Нормализуем обратно в number-keyed maps после любой загрузки из БД.
function Util.NormalizeProfileMaps(profile)
	if type(profile) ~= "table" then
		return profile
	end

	local function toNumMap(src)
		local out = {}
		if type(src) ~= "table" then
			return out
		end
		for k, v in pairs(src) do
			local nk = tonumber(k)
			if nk ~= nil then
				if type(v) == "number" then
					out[nk] = v
				else
					out[nk] = tonumber(v) or 0
				end
			end
		end
		return out
	end

	local wc = {}
	for wType, tiers in pairs(profile.WeaponCopies or {}) do
		if type(wType) == "string" and type(tiers) == "table" then
			wc[wType] = toNumMap(tiers)
		end
	end
	profile.WeaponCopies = wc
	profile.ArmorCopies = toNumMap(profile.ArmorCopies or {})

	local sa = toNumMap(profile.SquadArmor or {})
	for i = 1, 4 do
		if sa[i] == nil then
			sa[i] = 0
		end
	end
	profile.SquadArmor = sa

	local loadout = {}
	for k, v in pairs(profile.SquadLoadout or {}) do
		local slot = tonumber(k)
		if slot and type(v) == "table" then
			loadout[slot] = {
				WeaponType = tostring(v.WeaponType or "Pistol"),
				Tier = tonumber(v.Tier) or 1,
			}
		end
	end
	for i = 1, 4 do
		if not loadout[i] then
			loadout[i] = { WeaponType = "Pistol", Tier = 1 }
		end
	end
	profile.SquadLoadout = loadout

	profile.Gold = tonumber(profile.Gold) or 0
	profile.XP = tonumber(profile.XP) or 0
	profile.TotalXP = tonumber(profile.TotalXP) or 0
	profile.Level = tonumber(profile.Level) or 1
	profile.HighestWave = tonumber(profile.HighestWave) or 0
	profile.LastCheckpoint = tonumber(profile.LastCheckpoint) or 0
	profile.PrestigePoints = tonumber(profile.PrestigePoints) or 0
	profile.Ascensions = tonumber(profile.Ascensions) or 0
	profile.OwnedArmorTier = tonumber(profile.OwnedArmorTier) or 0
	profile.EquippedArmorTier = tonumber(profile.EquippedArmorTier) or 0

	local owned = {}
	for wType, tier in pairs(profile.OwnedWeapons or {}) do
		if type(wType) == "string" then
			owned[wType] = tonumber(tier) or 0
		end
	end
	profile.OwnedWeapons = owned

	local upgrades = {}
	for name, lvl in pairs(profile.Upgrades or {}) do
		if type(name) == "string" then
			upgrades[name] = tonumber(lvl) or 0
		end
	end
	profile.Upgrades = upgrades

	return profile
end

-- Перед JSONEncode: числовые ключи → строки, чтобы не схлопывалось в JSON-массив
function Util.PrepareProfileForStorage(profile)
	local p = Util.DeepCopy(profile)
	Util.NormalizeProfileMaps(p)
	local wc = {}
	for wType, tiers in pairs(p.WeaponCopies or {}) do
		local tmap = {}
		for tier, count in pairs(tiers) do
			tmap[tostring(tier)] = count
		end
		wc[wType] = tmap
	end
	p.WeaponCopies = wc
	local ac = {}
	for tier, count in pairs(p.ArmorCopies or {}) do
		ac[tostring(tier)] = count
	end
	p.ArmorCopies = ac
	local sa = {}
	for slot, tier in pairs(p.SquadArmor or {}) do
		sa[tostring(slot)] = tier
	end
	p.SquadArmor = sa
	local sl = {}
	for slot, load in pairs(p.SquadLoadout or {}) do
		sl[tostring(slot)] = load
	end
	p.SquadLoadout = sl
	return p
end

return Util
