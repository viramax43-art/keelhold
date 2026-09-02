local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local CoopMultiplier = {}

function CoopMultiplier.Compute(friendCount: number): number
	local cfg = GameConfig.CoopMultiplier
	friendCount = math.clamp(friendCount or 0, 0, cfg.MaxFriends or 3)
	if friendCount <= 0 then
		return cfg.Solo or 1
	end
	local m = (cfg.Base or 1.1) + (cfg.PerFriend or 0.1) * friendCount
	return math.min(m, cfg.MaxMultiplier or 1.4)
end

return CoopMultiplier
