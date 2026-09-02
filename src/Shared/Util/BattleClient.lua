--[[
	BattleClient — единственный клиентский вызов StartBattle.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)

local BattleClient = {}

function BattleClient.StartBattle(): (boolean, any)
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotes then
		return false, "No remotes"
	end
	local fn = remotes:FindFirstChild(RemoteNames.StartBattle)
	if not fn or not fn:IsA("RemoteFunction") then
		return false, "StartBattle missing"
	end
	local ok, result = pcall(function()
		return fn:InvokeServer()
	end)
	if not ok then
		return false, result
	end
	if type(result) == "table" and result.success == false then
		return false, result.error or "failed"
	end
	return true, result
end

return BattleClient
