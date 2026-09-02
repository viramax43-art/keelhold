local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)
local ClientLog = require(ReplicatedStorage.Shared.Util.ClientLog)

local CombatController = {}
local inBattle = false
local fireRemote = nil

local function getFire()
	if fireRemote then
		return fireRemote
	end
	local r = ReplicatedStorage:FindFirstChild("Remotes")
	fireRemote = r and r:FindFirstChild(RemoteNames.FireWeapon)
	return fireRemote
end

local function tryFire()
	if not inBattle then
		return
	end
	local fn = getFire()
	if not fn then
		return
	end
	local char = Players.LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	pcall(function()
		fn:InvokeServer(nil, hrp and hrp.Position)
	end)
end

function CombatController:Init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
	if not remotes then
		return
	end

	local started = remotes:FindFirstChild(RemoteNames.BattleStarted)
	if started then
		started.OnClientEvent:Connect(function()
			inBattle = true
			ClientLog.Write("Combat", "Battle started — fly + fire")
			local char = Players.LocalPlayer.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.WalkSpeed = 24
			end
		end)
	end
	local ended = remotes:FindFirstChild(RemoteNames.BattleEnded)
	if ended then
		ended.OnClientEvent:Connect(function()
			inBattle = false
		end)
	end

	UserInputService.InputBegan:Connect(function(input, gp)
		if gp then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.Space then
			tryFire()
		end
	end)

	-- Hold-to-fire light loop
	task.spawn(function()
		while true do
			task.wait(0.12)
			if inBattle and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
				tryFire()
			end
		end
	end)
end

return CombatController
