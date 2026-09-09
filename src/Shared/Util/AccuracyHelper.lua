--[[
	AccuracyHelper — итоговая точность выстрела.

	итоговая =
	  базовая_точность
	- штраф_за_дистанцию (растёт с разбросом)
	- штраф_за_движение
	+ бонусы / AccuracyMod цели-стрелка

	Range (MaxRange) — может ли выстрел вообще долететь.
	Spread — насколько сильно падает точность с дистанцией (не то же самое, что Range).
]]

local AccuracyHelper = {}

export type ShotOpts = {
	baseAccuracy: number?,
	distance: number?,
	maxRange: number?,
	spread: number?, -- 0..1, выше = хуже на дистанции
	movingShooter: boolean?,
	movingTarget: boolean?,
	entityMod: number?,
	bonus: number?,
}

function AccuracyHelper.ComputeBaseAccuracy(weaponAcc: number, upgradeAcc: number): number
	return math.clamp((weaponAcc or 0.75) * 0.55 + (upgradeAcc or 0.75) * 0.45, 0.35, 0.95)
end

function AccuracyHelper.ComputeShotChance(opts: ShotOpts): number
	local distance = math.max(0, opts.distance or 0)
	local maxRange = math.max(1, opts.maxRange or 100)
	if distance > maxRange then
		return 0
	end

	local base = math.clamp(opts.baseAccuracy or 0.75, 0.05, 0.99)
	local spread = math.clamp(opts.spread or 0.2, 0, 1)
	local t = distance / maxRange
	-- Квадратичный штраф: вблизи почти без потерь, вдали сильно зависит от Spread
	local distPenalty = (t * t) * (0.18 + spread * 0.55)
	local movePenalty = 0
	if opts.movingShooter then
		movePenalty += 0.1
	end
	if opts.movingTarget then
		movePenalty += 0.07
	end
	local chance = base - distPenalty - movePenalty + (opts.bonus or 0) + (opts.entityMod or 0)
	return math.clamp(chance, 0.05, 0.96)
end

function AccuracyHelper.RollShot(opts: ShotOpts): (boolean, number)
	local chance = AccuracyHelper.ComputeShotChance(opts)
	return math.random() <= chance, chance
end

-- Совместимость: простой ролл без дистанции
function AccuracyHelper.RollHit(accuracy: number): boolean
	return math.random() <= math.clamp(accuracy or 0.75, 0.05, 0.95)
end

return AccuracyHelper
