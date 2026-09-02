local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local CombatRange = {}

function CombatRange.GetDefenseEngageRange(weaponRange: number?): number
	local base = (GameConfig.Battle and GameConfig.Battle.DefenseEngageRange) or 320
	if weaponRange and weaponRange > 0 then
		return math.max(base * 0.35, math.min(base, weaponRange * 1.8))
	end
	return base
end

function CombatRange.GetPlayerEngageRange(): number
	return (GameConfig.Battle and GameConfig.Battle.PlayerEngageRange) or 320
end

return CombatRange
