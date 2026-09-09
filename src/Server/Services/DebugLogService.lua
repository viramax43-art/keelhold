local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)
local Log = require(ReplicatedStorage.Shared.Util.Log)
local AdminConfig = require(ReplicatedStorage.Shared.Config.AdminConfig)
local Players = game:GetService("Players")

local DebugLogService = {}
local lastSubmit = {}

local function isAdmin(player: Player): boolean
	return table.find(AdminConfig.AdminUserIds or {}, player.UserId) ~= nil
end

function DebugLogService:Init(services)
	local RemoteService = services.RemoteService
	Log.Write("DebugLog", "DebugLogService initialized")

	local getLogs = RemoteService.GetRemote(RemoteNames.GetDebugLogs)
	if getLogs then
		getLogs.OnServerInvoke = function(player)
			if not isAdmin(player) then
				return {}
			end
			return Log.GetLines()
		end
	end

	local submit = RemoteService.GetRemote(RemoteNames.SubmitClientLog)
	if submit and submit:IsA("RemoteEvent") then
		submit.OnServerEvent:Connect(function(player, message)
			local now = os.clock()
			if type(message) == "string"
				and #message < 500
				and now - (lastSubmit[player.UserId] or 0) >= 0.2
			then
				lastSubmit[player.UserId] = now
				Log.Write("Client:" .. player.Name, message)
			end
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastSubmit[player.UserId] = nil
	end)
end

return DebugLogService
