local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)
local Log = require(ReplicatedStorage.Shared.Util.Log)

local DebugLogService = {}

function DebugLogService:Init(services)
	local RemoteService = services.RemoteService
	Log.Write("DebugLog", "DebugLogService initialized")

	local getLogs = RemoteService.GetRemote(RemoteNames.GetDebugLogs)
	if getLogs then
		getLogs.OnServerInvoke = function()
			return Log.GetLines()
		end
	end

	local submit = RemoteService.GetRemote(RemoteNames.SubmitClientLog)
	if submit and submit:IsA("RemoteEvent") then
		submit.OnServerEvent:Connect(function(player, message)
			if type(message) == "string" and #message < 500 then
				Log.Write("Client:" .. player.Name, message)
			end
		end)
	end
end

return DebugLogService
