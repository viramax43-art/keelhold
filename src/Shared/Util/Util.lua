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

function Util.LevelFromTotalXP(totalXP: number, xpPerLevel: number): number
	xpPerLevel = math.max(1, xpPerLevel or 100)
	return math.max(1, math.floor((totalXP or 0) / xpPerLevel) + 1)
end

return Util
