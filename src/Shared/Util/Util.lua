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

return Util
