--[[
	CombatService — стрельба игрока (FireWeapon) по targetId.
]]

local Players = game:GetService("Players")
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
local lastWeaponType = {}

function CombatService:Init(services)
	DataService = services.DataService
	EnemyService = services.EnemyService
	RemoteService = services.RemoteService

	Players.PlayerRemoving:Connect(function(player)
		lastFire[player.UserId] = nil
		lastWeaponType[player.UserId] = nil
	end)

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

			if lastWeaponType[uid] ~= stats.WeaponType then
				lastFire[uid] = 0
				lastWeaponType[uid] = stats.WeaponType
			end

			local cooldown = stats.FireRate or 0.2
			if lastFire[uid] and now - lastFire[uid] < cooldown * 0.9 then
				return { hit = false, reason = "cooldown" }
			end
			lastFire[uid] = now

			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local from = (typeof(origin) == "Vector3" and origin) or (hrp and hrp.Position) or Vector3.zero
			local range = CombatRange.GetPlayerEngageRange()
			local maxHit = GameConfig.MaxHitDistance or 500

			local enemy = nil
			if targetId ~= nil and targetId ~= "" then
				enemy = EnemyService.FindEnemyById(tostring(targetId))
				if enemy and enemy.Root then
					local dist = (enemy.Root.Position - from).Magnitude
					if dist > maxHit or dist > range then
						enemy = nil
					end
				else
					enemy = nil
				end
			end

			if not enemy or not enemy.Alive then
				enemy = EnemyService.FindNearestEnemy(from, range)
			end

			if not enemy or not enemy.Root then
				return { hit = false }
			end

			local dist = (enemy.Root.Position - from).Magnitude
			if dist > maxHit then
				return { hit = false }
			end

			CombatVFX.PlayMuzzle(from + Vector3.new(0, 1.5, 0), enemy.Root.Position)
			if AccuracyHelper.RollHit(stats.Accuracy) then
				EnemyService.DamageEnemy(enemy, stats.Damage, player)
				return { hit = true, targetId = enemy.Id }
			end
			return { hit = false, targetId = enemy.Id }
		end
	end
end

return CombatService
