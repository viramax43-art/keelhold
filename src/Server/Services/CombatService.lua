--[[
	CombatService — стрельба игрока (FireWeapon).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)
local StatCalculator = require(ReplicatedStorage.Shared.Util.StatCalculator)
local CombatRange = require(ReplicatedStorage.Shared.Util.CombatRange)
local AccuracyHelper = require(ReplicatedStorage.Shared.Util.AccuracyHelper)
local CombatVFX = require(ReplicatedStorage.Shared.Util.CombatVFX)

local CombatService = {}
local DataService, EnemyService, RemoteService
local lastFire = {}

function CombatService:Init(services)
	DataService = services.DataService
	EnemyService = services.EnemyService
	RemoteService = services.RemoteService

	local fire = RemoteService.GetRemote(RemoteNames.FireWeapon)
	if fire and fire:IsA("RemoteFunction") then
		fire.OnServerInvoke = function(player, targetId, origin)
			local profile = DataService.GetProfile(player)
			if not profile then
				return { hit = false }
			end
			local stats = StatCalculator.BuildCombatStats(profile, 1)
			local now = os.clock()
			local uid = player.UserId
			if lastFire[uid] and now - lastFire[uid] < (stats.FireRate or 0.2) * 0.85 then
				return { hit = false, reason = "cooldown" }
			end
			lastFire[uid] = now

			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local from = (typeof(origin) == "Vector3" and origin) or (hrp and hrp.Position) or Vector3.zero
			local range = CombatRange.GetPlayerEngageRange()
			local enemy = EnemyService.FindNearestEnemy(from, range)
			if not enemy or not enemy.Root then
				return { hit = false }
			end
			local dist = (enemy.Root.Position - from).Magnitude
			if dist > (GameConfig.MaxHitDistance or 500) then
				return { hit = false }
			end
			CombatVFX.PlayMuzzle(from + Vector3.new(0, 1.5, 0), enemy.Root.Position)
			if AccuracyHelper.RollHit(stats.Accuracy) then
				EnemyService.DamageEnemy(enemy, stats.Damage, player)
				return { hit = true }
			end
			return { hit = false }
		end
	end
end

return CombatService
