--[[
	EnemyService — спавн и AI врагов по BridgePath.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local EnemiesConfig = require(ReplicatedStorage.Shared.Config.EnemiesConfig)
local CharacterRigBuilder = require(ReplicatedStorage.Shared.Builders.CharacterRigBuilder)
local WaveScaling = require(ReplicatedStorage.Shared.Util.WaveScaling)
local AccuracyHelper = require(ReplicatedStorage.Shared.Util.AccuracyHelper)
local CombatVFX = require(ReplicatedStorage.Shared.Util.CombatVFX)
local DamageFormula = require(ReplicatedStorage.Shared.Util.DamageFormula)
local Log = require(ReplicatedStorage.Shared.Util.Log)

local EnemyService = {}
local enemies = {}
local WaveService, BotService, RewardService
local nextId = 1
local remainingToSpawn = 0 -- ещё не появившиеся в текущей волне (для HUD)
local spawnGeneration = 0
local cachedBotPositions = {}
local lastCacheUpdate = 0
local CACHE_INTERVAL = 0.3
local cleanupStarted = false
local attackSlotCount = 0

local function nearestAllyAhead(enemy): any?
	if not enemy.Root then
		return nil
	end
	local best, bestDist = nil, EnemiesConfig.MinSpacing or 5.5
	local myProg = enemy.ProgressDist or math.huge
	for _, other in ipairs(enemies) do
		if other.Alive and other ~= enemy and other.Lane == enemy.Lane and other.Root then
			local otherProg = other.ProgressDist or math.huge
			if otherProg < myProg then
				local d = (other.Root.Position - enemy.Root.Position).Magnitude
				if d < bestDist then
					bestDist = d
					best = other
				end
			end
		end
	end
	return best
end

local function tryClaimAttackSlot(enemy): boolean
	local maxA = EnemiesConfig.MaxAttackers or 4
	if enemy.HasAttackSlot then
		return true
	end
	if attackSlotCount >= maxA then
		return false
	end
	enemy.HasAttackSlot = true
	attackSlotCount += 1
	return true
end

local function releaseAttackSlot(enemy)
	if enemy.HasAttackSlot then
		enemy.HasAttackSlot = false
		attackSlotCount = math.max(0, attackSlotCount - 1)
	end
end

local function distToDefense(enemy): number
	local wps = enemy.Waypoints
	if not wps or #wps == 0 or not enemy.Root then
		return math.huge
	end
	local last = wps[#wps]
	local pos = enemy.Root.Position
	return Vector3.new(last.X - pos.X, 0, last.Z - pos.Z).Magnitude
end


local function getWaypoints(): { Vector3 }
	local folder = workspace:FindFirstChild("MapPoints")
	local pts = {}
	local names = GameConfig.MapPointNames.BridgePathWaypoints or {}
	for _, name in ipairs(names) do
		local p = folder and folder:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			table.insert(pts, p.Position)
		end
	end
	local endP = folder and folder:FindFirstChild(GameConfig.MapPointNames.BridgePath)
	if endP and endP:IsA("BasePart") then
		table.insert(pts, endP.Position)
	end
	return pts
end

local function getEnemySpawn(): Vector3
	local folder = workspace:FindFirstChild("MapPoints")
	local p = folder and folder:FindFirstChild(GameConfig.MapPointNames.EnemySpawn)
	if p and p:IsA("BasePart") then
		return p.Position
	end
	return Vector3.new(0, 5, 0)
end

function EnemyService.FindEnemyById(id: string)
	if not id then
		return nil
	end
	for _, e in ipairs(enemies) do
		if e.Id == id and e.Alive then
			return e
		end
	end
	return nil
end

function EnemyService.FindNearestEnemy(fromPos: Vector3, maxRange: number)
	local maxRangeSq = (maxRange or 300) ^ 2
	local best, bestDistSq = nil, maxRangeSq
	for _, e in ipairs(enemies) do
		if e.Alive and e.Root then
			local diff = e.Root.Position - fromPos
			local dSq = diff.X * diff.X + diff.Y * diff.Y + diff.Z * diff.Z
			if dSq < bestDistSq then
				bestDistSq = dSq
				best = e
			end
		end
	end
	return best
end

function EnemyService.GetAliveInRange(fromPos: Vector3, maxRange: number): { any }
	local maxRangeSq = (maxRange or 300) ^ 2
	local list = {}
	for _, e in ipairs(enemies) do
		if e.Alive and e.Root then
			local diff = e.Root.Position - fromPos
			local dSq = diff.X * diff.X + diff.Y * diff.Y + diff.Z * diff.Z
			if dSq <= maxRangeSq then
				table.insert(list, e)
			end
		end
	end
	return list
end

function EnemyService.PickRandomEnemy(fromPos: Vector3, maxRange: number, preferred)
	return EnemyService.PickTargetForDefender(fromPos, maxRange, preferred, nil)
end

--[[
	Цель для союзного бота:
	- предпочитаем ближайших врагов (не весь мост случайно);
	- не сваливаем всех ботов в одного «самого ближнего»;
	- мягкий lock, но с лимитом фокуса (~1–2 бота на цель).
]]
function EnemyService.PickTargetForDefender(fromPos: Vector3, maxRange: number, preferred, teammateBots, selfBot): any?
	local list = EnemyService.GetAliveInRange(fromPos, maxRange)
	if #list == 0 then
		return nil
	end

	local function distOf(e): number
		local p = e.Root.Position
		local dx, dy, dz = p.X - fromPos.X, p.Y - fromPos.Y, p.Z - fromPos.Z
		return math.sqrt(dx * dx + dy * dy + dz * dz)
	end

	table.sort(list, function(a, b)
		return distOf(a) < distOf(b)
	end)

	local nearestD = distOf(list[1])
	local nearBand = math.max(nearestD * 2.25, 50)
	local pool = {}
	for i, e in ipairs(list) do
		if i <= 4 or (i <= 8 and distOf(e) <= nearBand) then
			table.insert(pool, e)
		else
			break
		end
	end

	local focus: { [string]: number } = {}
	if type(teammateBots) == "table" then
		for _, bot in ipairs(teammateBots) do
			if bot and bot ~= selfBot and bot.Alive then
				local t = bot.LockedTarget
				if t and t.Alive and t.Id then
					focus[t.Id] = (focus[t.Id] or 0) + 1
				end
			end
		end
	end

	local function inPool(enemy): boolean
		for _, e in ipairs(pool) do
			if e == enemy then
				return true
			end
		end
		return false
	end

	-- Мягкий lock: держим цель, если она ещё «ближняя» и не перегружена чужим фокусом
	if preferred and preferred.Alive and preferred.Root and inPool(preferred) then
		local f = focus[preferred.Id] or 0
		if f < 2 and math.random() < 0.62 then
			return preferred
		end
	end

	local totalW = 0
	local weights = table.create(#pool)
	for i, e in ipairs(pool) do
		local d = distOf(e)
		local f = focus[e.Id] or 0
		local w = (1 / (1 + d * 0.035)) / (1 + f * f)
		if f >= 2 then
			w *= 0.1
		elseif f >= 1 then
			w *= 0.5
		end
		weights[i] = w
		totalW += w
	end

	if totalW <= 0 then
		return pool[1]
	end

	local roll = math.random() * totalW
	local acc = 0
	for i, e in ipairs(pool) do
		acc += weights[i]
		if roll <= acc then
			return e
		end
	end
	return pool[#pool]
end

function EnemyService.GetAliveCount(): number
	local n = 0
	for _, e in ipairs(enemies) do
		if e.Alive then
			n += 1
		end
	end
	return n
end

-- Живые + ещё не заспавненные (чтобы HUD не показывал «1» в начале волны)
function EnemyService.GetDisplayEnemyCount(): number
	return EnemyService.GetAliveCount() + math.max(0, remainingToSpawn)
end

function EnemyService.Clear()
	spawnGeneration += 1
	remainingToSpawn = 0
	attackSlotCount = 0
	for _, e in ipairs(enemies) do
		e.Alive = false
		e.HasAttackSlot = false
		if e.Model then
			e.Model:Destroy()
		end
		e.Model = nil
		e.Root = nil
	end
	table.clear(enemies)
end

function EnemyService.AbortRemainingSpawns()
	spawnGeneration += 1
	remainingToSpawn = 0
end

function EnemyService.UpdateBotPositionCache()
	local now = os.clock()
	if now - lastCacheUpdate < CACHE_INTERVAL then
		return cachedBotPositions
	end
	lastCacheUpdate = now
	cachedBotPositions = {}
	local bots = WaveService and WaveService.GetBots and WaveService.GetBots() or {}
	for _, b in ipairs(bots) do
		if b.Alive and b.Root then
			table.insert(cachedBotPositions, {
				Position = b.Root.Position,
				Record = b,
			})
		end
	end
	return cachedBotPositions
end

function EnemyService.DamageEnemy(enemy, amount: number, attacker: Player?)
	if not enemy or not enemy.Alive then
		return
	end
	local mitigated = DamageFormula.Mitigate(amount, enemy.Armor)
	local appliedDamage = math.min(math.max(enemy.CurrentHP, 0), math.max(mitigated, 0))
	enemy.CurrentHP -= appliedDamage
	if enemy.Model then
		CharacterRigBuilder.UpdateHealthBar(enemy.Model, enemy.CurrentHP, enemy.MaxHP)
	end
	if enemy.Root then
		CombatVFX.PlayBlood(enemy.Root.Position + Vector3.new(0, 1, 0), 2.5)
	end
	if attacker and RewardService and RewardService.OnEnemyDamaged then
		RewardService.OnEnemyDamaged(attacker, appliedDamage, enemy.MaxHP or 1)
	end
	if enemy.CurrentHP <= 0 then
		enemy.Alive = false
		releaseAttackSlot(enemy)
		if RewardService and attacker then
			RewardService.OnEnemyKilled(attacker)
		end
		if enemy.Model then
			enemy.Model:Destroy()
		end
		enemy.Model = nil
		enemy.Root = nil
		if WaveService and WaveService.OnEnemyDied then
			WaveService.OnEnemyDied()
		end
	end
end

function EnemyService.StartCleanupLoop()
	if cleanupStarted then
		return
	end
	cleanupStarted = true
	task.spawn(function()
		while true do
			task.wait(10)
			for i = #enemies, 1, -1 do
				if not enemies[i].Alive then
					releaseAttackSlot(enemies[i])
					table.remove(enemies, i)
				end
			end
		end
	end)
end

local function startAI(enemy)
	task.spawn(function()
		local waypoints = enemy.Waypoints
		local wpIndex = 1
		local lastClock = os.clock()
		enemy.State = "Moving"
		while enemy.Alive and enemy.Model and enemy.Model.Parent do
			task.wait()
			local now = os.clock()
			local dt = math.clamp(now - lastClock, 0, 0.05)
			lastClock = now
			local root = enemy.Root
			if not root or not root.Parent then
				break
			end

			local speedMult = (WaveService and WaveService.GetCombatSpeedMult and WaveService.GetCombatSpeedMult()) or 1
			enemy.ProgressDist = distToDefense(enemy)
			local meleeRange = EnemiesConfig.MeleeRange or 18
			local nearLine = enemy.ProgressDist <= meleeRange

			if nearLine then
				if tryClaimAttackSlot(enemy) then
					enemy.State = "Attacking"
				else
					enemy.State = "Queued"
				end
			else
				if enemy.HasAttackSlot then
					releaseAttackSlot(enemy)
				end
				enemy.State = "Moving"
			end

			-- Движение к waypoint с deltaTime; стоп если впереди союзник на полосе
			if enemy.State == "Moving" and wpIndex <= #waypoints then
				local blocked = nearestAllyAhead(enemy)
				if not blocked then
					local target = waypoints[wpIndex]
					local pos = root.Position
					local flat = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
					if flat.Magnitude < 3 then
						wpIndex += 1
					elseif flat.Magnitude > 0.05 then
						local dir = flat.Unit
						local speed = (enemy.WalkSpeed or 12) * math.max(1, speedMult)
						local step = math.min(flat.Magnitude, speed * dt)
						local nextPos = pos + dir * step
						root.CFrame = CFrame.lookAt(
							Vector3.new(nextPos.X, pos.Y, nextPos.Z),
							Vector3.new(nextPos.X, pos.Y, nextPos.Z) + dir
						)
					end
				end
			elseif enemy.State == "Queued" then
				-- Стоим в очереди — лёгкий поворот к обороне
				local wps = waypoints
				if wps and #wps > 0 then
					local last = wps[#wps]
					local pos = root.Position
					local look = Vector3.new(last.X - pos.X, 0, last.Z - pos.Z)
					if look.Magnitude > 0.1 then
						root.CFrame = CFrame.lookAt(pos, pos + look.Unit)
					end
				end
			end

			-- Стрельба / ближняя атака
			local fireCd = enemy.FireRate or 0.5
			local dmg = enemy.Damage or 8
			local useMelee = enemy.State == "Attacking"
			if useMelee then
				fireCd = EnemiesConfig.MeleeFireRate or 0.45
				dmg = dmg * (EnemiesConfig.MeleeDamageMult or 2.2)
			end
			fireCd = fireCd / math.max(1, speedMult)

			if (enemy.State == "Attacking" or enemy.State == "Moving") and now - (enemy.LastFire or 0) >= fireCd and BotService then
				local cached = EnemyService.UpdateBotPositionCache()
				local best, bestD = nil, useMelee and (meleeRange + 8) or (EnemiesConfig.AttackRange or 180)
				for _, entry in ipairs(cached) do
					local d = (entry.Position - root.Position).Magnitude
					if d < bestD then
						bestD = d
						best = entry.Record
					end
				end
				if best and best.Root then
					enemy.LastFire = now
					local origin = CombatVFX.GetMuzzleWorldPosition(enemy.Model) or (root.Position + Vector3.new(0, 1.2, 0))
					local aim = best.Root.Position + Vector3.new(0, 1, 0)
					CharacterRigBuilder.PlayFireAnimation(enemy.Model, aim)
					local hit
					if useMelee then
						hit = true -- в упор точность не роллим
					else
						hit = AccuracyHelper.RollShot({
							baseAccuracy = enemy.Accuracy,
							distance = bestD,
							maxRange = EnemiesConfig.AttackRange or 180,
							spread = enemy.Spread or 0.28,
							movingShooter = enemy.State == "Moving",
							movingTarget = false,
							entityMod = 0,
						})
					end
					if hit then
						CombatVFX.PlayMuzzle(origin, aim)
						BotService.DamageBot(best, dmg)
					else
						CombatVFX.PlayMiss(origin, aim)
					end
				end
			end
		end
		releaseAttackSlot(enemy)
	end)
end

function EnemyService.SpawnWave(wave: number, difficultyMult: number)
	spawnGeneration += 1
	local generation = spawnGeneration
	local count = WaveScaling.EnemyCount(wave)
	local stats = WaveScaling.EnemyStats(wave, difficultyMult)
	local spawnPos = getEnemySpawn()
	local waypoints = getWaypoints()
	local folder = workspace:FindFirstChild("Enemies")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Enemies"
		folder.Parent = workspace
	end

	local MapBind = require(ReplicatedStorage.Shared.Map.MapBind)
	Log.Write("Wave", string.format("Wave %d starting, enemies=%d", wave, count))
	remainingToSpawn = count
	local interval = (GameConfig.Battle and GameConfig.Battle.EnemySpawnInterval) or 0.35
	local groupSize = (GameConfig.Battle and GameConfig.Battle.EnemyGroupSize) or 4
	local groupGap = (GameConfig.Battle and GameConfig.Battle.EnemyGroupGap) or 0.9
	local weapons = EnemiesConfig.WeaponRotation or { "Pistol" }
	local types = EnemiesConfig.EnemyTypes or {}
	local halfWidth = math.max(8, (workspace:GetAttribute("CommissionBridgeHalfWidth") or 18))
	local laneCount = EnemiesConfig.LaneCount or 6
	local laneWidth = halfWidth * 1.7
	local function laneLateral(laneIndex: number): number
		if laneCount <= 1 then
			return 0
		end
		local t = (laneIndex - 1) / (laneCount - 1) -- 0..1
		return (t - 0.5) * laneWidth
	end

	if WaveService and WaveService.NotifyWaveHud then
		WaveService.NotifyWaveHud()
	end

	task.spawn(function()
		for i = 1, count do
			if generation ~= spawnGeneration
				or not WaveService
				or not WaveService.CanSpawnForWave
				or not WaveService.CanSpawnForWave(wave)
			then
				if generation == spawnGeneration then
					remainingToSpawn = 0
				end
				break
			end
			local weaponType = weapons[((i - 1) % #weapons) + 1]
			local typeMod = types[weaponType] or {}
			local finalHP = stats.HP * (typeMod.HPMult or 1)
			local finalDMG = stats.Damage * (typeMod.DamageMult or 1)
			local speedJitter = 0.85 + math.random() * 0.3
			local finalSpeed = stats.WalkSpeed * (typeMod.SpeedMult or 1) * speedJitter
			local finalAcc = math.clamp(stats.Accuracy + (typeMod.AccuracyMod or 0), 0.2, 0.95)
			local lane = ((i - 1) % laneCount) + 1
			local lateral = laneLateral(lane)
			local spawnAt = MapBind.OffsetOnBridge(spawnPos, 0, lateral)
			local personalWp = {}
			for _, wp in ipairs(waypoints) do
				table.insert(personalWp, MapBind.OffsetOnBridge(wp, 0, lateral))
			end
			local model = CharacterRigBuilder.CreateNPC({
				ModelName = "Enemy_" .. nextId,
				DisplayName = "Враг",
				Position = spawnAt,
				WeaponType = weaponType,
				MaxHP = finalHP,
				CurrentHP = finalHP,
				Parent = folder,
				Team = "Enemy",
				Style = CharacterRigBuilder.GetKitVariant(i + wave, "Enemy"),
			})
			if not model then
				Log.Write("Wave", "Enemy model creation failed", "ERROR")
				remainingToSpawn = math.max(0, remainingToSpawn - 1)
				continue
			end
			model:SetAttribute("EnemyId", "E" .. nextId)
			model:SetAttribute("Lane", lane)
			local enemy = {
				Id = "E" .. nextId,
				Model = model,
				Root = model.PrimaryPart,
				CurrentHP = finalHP,
				MaxHP = finalHP,
				Armor = stats.Armor,
				Damage = finalDMG,
				FireRate = stats.FireRate,
				Accuracy = finalAcc,
				Spread = 0.28,
				WalkSpeed = finalSpeed,
				Waypoints = #personalWp > 0 and personalWp or waypoints,
				Lane = lane,
				State = "Moving",
				ProgressDist = math.huge,
				HasAttackSlot = false,
				LastFire = 0,
				Alive = true,
			}
			nextId += 1
			if generation ~= spawnGeneration then
				model:Destroy()
				break
			end
			remainingToSpawn = math.max(0, remainingToSpawn - 1)
			table.insert(enemies, enemy)
			startAI(enemy)
			if WaveService and WaveService.NotifyWaveHud then
				WaveService.NotifyWaveHud()
			end
			if i % groupSize == 0 then
				local speedMult = (WaveService and WaveService.GetCombatSpeedMult and WaveService.GetCombatSpeedMult()) or 1
				task.wait(groupGap / math.max(1, speedMult))
			else
				local speedMult = (WaveService and WaveService.GetCombatSpeedMult and WaveService.GetCombatSpeedMult()) or 1
				task.wait(interval / math.max(1, speedMult))
			end
		end
		if generation == spawnGeneration then
			remainingToSpawn = 0
			if WaveService and WaveService.NotifyWaveHud then
				WaveService.NotifyWaveHud()
			end
			if WaveService and WaveService.OnWaveSpawningFinished then
				WaveService.OnWaveSpawningFinished(wave)
			end
		end
	end)
	return count
end

function EnemyService:Init(services)
	WaveService = services.WaveService
	BotService = services.BotService
	RewardService = services.RewardService
	EnemyService.StartCleanupLoop()
end

return EnemyService
