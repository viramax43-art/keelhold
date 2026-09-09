--[[
	EnemyService — спавн и AI врагов.
	Движение: один общий Heartbeat (без per-enemy task.wait).
	Оружие: индивидуальные Range/Accuracy/Spread из WeaponsConfig.
	Очередь: attack slots + queue slots по полосам.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local EnemiesConfig = require(ReplicatedStorage.Shared.Config.EnemiesConfig)
local WeaponsConfig = require(ReplicatedStorage.Shared.Config.WeaponsConfig)
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
local remainingToSpawn = 0
local spawnGeneration = 0
local cachedBotPositions = {}
local lastCacheUpdate = 0
local CACHE_INTERVAL = 0.3
local cleanupStarted = false
local attackSlotCount = 0
local laneAttackCounts = {} -- [lane] = number
local aiConnection: RBXScriptConnection? = nil
local TURN_SPEED = 12

local function getWeaponStats(weaponType: string, wave: number)
	local maxTier = WeaponsConfig.MaxTier or 5
	local tier = math.clamp(1 + math.floor(math.max(0, wave - 1) / 4), 1, maxTier)
	local byType = WeaponsConfig.Weapons and WeaponsConfig.Weapons[weaponType]
	local cfg = byType and (byType[tier] or byType[1])
	if type(cfg) ~= "table" then
		return {
			Damage = EnemiesConfig.BaseStats.Damage,
			FireRate = EnemiesConfig.BaseStats.FireRate,
			Range = EnemiesConfig.AttackRange or 180,
			Accuracy = EnemiesConfig.BaseStats.Accuracy,
			Spread = 0.28,
			Tier = tier,
		}
	end
	return {
		Damage = tonumber(cfg.Damage) or EnemiesConfig.BaseStats.Damage,
		FireRate = tonumber(cfg.FireRate) or EnemiesConfig.BaseStats.FireRate,
		Range = tonumber(cfg.Range) or (EnemiesConfig.AttackRange or 180),
		Accuracy = tonumber(cfg.Accuracy) or EnemiesConfig.BaseStats.Accuracy,
		Spread = tonumber(cfg.Spread) or 0.28,
		Tier = tier,
	}
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

local function getDefenseFrame(enemy): (Vector3?, Vector3?)
	local wps = enemy.Waypoints
	if not wps or #wps == 0 then
		return nil, nil
	end
	local last = wps[#wps]
	local first = wps[1]
	local dir = Vector3.new(last.X - first.X, 0, last.Z - first.Z)
	if dir.Magnitude < 0.1 then
		dir = Vector3.new(0, 0, -1)
	else
		dir = dir.Unit
	end
	return last, dir
end

local function nearestAllyAhead(enemy): any?
	if not enemy.Root then
		return nil
	end
	local minSpacing = EnemiesConfig.MinSpacing or 5.5
	local best, bestDist = nil, minSpacing
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
	local maxPerLane = EnemiesConfig.AttackSlotsPerLane or 1
	if enemy.HasAttackSlot then
		return true
	end
	local lane = enemy.Lane or 1
	local laneCount = laneAttackCounts[lane] or 0
	if attackSlotCount >= maxA or laneCount >= maxPerLane then
		return false
	end
	enemy.HasAttackSlot = true
	enemy.AttackSlotIndex = laneCount + 1
	attackSlotCount += 1
	laneAttackCounts[lane] = laneCount + 1
	return true
end

local function releaseAttackSlot(enemy)
	if enemy.HasAttackSlot then
		enemy.HasAttackSlot = false
		enemy.AttackSlotIndex = nil
		local lane = enemy.Lane or 1
		laneAttackCounts[lane] = math.max(0, (laneAttackCounts[lane] or 1) - 1)
		attackSlotCount = math.max(0, attackSlotCount - 1)
	end
end

local function computeQueueIndex(enemy): number
	local idx = 0
	local myProg = enemy.ProgressDist or math.huge
	for _, other in ipairs(enemies) do
		if other.Alive and other ~= enemy and other.Lane == enemy.Lane then
			local otherProg = other.ProgressDist or math.huge
			if other.HasAttackSlot or otherProg < myProg - 0.05 then
				idx += 1
			elseif math.abs(otherProg - myProg) < 0.5 and (other.Id or "") < (enemy.Id or "") then
				idx += 1
			end
		end
	end
	return idx
end

local function setAttackTargetPosition(enemy)
	local last, dir = getDefenseFrame(enemy)
	if not last or not dir or not enemy.Root then
		return
	end
	local spacing = EnemiesConfig.AttackSpacing or 4.5
	local slot = enemy.AttackSlotIndex or 1
	local lateralNudge = (slot - 1) * 0.35
	local pos = last - dir * spacing
	-- Слегка разводим слоты вбок вдоль перпендикуляра
	local side = Vector3.new(-dir.Z, 0, dir.X)
	if side.Magnitude > 0.1 then
		pos = pos + side.Unit * lateralNudge
	end
	enemy.AttackTargetPosition = Vector3.new(pos.X, enemy.Root.Position.Y, pos.Z)
end

local function setQueueTargetPosition(enemy)
	local last, dir = getDefenseFrame(enemy)
	if not last or not dir or not enemy.Root then
		return
	end
	local q = enemy.QueueSlotIndex or 0
	local spacing = EnemiesConfig.QueueSpacing or 5.5
	local pos = last - dir * (spacing * (q + 1) + (EnemiesConfig.AttackSpacing or 4.5))
	enemy.QueueTargetPosition = Vector3.new(pos.X, enemy.Root.Position.Y, pos.Z)
end

local function moveRootToward(root: BasePart, targetPos: Vector3, lookDir: Vector3?, speed: number, dt: number)
	local pos = root.Position
	local flat = Vector3.new(targetPos.X - pos.X, 0, targetPos.Z - pos.Z)
	if flat.Magnitude < 0.08 then
		return true
	end
	local dir = flat.Unit
	local step = math.min(flat.Magnitude, speed * dt)
	local nextPos = Vector3.new(pos.X + dir.X * step, pos.Y, pos.Z + dir.Z * step)
	local face = lookDir or dir
	if face.Magnitude < 0.05 then
		face = dir
	else
		face = Vector3.new(face.X, 0, face.Z)
		if face.Magnitude < 0.05 then
			face = dir
		else
			face = face.Unit
		end
	end
	local targetRot = CFrame.lookAt(nextPos, nextPos + face)
	local alpha = math.clamp(dt * TURN_SPEED, 0, 1)
	local newRot = root.CFrame.Rotation:Lerp(targetRot.Rotation, alpha)
	root.CFrame = CFrame.new(nextPos) * newRot
	return flat.Magnitude <= step + 0.05
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

function EnemyService.GetDisplayEnemyCount(): number
	return EnemyService.GetAliveCount() + math.max(0, remainingToSpawn)
end

local function stopAIUpdate()
	if aiConnection then
		aiConnection:Disconnect()
		aiConnection = nil
	end
end

function EnemyService.Clear()
	spawnGeneration += 1
	remainingToSpawn = 0
	attackSlotCount = 0
	table.clear(laneAttackCounts)
	stopAIUpdate()
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
		enemy.State = "Dead"
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

local function tryFire(enemy, now: number, speedMult: number)
	local root = enemy.Root
	if not root or not BotService then
		return
	end

	local arrive = EnemiesConfig.AttackArriveDistance or 1.5
	local isAtAttackPosition = enemy.HasAttackSlot
		and enemy.AttackTargetPosition
		and (root.Position - enemy.AttackTargetPosition).Magnitude <= arrive

	local useMelee = enemy.State == "Attacking" and isAtAttackPosition == true
	local fireCd = enemy.FireRate or 0.5
	local dmg = enemy.Damage or 8
	if useMelee then
		fireCd = EnemiesConfig.MeleeFireRate or 0.45
		dmg = dmg * (EnemiesConfig.MeleeDamageMult or 2.2)
	end
	fireCd = fireCd / math.max(1, speedMult)

	-- Queued не стреляет; Moving/Attacking — да
	if enemy.State == "Queued" then
		return
	end
	if now - (enemy.LastFire or 0) < fireCd then
		return
	end

	local weaponRange = enemy.Range or EnemiesConfig.AttackRange or 180
	local cached = EnemyService.UpdateBotPositionCache()
	local best, bestD = nil, if useMelee then (arrive + 8) else weaponRange
	for _, entry in ipairs(cached) do
		local d = (entry.Position - root.Position).Magnitude
		if d < bestD then
			bestD = d
			best = entry.Record
		end
	end
	if not best or not best.Root then
		return
	end

	enemy.LastFire = now
	local origin = CombatVFX.GetMuzzleWorldPosition(enemy.Model) or (root.Position + Vector3.new(0, 1.2, 0))
	local aim = best.Root.Position + Vector3.new(0, 1, 0)
	CharacterRigBuilder.PlayFireAnimation(enemy.Model, aim)

	local losClear, losPos = CombatVFX.HasClearLos(origin, aim, weaponRange, enemy.Model, best.Model)

	local hit = false
	if useMelee then
		hit = true
	elseif not losClear then
		hit = false
		aim = losPos
	else
		-- bestD уже ≤ weaponRange; clamp от смещения дула
		local shotDistance = math.min(bestD, weaponRange)
		hit = AccuracyHelper.RollShot({
			baseAccuracy = enemy.Accuracy,
			distance = shotDistance,
			maxRange = weaponRange,
			spread = enemy.Spread or 0.28,
			movingShooter = enemy.State == "Moving",
			movingTarget = false,
			entityMod = 0,
		})
	end

	if hit then
		CombatVFX.PlayMuzzle(origin, aim, enemy.Model, enemy.WeaponType)
		BotService.DamageBot(best, dmg)
	else
		CombatVFX.PlayMiss(origin, aim, enemy.Model, enemy.WeaponType, weaponRange)
	end
end

local function updateEnemy(enemy, dt: number)
	local root = enemy.Root
	if not root or not root.Parent or not enemy.Alive then
		return
	end

	local now = os.clock()
	local speedMult = (WaveService and WaveService.GetCombatSpeedMult and WaveService.GetCombatSpeedMult()) or 1
	local speed = (enemy.WalkSpeed or 12) * math.max(1, speedMult)
	enemy.ProgressDist = distToDefense(enemy)

	local meleeRange = EnemiesConfig.MeleeRange or 18
	local nearLine = enemy.ProgressDist <= meleeRange
	local arrive = EnemiesConfig.AttackArriveDistance or 1.5

	if nearLine then
		if tryClaimAttackSlot(enemy) then
			setAttackTargetPosition(enemy)
			local slotPos = enemy.AttackTargetPosition
			if slotPos and (root.Position - slotPos).Magnitude <= arrive then
				enemy.State = "Attacking"
			else
				enemy.State = "Moving"
				if slotPos then
					local _, dir = getDefenseFrame(enemy)
					moveRootToward(root, slotPos, dir, speed, dt)
				end
			end
		else
			if enemy.HasAttackSlot then
				releaseAttackSlot(enemy)
			end
			enemy.State = "Queued"
			enemy.QueueSlotIndex = computeQueueIndex(enemy)
			setQueueTargetPosition(enemy)
			local qPos = enemy.QueueTargetPosition
			if qPos then
				local distQ = (root.Position - qPos).Magnitude
				if distQ > arrive then
					local _, dir = getDefenseFrame(enemy)
					moveRootToward(root, qPos, dir, speed, dt)
				else
					-- На позиции очереди — смотрим на оборону
					local last, dir = getDefenseFrame(enemy)
					if last and dir then
						local targetRot = CFrame.lookAt(root.Position, root.Position + dir)
						root.CFrame = CFrame.new(root.Position)
							* root.CFrame.Rotation:Lerp(targetRot.Rotation, math.clamp(dt * TURN_SPEED, 0, 1))
					end
				end
			end
		end
	else
		if enemy.HasAttackSlot then
			releaseAttackSlot(enemy)
		end
		enemy.State = "Moving"
		enemy.AttackTargetPosition = nil
		enemy.QueueTargetPosition = nil

		local waypoints = enemy.Waypoints
		local wpIndex = enemy.WpIndex or 1
		if waypoints and wpIndex <= #waypoints then
			local blocked = nearestAllyAhead(enemy)
			if not blocked then
				local target = waypoints[wpIndex]
				local pos = root.Position
				local flat = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
				if flat.Magnitude < 3 then
					enemy.WpIndex = wpIndex + 1
				else
					moveRootToward(root, target, flat.Unit, speed, dt)
				end
			else
				-- Держим дистанцию — лёгкий стоп
				local last, dir = getDefenseFrame(enemy)
				if dir then
					local targetRot = CFrame.lookAt(root.Position, root.Position + dir)
					root.CFrame = CFrame.new(root.Position)
						* root.CFrame.Rotation:Lerp(targetRot.Rotation, math.clamp(dt * TURN_SPEED, 0, 1))
				end
			end
		end
	end

	tryFire(enemy, now, speedMult)
end

local function startAIUpdate()
	if aiConnection then
		return
	end
	aiConnection = RunService.Heartbeat:Connect(function(dt)
		local effectiveDt = math.clamp(dt, 0, 0.05)
		for _, enemy in ipairs(enemies) do
			if enemy.Alive and enemy.Model and enemy.Model.Parent and enemy.Root then
				updateEnemy(enemy, effectiveDt)
			end
		end
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
	local baseDmg = EnemiesConfig.BaseStats.Damage or 8
	local baseFire = EnemiesConfig.BaseStats.FireRate or 0.6
	local baseAcc = EnemiesConfig.BaseStats.Accuracy or 0.55
	local waveDmgMult = (stats.Damage or baseDmg) / baseDmg
	local waveFireMult = baseFire / math.max(0.05, stats.FireRate or baseFire)
	local waveAccBonus = (stats.Accuracy or baseAcc) - baseAcc

	local function laneLateral(laneIndex: number): number
		if laneCount <= 1 then
			return 0
		end
		local t = (laneIndex - 1) / (laneCount - 1)
		return (t - 0.5) * laneWidth
	end

	if WaveService and WaveService.NotifyWaveHud then
		WaveService.NotifyWaveHud()
	end

	startAIUpdate()

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
			local weaponCfg = getWeaponStats(weaponType, wave)
			local finalHP = stats.HP * (typeMod.HPMult or 1)
			local finalDMG = weaponCfg.Damage * (typeMod.DamageMult or 1) * waveDmgMult
			local speedJitter = 0.85 + math.random() * 0.3
			local finalSpeed = stats.WalkSpeed * (typeMod.SpeedMult or 1) * speedJitter
			local finalAcc = math.clamp(
				weaponCfg.Accuracy + (typeMod.AccuracyMod or 0) + waveAccBonus,
				0.2,
				0.95
			)
			local finalFire = math.max(
				EnemiesConfig.MinFireRate or 0.15,
				weaponCfg.FireRate / math.max(0.5, waveFireMult)
			)
			local finalSpread = weaponCfg.Spread
			local finalRange = weaponCfg.Range
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
			model:SetAttribute("WeaponTier", weaponCfg.Tier)
			local enemy = {
				Id = "E" .. nextId,
				Model = model,
				Root = model.PrimaryPart,
				CurrentHP = finalHP,
				MaxHP = finalHP,
				Armor = stats.Armor,
				Damage = finalDMG,
				FireRate = finalFire,
				Accuracy = finalAcc,
				Spread = finalSpread,
				Range = finalRange,
				WeaponType = weaponType,
				WalkSpeed = finalSpeed,
				Waypoints = #personalWp > 0 and personalWp or waypoints,
				WpIndex = 1,
				Lane = lane,
				LateralOffset = lateral,
				State = "Moving",
				ProgressDist = math.huge,
				HasAttackSlot = false,
				AttackSlotIndex = nil,
				QueueSlotIndex = nil,
				AttackTargetPosition = nil,
				QueueTargetPosition = nil,
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
			if WaveService and WaveService.NotifyWaveHud then
				WaveService.NotifyWaveHud()
			end
			if i % groupSize == 0 then
				local sm = (WaveService and WaveService.GetCombatSpeedMult and WaveService.GetCombatSpeedMult()) or 1
				task.wait(groupGap / math.max(1, sm))
			else
				local sm = (WaveService and WaveService.GetCombatSpeedMult and WaveService.GetCombatSpeedMult()) or 1
				task.wait(interval / math.max(1, sm))
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
