--[[
	WaveService — цикл волн, wipe, возврат в лобби.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MapBind = require(ReplicatedStorage.Shared.Map.MapBind)
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)
local Log = require(ReplicatedStorage.Shared.Util.Log)

local WaveService = {}
local battleState = nil
local combatSpeedMult = 1
local TeleportServiceRef = nil
local DataService, BotService, EnemyService, RewardService, RemoteService, GlobalConfigService, LeaderboardServiceRef
local invisibleCollisionBackup = {}

function WaveService.BindTeleportService(svc)
	TeleportServiceRef = svc
end

function WaveService.GetCombatSpeedMult(): number
	return combatSpeedMult
end

function WaveService.SetCombatSpeedMult(mult: number)
	combatSpeedMult = math.clamp(tonumber(mult) or 1, 1, 20)
	workspace:SetAttribute("CombatSpeedMult", combatSpeedMult)
end

function WaveService.ToggleCombatSpeed(): number
	if combatSpeedMult >= 10 then
		WaveService.SetCombatSpeedMult(1)
	else
		WaveService.SetCombatSpeedMult(10)
	end
	return combatSpeedMult
end

function WaveService.IsBattleActive(): boolean
	return battleState ~= nil and battleState.Active == true
end

function WaveService.IsBattleBusy(): boolean
	return battleState ~= nil
end

-- Можно ли ещё спавнить врагов для этой волны (блокирует хвост спавна после клира)
function WaveService.CanSpawnForWave(wave: number): boolean
	return battleState ~= nil
		and battleState.Active == true
		and battleState.WaveClearing ~= true
		and battleState.Wiping ~= true
		and battleState.Wave == wave
end

function WaveService.GetCurrentWave(): number?
	return battleState and battleState.Wave or nil
end

function WaveService.GetBots()
	return battleState and battleState.Bots or {}
end

function WaveService.RegisterBot(bot)
	if not battleState then
		return
	end
	table.insert(battleState.Bots, bot)
end

local function disableInvisibleWorldColliders()
	table.clear(invisibleCollisionBackup)
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("BasePart") and d.CanCollide then
			local model = d:FindFirstAncestorOfClass("Model")
			if model and model:FindFirstChildOfClass("Humanoid") then
				continue
			end
			local n = string.lower(d.Name)
			local invisible = d.Transparency >= 0.35
				or string.find(n, "invis", 1, true)
				or string.find(n, "barrier", 1, true)
				or string.find(n, "nocollide", 1, true)
				or string.find(n, "collision", 1, true)
				or string.find(n, "blocker", 1, true)
				or (string.find(n, "wall", 1, true) and d.Transparency > 0.2)
			if invisible then
				table.insert(invisibleCollisionBackup, {
					Part = d,
					CanCollide = d.CanCollide,
					Transparency = d.Transparency,
				})
				d.CanCollide = false
				-- Скрываем полупрозрачные барьеры полностью
				if d.Transparency > 0.05 and d.Transparency < 1 then
					d.Transparency = 1
				end
			end
		end
	end
	Log.Write("Wave", "Disabled invisible colliders: " .. tostring(#invisibleCollisionBackup))
end

local function restoreInvisibleWorldColliders()
	for _, entry in ipairs(invisibleCollisionBackup) do
		local d = entry.Part or entry
		if d and d.Parent then
			d.CanCollide = if type(entry) == "table" and entry.CanCollide ~= nil then entry.CanCollide else true
			if type(entry) == "table" and entry.Transparency ~= nil then
				d.Transparency = entry.Transparency
			end
		end
	end
	table.clear(invisibleCollisionBackup)
end

local function defensePositions(): { Vector3 }
	local folder = workspace:FindFirstChild("MapPoints")
	local names = GameConfig.MapPointNames.DefenseSpawns or {}
	local positions = {}
	for i, name in ipairs(names) do
		local p = folder and folder:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			positions[i] = p.Position
		else
			positions[i] = Vector3.new((i - 2.5) * 5, 5, 0)
		end
	end
	return positions
end

local function alivePlayers(list)
	local out = {}
	for _, p in ipairs(list or {}) do
		if p and p.Parent then
			table.insert(out, p)
		end
	end
	return out
end

local function anyBotAlive()
	if not battleState then
		return false
	end
	for _, b in ipairs(battleState.Bots) do
		if b.Alive then
			return true
		end
	end
	return false
end

local function fireWaveUpdated()
	if not battleState or not RemoteService then
		return
	end
	local enemiesDisplay = EnemyService.GetDisplayEnemyCount and EnemyService.GetDisplayEnemyCount()
		or EnemyService.GetAliveCount()
	RemoteService.FireAll(RemoteNames.WaveUpdated, {
		Wave = battleState.Wave,
		EnemiesAlive = enemiesDisplay,
		BotsAlive = (function()
			local n = 0
			for _, b in ipairs(battleState.Bots) do
				if b.Alive then
					n += 1
				end
			end
			return n
		end)(),
		InMission = battleState.Active == true,
	})
end

function WaveService.NotifyWaveHud()
	fireWaveUpdated()
end

function WaveService.OnEnemyDied()
	if not battleState or not battleState.Active then
		return
	end
	fireWaveUpdated()
	if battleState.SpawningDone
		and not battleState.WaveClearing
		and not battleState.ClearHandled
		and EnemyService.GetAliveCount() <= 0
	then
		WaveService.OnWaveCleared()
	end
end

function WaveService.OnWaveSpawningFinished(wave: number)
	if not battleState
		or not battleState.Active
		or battleState.Wave ~= wave
		or battleState.WaveClearing
		or battleState.ClearHandled
	then
		return
	end
	battleState.SpawningDone = true
	fireWaveUpdated()
	if EnemyService.GetAliveCount() <= 0 then
		WaveService.OnWaveCleared()
	end
end

function WaveService.OnDefenderDied(_bot)
	if not battleState or not battleState.Active then
		return
	end
	fireWaveUpdated()
	if not anyBotAlive() then
		Log.Write("Wave", "All defenders dead — squad wiped")
		WaveService.OnWipe()
	end
end

function WaveService.OnWaveCleared()
	if not battleState or not battleState.Active then
		return
	end
	if battleState.ClearHandled then
		return
	end
	battleState.WaveClearing = true
	battleState.ClearHandled = true
	-- Останавливаем доспавн хвоста прошлой волны
	pcall(function()
		if EnemyService.AbortRemainingSpawns then
			EnemyService.AbortRemainingSpawns()
		end
	end)
	local wave = battleState.Wave
	local stateAtClear = battleState
	local players = alivePlayers(battleState.Players)
	local earnings = RewardService.GrantWaveClear(players, wave) or {}
	for _, p in ipairs(players) do
		local e = earnings[p.UserId] or { gold = 0, xp = 0 }
		RemoteService.FireClient(p, RemoteNames.WaveResult, {
			success = true,
			wave = wave,
			goldEarned = e.gold,
			xpEarned = e.xp,
		})
	end

	local cfg = GlobalConfigService and GlobalConfigService.GetWaveMode and GlobalConfigService.GetWaveMode()
		or { Endless = GameConfig.Waves.DefaultEndless, FixedCount = GameConfig.Waves.DefaultFixedCount }
	local continueBattle = cfg.Endless or wave < (cfg.FixedCount or 20)
	local delay = GameConfig.Waves.InterWaveDelay or 8
	if continueBattle then
		Log.Write("Wave", "next wave in " .. delay .. "s")
		task.delay(delay, function()
			if battleState == stateAtClear and battleState.Active and battleState.Wave == wave then
				WaveService.BeginWave(wave + 1)
			end
		end)
	else
		task.delay(2.5, function()
			if battleState == stateAtClear and battleState.Active and battleState.Wave == wave then
				WaveService.EndBattle(true)
			end
		end)
	end
end

function WaveService.OnWipe()
	if not battleState or not battleState.Active then
		return
	end
	if battleState.WaveClearing or battleState.ClearHandled or battleState.WipeHandled then
		return
	end
	battleState.WipeHandled = true
	-- Сразу останавливаем бой: иначе враги ещё долго «живут» после таблички поражения
	battleState.Active = false
	battleState.Wiping = true
	local wipingState = battleState
	local wave = battleState.Wave
	local players = alivePlayers(battleState.Players)
	Log.Write("Wave", string.format("Squad wiped on wave %d, return lobby soon (players=%d)", wave, #players))

	-- Убиваем AI врагов сразу
	pcall(function()
		EnemyService.Clear()
	end)
	for _, bot in ipairs(battleState.Bots) do
		bot.Alive = false
	end

	local earnings = RewardService.GrantDefeatConsolation(players, wave) or {}
	for _, p in ipairs(players) do
		local e = earnings[p.UserId] or { gold = 0, xp = 0 }
		RemoteService.FireClient(p, RemoteNames.WaveResult, {
			success = false,
			wave = wave,
			goldEarned = e.gold,
			xpEarned = e.xp,
		})
	end
	task.delay(1.8, function()
		if battleState == wipingState then
			WaveService.EndBattle(false)
		end
	end)
end

function WaveService.EndBattle(won: boolean)
	if not battleState then
		return
	end
	local endingState = battleState
	local players = alivePlayers(endingState.Players)
	Log.Write("Wave", string.format("Returning %d player(s) to lobby after wave %s", #players, tostring(endingState.Wave)))
	pcall(function()
		EnemyService.Clear()
	end)
	local squad = workspace:FindFirstChild("Squad")
	if squad then
		squad:ClearAllChildren()
	end
	restoreInvisibleWorldColliders()
	WaveService.SetCombatSpeedMult(1)
	if RemoteService then
		RemoteService.FireAll(RemoteNames.BattleEnded, { won = won })
	end
	for _, connection in ipairs(endingState.CharacterConnections or {}) do
		connection:Disconnect()
	end
	battleState = nil
	task.defer(function()
		if LeaderboardServiceRef and LeaderboardServiceRef.PushPlayer then
			for _, p in ipairs(players) do
				pcall(function()
					LeaderboardServiceRef.PushPlayer(p)
				end)
			end
		end
		if TeleportServiceRef and TeleportServiceRef.ReturnPlayers then
			TeleportServiceRef.ReturnPlayers(players)
		else
			Log.Write("Wave", "TeleportService missing — local lobby restore fallback", "WARN")
			for _, p in ipairs(players) do
				local char = p.Character
				if char then
					char:SetAttribute("Spectator", false)
				end
			end
		end
	end)
end

function WaveService.BeginWave(wave: number)
	if not battleState or not battleState.Active or battleState.Wiping then
		return
	end
	battleState.Wave = wave
	battleState.SpawningDone = false
	battleState.WaveClearing = false
	battleState.ClearHandled = false
	if BotService and BotService.HealAllBots then
		BotService.HealAllBots()
	end
	RewardService.ClearWaveStats()
	RewardService.SetCurrentWave(wave)
	local diff = GameConfig.Difficulties[battleState.Difficulty or "Normal"]
	local mult = (diff and diff.EnemyStatMultiplier) or 1
	local startDelay = (GameConfig.Battle and GameConfig.Battle.WaveStartDelay) or 0.2
	-- Фиксируем номер волны для отложенных колбэков (иначе таймер прошлой волны клирит следующую)
	local waveAtStart = wave
	task.delay(startDelay, function()
		if not battleState or not battleState.Active or battleState.Wave ~= waveAtStart then
			return
		end
		EnemyService.SpawnWave(waveAtStart, mult)
		fireWaveUpdated()
	end)
end

function WaveService.StartBattle(teleportData)
	-- A wiping/ending session still owns delayed callbacks and world state.
	-- Do not overwrite it until EndBattle performs the complete teardown.
	if battleState then
		return
	end
	MapBind.EnsureBattlePoints()

	local players = {}
	if teleportData and teleportData.Members then
		for _, m in ipairs(teleportData.Members) do
			local p = Players:GetPlayerByUserId(m.UserId)
			if p then
				table.insert(players, p)
			end
		end
	end
	if #players == 0 then
		players = Players:GetPlayers()
	end
	local deadline = os.clock() + 8
	while #players == 0 and os.clock() < deadline do
		task.wait(0.2)
		players = Players:GetPlayers()
	end
	if #players == 0 then
		Log.Write("Wave", "StartBattle: no players, aborting", "WARN")
		return
	end

	-- Не начинаем бой, пока профили не готовы (защита от пустых данных)
	local profileDeadline = os.clock() + 12
	while os.clock() < profileDeadline do
		local allReady = true
		for _, p in ipairs(players) do
			if not p.Parent or p:GetAttribute("BD_ProfileReady") ~= true then
				allReady = false
				break
			end
		end
		if allReady then
			break
		end
		task.wait(0.2)
	end
	for _, p in ipairs(players) do
		if not p.Parent or p:GetAttribute("BD_ProfileReady") ~= true then
			Log.Write("Wave", "StartBattle: profile not ready for " .. p.Name .. ", aborting", "WARN")
			return
		end
	end

	local startCheckpoint = 0
	for _, m in ipairs((teleportData and teleportData.Members) or {}) do
		startCheckpoint = math.max(startCheckpoint, m.LastCheckpoint or 0)
	end

	battleState = {
		Active = true,
		Wiping = false,
		WaveClearing = false,
		ClearHandled = false,
		WipeHandled = false,
		SpawningDone = false,
		Players = players,
		Bots = {},
		Wave = math.max(1, startCheckpoint),
		Difficulty = (teleportData and teleportData.Difficulty) or "Normal",
		CharacterConnections = {},
	}

	local function prepareSpectator(player: Player)
		local function apply(char)
			local hum = char:WaitForChild("Humanoid", 5)
			local hrp = char:WaitForChild("HumanoidRootPart", 5)
			if not hum or not hrp then
				return
			end
			hum.MaxHealth = 1e9
			hum.Health = 1e9
			hum.PlatformStand = false
			hrp.Anchored = false
			-- Коллизии оставляем: игрок упирается в мост, но невидимые блоки отключены отдельно
			for _, d in ipairs(char:GetDescendants()) do
				if d:IsA("BasePart") then
					d.CanQuery = false
					if d.Name == "HumanoidRootPart" then
						d.CanCollide = true
					end
				end
			end
			char:SetAttribute("Spectator", true)
			-- На настиле моста, чуть позади линии обороны (не world-offset — иначе падают с моста)
			local stand = MapBind.GetSpectatorStandCFrame()
			if stand then
				hrp.AssemblyLinearVelocity = Vector3.zero
				hrp.AssemblyAngularVelocity = Vector3.zero
				hrp.CFrame = stand
			end
		end
		if player.Character then
			apply(player.Character)
		end
		local connection = player.CharacterAdded:Connect(function(character)
			if battleState and battleState.Active and table.find(battleState.Players, player) then
				apply(character)
			end
		end)
		table.insert(battleState.CharacterConnections, connection)
	end

	for _, p in ipairs(players) do
		prepareSpectator(p)
	end
	-- Убираем полупрозрачные/невидимые барьеры на время миссии
	disableInvisibleWorldColliders()

	RewardService.SetBattleContext({
		friendCount = teleportData and teleportData.FriendCount or 0,
		difficulty = battleState.Difficulty,
	})

	Log.Write("Wave", string.format("StartBattle players=%d checkpoint=%d", #players, startCheckpoint))

	local host = players[1]
	BotService.SpawnBots(host, defensePositions())
	local startingState = battleState
	task.delay(0.8, function()
		if battleState ~= startingState or not battleState.Active then
			return
		end
		Log.Write("Wave", "Defenders ready: " .. tostring(GameConfig.DefenseBotCount) .. " bots (players immortal observers)")
		if RemoteService then
			RemoteService.FireAll(RemoteNames.BattleStarted, { wave = battleState.Wave })
		end
		WaveService.BeginWave(math.max(1, startCheckpoint > 0 and startCheckpoint or 1))
	end)
end

function WaveService:Init(services)
	DataService = services.DataService
	BotService = services.BotService
	EnemyService = services.EnemyService
	RewardService = services.RewardService
	RemoteService = services.RemoteService
	GlobalConfigService = services.GlobalConfigService
	LeaderboardServiceRef = services.LeaderboardService

	WaveService.SetCombatSpeedMult(1)

	local toggleSpeed = RemoteService.GetRemote(RemoteNames.ToggleWaveSpeed)
	if toggleSpeed and toggleSpeed:IsA("RemoteFunction") then
		toggleSpeed.OnServerInvoke = function(_player)
			local mult = WaveService.ToggleCombatSpeed()
			return { success = true, mult = mult }
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		if not battleState then
			return
		end
		for i = #battleState.Players, 1, -1 do
			if battleState.Players[i] == player then
				table.remove(battleState.Players, i)
			end
		end
		if #battleState.Players > 0 then
			local newHost = battleState.Players[1]
			for _, bot in ipairs(battleState.Bots) do
				if bot.HostPlayer == player then
					bot.HostPlayer = newHost
				end
			end
		end
		if #alivePlayers(battleState.Players) == 0 and battleState.Active then
			Log.Write("Wave", "ReturnPlayersToLobby: no players", "WARN")
			battleState.Active = false
			WaveService.EndBattle(false)
		end
	end)
end

return WaveService
