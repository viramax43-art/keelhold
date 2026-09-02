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
local Log = require(ReplicatedStorage.Shared.Util.Log)

local EnemyService = {}
local enemies = {}
local WaveService, BotService, RewardService
local nextId = 1

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

function EnemyService.FindNearestEnemy(fromPos: Vector3, maxRange: number)
	local best, bestDist = nil, maxRange or 300
	for _, e in ipairs(enemies) do
		if e.Alive and e.Root then
			local d = (e.Root.Position - fromPos).Magnitude
			if d < bestDist then
				bestDist = d
				best = e
			end
		end
	end
	return best
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

function EnemyService.Clear()
	for _, e in ipairs(enemies) do
		if e.Model then
			e.Model:Destroy()
		end
	end
	table.clear(enemies)
end

function EnemyService.DamageEnemy(enemy, amount: number, attacker: Player?)
	if not enemy or not enemy.Alive then
		return
	end
	local mitigated = math.max(1, amount - (enemy.Armor or 0) * 0.2)
	enemy.CurrentHP -= mitigated
	CharacterRigBuilder.UpdateHealthBar(enemy.Model, enemy.CurrentHP, enemy.MaxHP)
	if enemy.Root then
		CombatVFX.PlayBlood(enemy.Root.Position + Vector3.new(0, 1, 0), 2.5)
	end
	if enemy.CurrentHP <= 0 then
		enemy.Alive = false
		if RewardService and attacker then
			RewardService.OnEnemyKilled(attacker)
		end
		if enemy.Model then
			enemy.Model:Destroy()
		end
		if WaveService and WaveService.OnEnemyDied then
			WaveService.OnEnemyDied()
		end
	end
end

local function startAI(enemy)
	task.spawn(function()
		local waypoints = enemy.Waypoints
		local wpIndex = 1
		while enemy.Alive and enemy.Model and enemy.Model.Parent do
			task.wait(0.1)
			local root = enemy.Root
			if not root then
				break
			end

			-- Move toward waypoint
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
					local speed = enemy.WalkSpeed or 14
					local nextPos = pos + dir * speed * 0.1
					root.CFrame = CFrame.lookAt(Vector3.new(nextPos.X, pos.Y, nextPos.Z), Vector3.new(nextPos.X, pos.Y, nextPos.Z) + dir)
				end
			end

			-- Shoot nearest bot
			local now = os.clock()
			if now - (enemy.LastFire or 0) >= (enemy.FireRate or 0.5) and BotService then
				local bots = WaveService and WaveService.GetBots and WaveService.GetBots() or {}
				local best, bestD = nil, EnemiesConfig.AttackRange or 180
				for _, b in ipairs(bots) do
					if b.Alive and b.Root then
						local d = (b.Root.Position - root.Position).Magnitude
						if d < bestD then
							bestD = d
							best = b
						end
					end
				end
				if best then
					enemy.LastFire = now
					local origin = root.Position + Vector3.new(0, 1.5, 0)
					local aim = best.Root.Position + Vector3.new(0, 1, 0)
					CombatVFX.PlayMuzzle(origin, aim)
					if AccuracyHelper.RollHit(enemy.Accuracy) then
						BotService.DamageBot(best, enemy.Damage or 10)
					end
				end
			end
		end
	end)
end

function EnemyService.SpawnWave(wave: number, difficultyMult: number)
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

	Log.Write("Wave", string.format("Wave %d starting, enemies=%d", wave, count))
	local interval = (GameConfig.Battle and GameConfig.Battle.EnemySpawnInterval) or 0.35
	local weapons = EnemiesConfig.WeaponRotation or { "Pistol" }

	task.spawn(function()
		for i = 1, count do
			if not WaveService or not WaveService.IsBattleActive or not WaveService.IsBattleActive() then
				break
			end
			local weaponType = weapons[((i - 1) % #weapons) + 1]
			local offset = Vector3.new((i % 5 - 2) * 2.5, 0, 0)
			local model = CharacterRigBuilder.CreateR6Kit({
				ModelName = "Enemy_" .. nextId,
				DisplayName = "Враг",
				Position = spawnPos + offset,
				WeaponType = weaponType,
				MaxHP = stats.HP,
				CurrentHP = stats.HP,
				Parent = folder,
				Kit = CharacterRigBuilder.GetKitVariant(i + 3),
			})
			local enemy = {
				Id = "E" .. nextId,
				Model = model,
				Root = model.PrimaryPart,
				CurrentHP = stats.HP,
				MaxHP = stats.HP,
				Armor = stats.Armor,
				Damage = stats.Damage,
				FireRate = stats.FireRate,
				Accuracy = stats.Accuracy,
				WalkSpeed = stats.WalkSpeed,
				Waypoints = waypoints,
				LastFire = 0,
				Alive = true,
			}
			nextId += 1
			table.insert(enemies, enemy)
			startAI(enemy)
			task.wait(interval)
		end
	end)
	return count
end

function EnemyService:Init(services)
	WaveService = services.WaveService
	BotService = services.BotService
	RewardService = services.RewardService
end

return EnemyService
