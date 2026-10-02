--[[
	AccuracyHelper — итоговая точность выстрела.

	итоговая =
	  (базовая_точность + бонусы) * множитель_профиля_стрелка
	- штраф_за_дистанцию (растёт с разбросом оружия)
	- штраф_за_движение

	Range (maxRange) — может ли выстрел вообще долететь.
	Spread — насколько сильно падает точность с дистанцией.

	Все коэффициенты живут в GameConfig.Battle.HitChance (единая точка тюнинга).
	Профиль стрелка: боты = BotProfileMult (эталон 1.0), враги = EnemyProfileMult (хуже).
	Вблизи точность почти не падает, на пределе дальности — падает почти до нуля.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local AccuracyHelper = {}

-- Дефолты = GameConfig.Battle.HitChance (если блок в конфиге не задан)
local DEFAULTS = {
	Enabled = true,
	BotProfileMult = 1.0,
	EnemyProfileMult = 0.78,
	NearFalloffStart = 0.15,
	FalloffPower = 1.35,
	MaxDistancePenalty = 0.55,
	SpreadBase = 0.55,
	SpreadWeight = 0.85,
	MovingShooterPenalty = 0.10,
	MovingTargetPenalty = 0.07,
	MinChance = 0.05,
	MaxChance = 0.92,
	-- Визуальный разброс трассеров: только горизонталь (вертикаль отключена)
	HorizontalOnlySpread = true,
	VisualSpreadMaxDeg = 5,
	VisualSpreadMinDeg = 0.6,
}

local function tuning()
	local cfg = GameConfig and GameConfig.Battle and GameConfig.Battle.HitChance
	if type(cfg) ~= "table" then
		return DEFAULTS
	end
	return cfg
end

local function num(key: string, fallback: number): number
	local v = tonumber(tuning()[key])
	if v == nil then
		return fallback
	end
	return v
end

export type ShotOpts = {
	baseAccuracy: number?,
	distance: number?,
	maxRange: number?,
	spread: number?, -- 0..1, выше = хуже на дистанции
	movingShooter: boolean?,
	movingTarget: boolean?,
	entityMod: number?,
	bonus: number?,
	-- Множитель профиля стрелка: боты 1.0, враги EnemyProfileMult (< 1).
	-- nil = 1 (нейтральный профиль).
	profileMult: number?,
}

function AccuracyHelper.ComputeBaseAccuracy(weaponAcc: number, upgradeAcc: number): number
	return math.clamp((weaponAcc or 0.75) * 0.55 + (upgradeAcc or 0.75) * 0.45, 0.35, 0.95)
end

-- Профиль стрелка: side = "bot" | "enemy" (иначе нейтральный 1.0)
function AccuracyHelper.GetProfileMult(side: string?): number
	if side == "bot" then
		return math.max(0.1, num("BotProfileMult", DEFAULTS.BotProfileMult))
	elseif side == "enemy" then
		return math.max(0.1, num("EnemyProfileMult", DEFAULTS.EnemyProfileMult))
	end
	return 1
end

-- Штраф за дистанцию: 0 вблизи (до NearFalloffStart от maxRange),
-- дальше растёт по FalloffPower и усиливается разбросом оружия.
function AccuracyHelper.DistancePenalty(distance: number?, maxRange: number?, spread: number?): number
	local range = math.max(1, maxRange or 100)
	local start = math.clamp(num("NearFalloffStart", DEFAULTS.NearFalloffStart), 0, 0.9)
	local t = (math.max(0, distance or 0) / range - start) / math.max(0.05, 1 - start)
	t = math.clamp(t, 0, 1)
	local spreadMult = num("SpreadBase", DEFAULTS.SpreadBase)
		+ math.clamp(spread or 0.2, 0, 1) * num("SpreadWeight", DEFAULTS.SpreadWeight)
	local power = math.max(0.25, num("FalloffPower", DEFAULTS.FalloffPower))
	return math.max(0, num("MaxDistancePenalty", DEFAULTS.MaxDistancePenalty)) * spreadMult * (t ^ power)
end

function AccuracyHelper.ComputeShotChance(opts: ShotOpts): number
	local distance = math.max(0, opts.distance or 0)
	local maxRange = math.max(1, opts.maxRange or 100)
	-- Небольшой запас: дуло/точка прицеливания чуть длиннее дистанции выбора цели
	if distance > maxRange * 1.08 then
		return 0
	end
	distance = math.min(distance, maxRange)

	local base = math.clamp(opts.baseAccuracy or 0.75, 0.05, 0.99)
	local spread = math.clamp(opts.spread or 0.2, 0, 1)
	local movePenalty = 0
	if opts.movingShooter then
		movePenalty += num("MovingShooterPenalty", DEFAULTS.MovingShooterPenalty)
	end
	if opts.movingTarget then
		movePenalty += num("MovingTargetPenalty", DEFAULTS.MovingTargetPenalty)
	end

	if tuning().Enabled == false then
		-- Старая кривая (слишком щедрая) — только для сравнения
		local t = distance / maxRange
		local legacy = base - (t * t) * (0.18 + spread * 0.55) - movePenalty + (opts.bonus or 0) + (opts.entityMod or 0)
		return math.clamp(legacy, 0.08, 0.96)
	end

	local chance = (base + (opts.bonus or 0) + (opts.entityMod or 0)) * math.clamp(opts.profileMult or 1, 0.1, 2)
		- AccuracyHelper.DistancePenalty(distance, maxRange, spread)
		- movePenalty
	return math.clamp(chance, num("MinChance", DEFAULTS.MinChance), num("MaxChance", DEFAULTS.MaxChance))
end

function AccuracyHelper.RollShot(opts: ShotOpts): (boolean, number, number)
	local chance = AccuracyHelper.ComputeShotChance(opts)
	local roll = math.random()
	local hit = roll <= chance
	return hit, chance, roll
end

-- Совместимость: простой ролл без дистанции
function AccuracyHelper.RollHit(accuracy: number): boolean
	return math.random() <= math.clamp(accuracy or 0.75, 0.05, 0.95)
end

--[[
	SpreadAim — визуальная точка вылета пули с разбросом ТОЛЬКО по горизонтали.

	ТЗ заказчика: «убрать вертикальный разброс, оставить разброс по горизонтали» —
	тогда чем дальше цель, тем реже попадания, а вблизи стрельба почти в упор.
	Hit/miss остаётся вероятностным (ComputeShotChance); здесь мы лишь показываем
	трассер так, будто пуля ушла влево/вправо. Высота (Y) НЕ меняется — вертикального
	разброса нет. Угол растёт с дистанцией и падает с точностью стрелка.
]]
function AccuracyHelper.SpreadAim(origin: Vector3, aim: Vector3, opts): Vector3
	if typeof(origin) ~= "Vector3" or typeof(aim) ~= "Vector3" then
		return aim
	end
	if tuning().HorizontalOnlySpread == false then
		return aim
	end
	local delta = aim - origin
	local dist = delta.Magnitude
	if dist < 0.06 then
		return aim
	end
	local dir = delta.Unit
	-- Горизонтальная нормаль (право/лево) в плоскости XZ — вертикали здесь нет.
	local right = Vector3.new(dir.Z, 0, -dir.X)
	if right.Magnitude < 1e-4 then
		right = Vector3.new(1, 0, 0)
	else
		right = right.Unit
	end

	local o = opts or {}
	local base = math.clamp(o.accuracy or 0.75, 0, 1)
	local spread = math.clamp(o.spread or 0.2, 0, 1)
	local maxRange = math.max(1, o.maxRange or dist)
	local falloff = AccuracyHelper.DistancePenalty(o.distance or dist, maxRange, spread)
	-- Чем хуже точность и дальше цель — тем шире горизонтальный конус.
	local severity = math.clamp(0.25 + (1 - base) + falloff, 0, 1)
	local maxDeg = num("VisualSpreadMaxDeg", DEFAULTS.VisualSpreadMaxDeg or 5)
	local minDeg = num("VisualSpreadMinDeg", DEFAULTS.VisualSpreadMinDeg or 0.6)
	local angle = math.rad(minDeg + (maxDeg - minDeg) * severity)
	local side = if math.random() < 0.5 then -1 else 1
	local lateral = math.tan(angle) * dist * side
	-- Смещаем только по горизонтали: Y остаётся от исходного aim.
	return aim + right * lateral
end

return AccuracyHelper
