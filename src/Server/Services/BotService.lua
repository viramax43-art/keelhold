--[[
	BotService — защитники: слот 1 аватар, остальные kit.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MapBind = require(ReplicatedStorage.Shared.Map.MapBind)
local AvatarClone = require(ReplicatedStorage.Shared.Builders.AvatarClone)
local SquadUnitBuilder = require(ReplicatedStorage.Shared.Builders.SquadUnitBuilder)
local CharacterRigBuilder = require(ReplicatedStorage.Shared.Builders.CharacterRigBuilder)
local StatCalculator = require(ReplicatedStorage.Shared.Util.StatCalculator)
local CombatRange = require(ReplicatedStorage.Shared.Util.CombatRange)
local ProfileTemplate = require(ReplicatedStorage.Shared.Util.ProfileTemplate)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local AccuracyHelper = require(ReplicatedStorage.Shared.Util.AccuracyHelper)
local CombatVFX = require(ReplicatedStorage.Shared.Util.CombatVFX)
local Log = require(ReplicatedStorage.Shared.Util.Log)

local BotService = {}
local DataService, WaveService, EnemyService

local function debugCombat(message: string)
	if GameConfig.Battle and GameConfig.Battle.DebugCombatDamage then
		Log.Write("Combat", message, "WARN")
	end
end

function BotService.GetDefenseCFrame(position: Vector3): CFrame
	return MapBind.GetDefenseCFrame(position)
end

local function createKit(slotIndex, position, stats, profile)
	local kit = CharacterRigBuilder.GetKitVariant(slotIndex + 1)
	local weaponType = stats.WeaponType or "Rifle"
	return SquadUnitBuilder.CreateDefenderModel({
		SlotIndex = slotIndex,
		Position = position,
		FacingCFrame = BotService.GetDefenseCFrame(position),
		DisplayName = string.format("Спецназ-%d | %s", slotIndex, weaponType),
		WeaponType = weaponType,
		WeaponTier = stats.WeaponTier,
		CurrentHP = stats.MaxHP,
		MaxHP = stats.MaxHP,
		IsBot = true,
		ModelName = "Bot_Slot" .. slotIndex,
		Parent = workspace:FindFirstChild("Squad") or workspace,
		UniformColor = kit.Uniform,
		VestColor = kit.Vest,
		HelmetColor = kit.Helmet,
	})
end

local function buildRecord(model, slotIndex, stats, hostPlayer)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.MaxHealth = stats.MaxHP
		humanoid.Health = stats.MaxHP
	end
	CharacterRigBuilder.UpdateHealthBar(model, stats.MaxHP, stats.MaxHP)
	return {
		Id = "Bot_" .. slotIndex,
		SlotIndex = slotIndex,
		Model = model,
		Root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"),
		DefensePosition = model:GetPivot().Position,
		CurrentHP = stats.MaxHP,
		MaxHP = stats.MaxHP,
		Armor = stats.Armor,
		Damage = stats.Damage,
		FireRate = stats.FireRate,
		Range = CombatRange.GetDefenseEngageRange(stats.Range),
		Accuracy = stats.Accuracy,
		Spread = stats.Spread or 0.2,
		CritChance = stats.CritChance,
		CritDamage = stats.CritDamage,
		BotDamageMult = stats.BotDamageMult,
		WeaponType = stats.WeaponType,
		LastFire = 0,
		IsBot = true,
		HostPlayer = hostPlayer,
		Alive = true,
	}
end

function BotService.StartBotAI(bot)
	task.spawn(function()
		while bot.Alive and bot.Model and bot.Model.Parent do
			local speedMult = (WaveService and WaveService.GetCombatSpeedMult and WaveService.GetCombatSpeedMult()) or 1
			task.wait(0.15 / math.max(1, speedMult))
			if not EnemyService or not bot.Root or not bot.Root.Parent then
				continue
			end
			speedMult = (WaveService and WaveService.GetCombatSpeedMult and WaveService.GetCombatSpeedMult()) or 1
			local now = os.clock()
			local fireCd = (bot.FireRate or 0.3) / math.max(1, speedMult)
			local standPos = bot.Root.Position
			local range = bot.Range or 200
			local teammates = WaveService and WaveService.GetBots and WaveService.GetBots() or {}
			local target = EnemyService.PickTargetForDefender
					and EnemyService.PickTargetForDefender(standPos, range, bot.LockedTarget, teammates, bot)
				or EnemyService.FindNearestEnemy(standPos, range)
			if not target or not target.Root then
				bot.LockedTarget = nil
				pcall(function()
					if CharacterRigBuilder.ClearAimPose then
						CharacterRigBuilder.ClearAimPose(bot.Model)
					end
				end)
				continue
			end
			bot.LockedTarget = target
			local aim = target.Root.Position + Vector3.new(0, 1.1, 0)
			local look = Vector3.new(aim.X - standPos.X, 0, aim.Z - standPos.Z)
			if look.Magnitude > 0.1 then
				pcall(function()
					CharacterRigBuilder.FaceInPlace(bot.Model, CFrame.lookAt(standPos, standPos + look.Unit))
				end)
			end
			pcall(function()
				CharacterRigBuilder.PlayFireAnimation(bot.Model, aim)
			end)
			if now - (bot.LastFire or 0) < fireCd then
				continue
			end
			bot.LastFire = now

			debugCombat(string.format("BOT_SHOT_ATTEMPT bot=%s target=%s", tostring(bot.Id), tostring(target.Id)))

			local origin = CombatVFX.GetMuzzleWorldPosition(bot.Model) or (bot.Root.Position + Vector3.new(0, 1.2, 0))
			local distance = (aim - origin).Magnitude
			local shotDistance = math.min(distance, range)
			if distance > range * 1.15 then
				debugCombat(string.format("BOT_OUT_OF_RANGE bot=%s distance=%.1f range=%.1f", tostring(bot.Id), distance, range))
			end

			local losClear, losPos = true, aim
			local losOk, losA, losB = pcall(function()
				return CombatVFX.HasClearLos(origin, aim, range, bot.Model, target.Model)
			end)
			if losOk then
				losClear, losPos = losA, losB
			else
				losClear = true
			end

			local hit, chance, roll = false, 0, 1
			if losClear then
				hit, chance, roll = AccuracyHelper.RollShot({
					baseAccuracy = bot.Accuracy,
					distance = shotDistance,
					maxRange = range,
					spread = bot.Spread or 0.2,
					movingShooter = false,
					movingTarget = target.State == "Moving",
				})
			end
			debugCombat(string.format(
				"BOT_HIT_ROLL bot=%s target=%s distance=%.2f range=%.2f accuracy=%.3f chance=%.3f roll=%.3f los=%s hit=%s",
				tostring(bot.Id),
				tostring(target.Id),
				shotDistance,
				range,
				bot.Accuracy or -1,
				chance,
				roll,
				tostring(losClear),
				tostring(hit)
			))

			if GameConfig.Battle and GameConfig.Battle.ForceBotHitsForTest then
				hit = true
			end

			if hit then
				local damage = (bot.Damage or 10) * (bot.BotDamageMult or 1)
				if math.random() < (bot.CritChance or 0) then
					damage *= math.max(1.5, bot.CritDamage or 1.5)
				end
				local beforeHP = target.CurrentHP
				local targetId = target.Id or "unknown"
				debugCombat(string.format(
					"BOT_DAMAGE_CALL bot=%s target=%s damage=%.2f hpBefore=%.2f",
					tostring(bot.Id),
					tostring(targetId),
					damage,
					tonumber(beforeHP) or -1
				))
				local ok, result = EnemyService.DamageEnemy(target, damage, bot.HostPlayer)
				if not ok then
					debugCombat(string.format(
						"BOT_DAMAGE_FAILED bot=%s target=%s reason=%s",
						tostring(bot.Id),
						tostring(targetId),
						tostring(result)
					))
				else
					debugCombat(string.format(
						"BOT_DAMAGE_RESULT bot=%s target=%s hpAfter=%.2f applied=%s",
						tostring(bot.Id),
						tostring(targetId),
						tonumber(target.CurrentHP) or -1,
						tostring(result)
					))
				end
				pcall(function()
					CombatVFX.PlayMuzzle(origin, aim, bot.Model, bot.WeaponType)
				end)
			else
				pcall(function()
					CombatVFX.PlayMiss(origin, if losClear then aim else losPos, bot.Model, bot.WeaponType, range)
				end)
			end
		end
	end)
end

function BotService.HealAllBots()
	local bots = WaveService and WaveService.GetBots and WaveService.GetBots() or {}
	for _, bot in ipairs(bots) do
		if bot.Alive and bot.Model and bot.Model.Parent then
			bot.CurrentHP = bot.MaxHP or bot.CurrentHP
			CharacterRigBuilder.UpdateHealthBar(bot.Model, bot.CurrentHP, bot.MaxHP)
			local hum = bot.Model:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.MaxHealth = bot.MaxHP
				hum.Health = bot.MaxHP
			end
		end
	end
end

function BotService.DamageBot(bot, amount: number)
	if not bot then
		return false, "bot_nil"
	end
	if bot.Alive ~= true then
		return false, "bot_not_alive"
	end

	local beforeHP = tonumber(bot.CurrentHP) or 0
	local maxHP = tonumber(bot.MaxHP) or beforeHP
	if beforeHP <= 0 then
		return false, "bot_hp_empty"
	end

	local DamageFormula = require(ReplicatedStorage.Shared.Util.DamageFormula)
	local rawDamage = math.max(0, tonumber(amount) or 0)
	local mitigated = DamageFormula.Mitigate(rawDamage, bot.Armor)
	local appliedDamage = math.min(beforeHP, math.max(1, mitigated))
	bot.CurrentHP = math.max(0, beforeHP - appliedDamage)

	if bot.Model and bot.Model.Parent then
		CharacterRigBuilder.UpdateHealthBar(bot.Model, bot.CurrentHP, maxHP)
		local humanoid = bot.Model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.MaxHealth = maxHP
			humanoid.Health = bot.CurrentHP
		end
	end

	debugCombat(string.format(
		"BOT_HP_CHANGED id=%s before=%.2f damage=%.2f after=%.2f",
		tostring(bot.Id),
		beforeHP,
		appliedDamage,
		bot.CurrentHP
	))

	if bot.CurrentHP <= 0 then
		bot.Alive = false
		Log.Write("Wave", "Defender died: " .. tostring(bot.Id))
		if bot.Model then
			bot.Model:Destroy()
		end
		if WaveService and WaveService.OnDefenderDied then
			WaveService.OnDefenderDied(bot)
		end
	end

	return true, appliedDamage
end

function BotService.SpawnBots(hostPlayer: Player, defensePositions: { Vector3 })
	local profile = DataService and DataService.GetProfile(hostPlayer)
	if not profile then
		profile = Util.ReconcileProfile(nil, ProfileTemplate)
	end
	local statsProfile = profile
	if GameConfig.BotsInheritHostUpgrades == false then
		statsProfile = Util.DeepCopy(profile)
		statsProfile.Upgrades = Util.DeepCopy(ProfileTemplate.Upgrades)
	end

	local botCount = GameConfig.DefenseBotCount or 4
	local squad = workspace:FindFirstChild("Squad")
	if not squad then
		squad = Instance.new("Folder")
		squad.Name = "Squad"
		squad.Parent = workspace
	end

	local spawnedBots = {}
	for slotIndex = 1, botCount do
		local pos = defensePositions[slotIndex] or defensePositions[1] or Vector3.new(0, 5, 0)
		local stats = StatCalculator.BuildCombatStats(statsProfile, slotIndex)

		local model = nil
		local skin = "kit"
		if slotIndex == 1 then
			local facing = BotService.GetDefenseCFrame(pos)
			local clone = AvatarClone.Create(hostPlayer, slotIndex, facing, stats)
			if clone then
				model = clone
				skin = "avatar"
			else
				Log.Write("Bot", "Avatar clone failed for slot 1, using kit fallback", "WARN")
				model = createKit(slotIndex, pos, stats, profile)
			end
		else
			model = createKit(slotIndex, pos, stats, profile)
		end

		if model then
			-- Для аватара facing уже с HipHeight; не сбрасываем PivotTo на «голую» точку слота
			local facing = model:GetPivot()
			if not model:GetAttribute("UsesPlayerSkin") then
				facing = BotService.GetDefenseCFrame(pos)
			end
			CharacterRigBuilder.LockStanding(model, facing)
			local bot = buildRecord(model, slotIndex, stats, hostPlayer)
			bot.DefensePosition = facing.Position
			table.insert(spawnedBots, bot)
			BotService.StartBotAI(bot)
			if WaveService and WaveService.RegisterBot then
				WaveService.RegisterBot(bot)
			else
				Log.Write("Bot", "WaveService not ready for slot " .. slotIndex, "WARN")
			end
			Log.Write("Bot", string.format("Bot slot %d weapon=%s skin=%s", slotIndex, stats.WeaponType, skin))
		end
	end
	Log.Write("Bot", "Spawned " .. #spawnedBots .. "/" .. botCount .. " defense bots")
	return spawnedBots
end

function BotService:Init(services)
	DataService = services.DataService
	WaveService = services.WaveService
	EnemyService = services.EnemyService
end

return BotService
