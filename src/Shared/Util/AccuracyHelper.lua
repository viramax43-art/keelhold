local AccuracyHelper = {}

function AccuracyHelper.ComputeBaseAccuracy(weaponAcc: number, upgradeAcc: number): number
	-- Soft cap so misses stay visible in combat VFX
	return math.clamp((weaponAcc or 0.75) * 0.55 + (upgradeAcc or 0.75) * 0.45, 0.35, 0.92)
end

function AccuracyHelper.RollHit(accuracy: number): boolean
	return math.random() <= math.clamp(accuracy or 0.75, 0.05, 0.92)
end

return AccuracyHelper
