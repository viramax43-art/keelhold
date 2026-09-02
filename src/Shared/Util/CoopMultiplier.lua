local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local CoopMultiplier = {}

function CoopMultiplier.Compute(friendCount: number): number
	local cfg = GameConfig.CoopMultiplier
	friendCount = math.clamp(math.floor(friendCount or 0), 0, 3)
	if friendCount <= 0 then
		return cfg.Solo or 1
	end
	local value = cfg[friendCount]
	if typeof(value) == "number" then
		return value
	end
	return cfg.Solo or 1
end

return CoopMultiplier
