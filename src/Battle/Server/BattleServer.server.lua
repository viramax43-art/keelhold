--[[
	Battle place entry: JoinData → WaveService.StartBattle
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MapBind = require(ReplicatedStorage.Shared.Map.MapBind)
local Log = require(ReplicatedStorage.Shared.Util.Log)

local readyDeadline = os.clock() + 20
while game:GetAttribute("BridgeDefenseServerReady") ~= true and os.clock() < readyDeadline do
	task.wait(0.1)
end
if game:GetAttribute("BridgeDefenseServerReady") ~= true then
	Log.Write("BattlePlace", "Server services did not initialize in time", "ERROR")
	return
end
local WaveService = require(game:GetService("ServerScriptService").Server.Services.WaveService)

MapBind.EnsureBattlePoints()

local started = false
local function tryStart(player: Player)
	if started then
		return
	end
	local join = player:GetJoinData()
	local teleportData = join and join.TeleportData
	if not teleportData then
		-- Studio play on battle place
		teleportData = {
			Difficulty = "Normal",
			FriendCount = 0,
			Members = { { UserId = player.UserId, Name = player.Name, LastCheckpoint = 0 } },
		}
	end
	started = true
	Log.Write("BattlePlace", "Starting wave battle")
	WaveService.StartBattle(teleportData)
end

Players.PlayerAdded:Connect(function(player)
	task.delay(1, function()
		tryStart(player)
	end)
end)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		tryStart(p)
	end)
end
