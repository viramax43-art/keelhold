--[[
	LobbyZoneController — E / ProximityPrompt → меню или StartBattle (один путь).
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MenuBridge = require(ReplicatedStorage.Shared.Util.MenuBridge)
local BattleClient = require(ReplicatedStorage.Shared.Util.BattleClient)
local ClientLoader = require(script.Parent.Parent.Client.ClientLoader)
local ClientLog = require(ReplicatedStorage.Shared.Util.ClientLog)

ClientLoader.EnsureReady()

local ZONE_TABS = {
	Shop = "Магазин",
	ArmorShop = "Броня",
	UnitShop = "Юниты",
	Upgrade = "Прокачка",
	DailyReward = "Награды",
	Promocode = "Промокод",
	Leaderboard = "Лидерборд",
}

local lastBattle = 0
local connected = {}

local function handleZone(zoneType: string)
	if zoneType == "BattleTeleport" then
		if tick() - lastBattle < 2 then
			return
		end
		lastBattle = tick()
		local ok, err = BattleClient.StartBattle()
		ClientLog.Write("Zone", ok and "Battle start" or tostring(err))
		return
	end
	local tab = ZONE_TABS[zoneType]
	if tab then
		MenuBridge.OpenTab(tab)
	end
end

local function hookPrompt(part: BasePart)
	if connected[part] then
		return
	end
	local zoneType = part:GetAttribute("ZoneType")
	if type(zoneType) ~= "string" then
		return
	end
	local prompt = part:FindFirstChild("BridgeDefensePrompt")
	if not prompt or not prompt:IsA("ProximityPrompt") then
		return
	end
	connected[part] = true
	prompt.Triggered:Connect(function(player)
		if player ~= Players.LocalPlayer then
			return
		end
		handleZone(zoneType)
	end)
end

local function scan()
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("BridgeDefenseZone") then
			hookPrompt(d)
		end
	end
end

task.spawn(function()
	for _ = 1, 40 do
		scan()
		task.wait(0.5)
	end
end)
workspace.DescendantAdded:Connect(function(inst)
	if inst:IsA("ProximityPrompt") and inst.Name == "BridgeDefensePrompt" then
		local part = inst.Parent
		if part and part:IsA("BasePart") then
			hookPrompt(part)
		end
	end
end)

-- Nearby E fallback
UserInputService.InputBegan:Connect(function(input, gp)
	if gp or input.KeyCode ~= Enum.KeyCode.E then
		return
	end
	local char = Players.LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local best, bestD = nil, 18
	for part in pairs(connected) do
		if part.Parent then
			local d = (part.Position - hrp.Position).Magnitude
			if d < bestD then
				bestD = d
				best = part
			end
		end
	end
	if best then
		handleZone(best:GetAttribute("ZoneType"))
	end
end)
