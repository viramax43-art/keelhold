--[[
	DamageFormula — процентная броня (макс. 70% снижения).
]]

local DamageFormula = {}

function DamageFormula.Mitigate(rawDamage: number, armor: number?): number
	if not armor or armor <= 0 then
		return math.max(1, math.floor(rawDamage))
	end
	local reduction = math.clamp(armor * 0.01, 0, 0.70)
	return math.max(1, math.floor(rawDamage * (1 - reduction)))
end

return DamageFormula
