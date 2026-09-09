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
	if preferred and preferred.Alive and preferred.Root then
		local diff = preferred.Root.Position - fromPos
		local dSq = diff.X * diff.X + diff.Y * diff.Y + diff.Z * diff.Z
		if dSq <= (maxRange or 300) ^ 2 then
			return preferred
		end
	end
	local list = EnemyService.GetAliveInRange(fromPos, maxRange)
	if #list == 0 then
		return nil
	end
	return list[math.random(1, #list)]
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
	for _, e in ipairs(enemies) do
		e.Alive = false
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
		local baseTick = 0.15
		while enemy.Alive and enemy.Model and enemy.Model.Parent do
			local speedMult = (WaveService and WaveService.GetCombatSpeedMult and WaveService.GetCombatSpeedMult()) or 1
			local tickDt = baseTick / math.max(1, speedMult)
			task.wait(tickDt)
			local root = enemy.Root
			if not root then
				break
			end

			if wpIndex <= #waypoints then
				local target = waypoints[wpIndex]
				local pos = root.Position
				local flat = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
				local distToStop = EnemiesConfig.StopRange or 55
				local nearDefense = wpIndex >= #waypoints and flat.Magnitude < distToStop
				if flat.Magnitude < 4 then
					wpIndex += 1
				elseif not nearDefense then
					local dir = flat.Unit
					local speed = (enemy.WalkSpeed or 12) * math.max(1, speedMult)
					local nextPos = pos + dir * speed * tickDt
					root.CFrame = CFrame.lookAt(
						Vector3.new(nextPos.X, pos.Y, nextPos.Z),
						Vector3.new(nextPos.X, pos.Y, nextPos.Z) + dir
					)
				end
			end

			local now = os.clock()
			if now - (enemy.LastFire or 0) >= (enemy.FireRate or 0.5) and BotService then
				local cached = EnemyService.UpdateBotPositionCache()
				local best, bestD = nil, EnemiesConfig.AttackRange or 180
				for _, entry in ipairs(cached) do
					local d = (entry.Position - root.Position).Magnitude
					if d < bestD then
						bestD = d
						best = entry.Record
					end
				end
				if best and best.Root then
					enemy.LastFire = now
					local origin = root.Position + Vector3.new(0, 1.5, 0)
					local aim = best.Root.Position + Vector3.new(0, 1, 0)
					CharacterRigBuilder.PlayFireAnimation(enemy.Model, aim)
					if AccuracyHelper.RollHit(enemy.Accuracy) then
						CombatVFX.PlayMuzzle(origin, aim)
						BotService.DamageBot(best, enemy.Damage or 8)
					else
						CombatVFX.PlayMiss(origin, aim)
					end
				end
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
			local speedJitter = 0.75 + math.random() * 0.5
			local finalSpeed = stats.WalkSpeed * (typeMod.SpeedMult or 1) * speedJitter
			local finalAcc = math.clamp(stats.Accuracy + (typeMod.AccuracyMod or 0), 0.2, 0.95)
			local lateral = (math.random() * 2 - 1) * halfWidth * 0.85
			local spawnAt = MapBind.OffsetOnBridge(spawnPos, 0, lateral)
			-- Персональные waypoints со смещением по ширине
			local personalWp = {}
			for _, wp in ipairs(waypoints) do
				table.insert(personalWp, MapBind.OffsetOnBridge(wp, 0, lateral * (0.55 + math.random() * 0.35)))
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
				WalkSpeed = finalSpeed,
				Waypoints = #personalWp > 0 and personalWp or waypoints,
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
