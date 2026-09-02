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
local TeleportServiceRef = nil
local DataService, BotService, EnemyService, RewardService, RemoteService, GlobalConfigService

function WaveService.BindTeleportService(svc)
	TeleportServiceRef = svc
end

function WaveService.IsBattleActive(): boolean
	return battleState ~= nil and battleState.Active == true
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
	RemoteService.FireAll(RemoteNames.WaveUpdated, {
		Wave = battleState.Wave,
		EnemiesAlive = EnemyService.GetAliveCount(),
		BotsAlive = (function()
			local n = 0
			for _, b in ipairs(battleState.Bots) do
				if b.Alive then
					n += 1
				end
			end
			return n
		end)(),
	})
end

function WaveService.OnEnemyDied()
	if not battleState or not battleState.Active then
		return
	end
	fireWaveUpdated()
	if EnemyService.GetAliveCount() <= 0 and battleState.SpawningDone then
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
	local wave = battleState.Wave
	local players = alivePlayers(battleState.Players)
	RewardService.GrantWaveClear(players, wave)
	RemoteService.FireAll(RemoteNames.WaveResult, { success = true, wave = wave })

	local cfg = GlobalConfigService and GlobalConfigService.GetWaveMode and GlobalConfigService.GetWaveMode()
		or { Endless = GameConfig.Waves.DefaultEndless, FixedCount = GameConfig.Waves.DefaultFixedCount }
	local continueBattle = cfg.Endless or wave < (cfg.FixedCount or 20)
	local delay = GameConfig.Waves.InterWaveDelay or 8
	if continueBattle then
		Log.Write("Wave", "next wave in " .. delay .. "s")
		task.delay(delay, function()
			if battleState and battleState.Active then
				WaveService.BeginWave(wave + 1)
			end
		end)
	else
		task.delay(2.5, function()
			WaveService.EndBattle(true)
		end)
	end
end

function WaveService.OnWipe()
	if not battleState or not battleState.Active then
		return
	end
	battleState.Active = false
	local wave = battleState.Wave
	local players = alivePlayers(battleState.Players)
	Log.Write("Wave", string.format("Squad wiped on wave %d, return lobby in 2s (players=%d)", wave, #players))
	RewardService.GrantDefeatConsolation(players, wave)
	RemoteService.FireAll(RemoteNames.WaveResult, { success = false, wave = wave })
	task.delay(2.5, function()
		WaveService.EndBattle(false)
	end)
end

function WaveService.EndBattle(won: boolean)
	local players = battleState and alivePlayers(battleState.Players) or {}
	Log.Write("Wave", string.format("Returning %d player(s) to lobby after wave %s", #players, tostring(battleState and battleState.Wave)))
	EnemyService.Clear()
	local squad = workspace:FindFirstChild("Squad")
	if squad then
		squad:ClearAllChildren()
	end
	if RemoteService then
		RemoteService.FireAll(RemoteNames.BattleEnded, { won = won })
	end
	battleState = nil
	if TeleportServiceRef and TeleportServiceRef.ReturnPlayers then
		TeleportServiceRef.ReturnPlayers(players)
	end
end

function WaveService.BeginWave(wave: number)
	if not battleState then
		return
	end
	battleState.Wave = wave
	battleState.SpawningDone = false
	RewardService.ClearWaveStats()
	local diff = GameConfig.Difficulties[battleState.Difficulty or "Normal"]
	local mult = (diff and diff.EnemyStatMultiplier) or 1
	local startDelay = (GameConfig.Battle and GameConfig.Battle.WaveStartDelay) or 0.2
	task.delay(startDelay, function()
		if not battleState or not battleState.Active then
			return
		end
		EnemyService.SpawnWave(wave, mult)
		-- mark spawning done after estimated spawn window
		local count = require(ReplicatedStorage.Shared.Util.WaveScaling).EnemyCount(wave)
		local interval = (GameConfig.Battle and GameConfig.Battle.EnemySpawnInterval) or 0.35
		task.delay(count * interval + 0.5, function()
			if battleState then
				battleState.SpawningDone = true
				if EnemyService.GetAliveCount() <= 0 then
					WaveService.OnWaveCleared()
				end
			end
		end)
		fireWaveUpdated()
	end)
end

function WaveService.StartBattle(teleportData)
	if battleState and battleState.Active then
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
	-- wait briefly for party
	local deadline = os.clock() + 8
	while #players == 0 and os.clock() < deadline do
		task.wait(0.2)
		players = Players:GetPlayers()
	end
	if #players == 0 then
		Log.Write("Wave", "StartBattle: no players, aborting", "WARN")
		return
	end

	local startCheckpoint = 0
	for _, m in ipairs((teleportData and teleportData.Members) or {}) do
		startCheckpoint = math.max(startCheckpoint, m.LastCheckpoint or 0)
	end

	battleState = {
		Active = true,
		Players = players,
		Bots = {},
		Wave = math.max(1, startCheckpoint),
		Difficulty = (teleportData and teleportData.Difficulty) or "Normal",
		SpawningDone = false,
	}

	RewardService.SetBattleContext({
		friendCount = teleportData and teleportData.FriendCount or 0,
		difficulty = battleState.Difficulty,
	})

	Log.Write("Wave", string.format("StartBattle players=%d checkpoint=%d", #players, startCheckpoint))

	local host = players[1]
	BotService.SpawnBots(host, defensePositions())
	task.delay(0.8, function()
		Log.Write("Wave", "Defenders ready: " .. tostring(GameConfig.DefenseBotCount) .. " bots (players immortal fly)")
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

	Players.PlayerRemoving:Connect(function(player)
		if not battleState then
			return
		end
		for i = #battleState.Players, 1, -1 do
			if battleState.Players[i] == player then
				table.remove(battleState.Players, i)
			end
		end
		if #alivePlayers(battleState.Players) == 0 and battleState.Active then
			Log.Write("Wave", "ReturnPlayersToLobby: no players", "WARN")
			battleState.Active = false
			EnemyService.Clear()
			battleState = nil
		end
	end)
end

return WaveService
