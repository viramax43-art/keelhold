--[[
	LobbyClient — пати UI + кнопка В БОЙ (только StartBattle RF).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ClientLoader = require(script.Parent.Parent.Client.ClientLoader)
local UIController = require(script.Parent.Parent.Client.Controllers.UIController)
local BattleClient = require(ReplicatedStorage.Shared.Util.BattleClient)
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ClientLog = require(ReplicatedStorage.Shared.Util.ClientLog)

ClientLoader.EnsureReady()
UIController.WaitForReady()

local gui = UIController.ScreenGui
if not gui then
	warn("[BridgeDefense] LobbyClient: no ScreenGui")
	return
end

local remotes = ReplicatedStorage:WaitForChild("Remotes")

local partyPanel = UIController.CreatePanel("PartyPanel", UDim2.new(0.32, 0, 0.42, 0))
partyPanel.Position = UDim2.new(0.02, 0, 0.5, 0)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -12, 0, 32)
title.Position = UDim2.new(0, 6, 0, 6)
title.BackgroundTransparency = 1
title.Text = "Пати"
title.TextColor3 = Color3.new(1, 1, 1)
title.Font = Enum.Font.GothamBold
title.TextScaled = true
title.Parent = partyPanel

local membersLabel = Instance.new("TextLabel")
membersLabel.Name = "Members"
membersLabel.Size = UDim2.new(1, -12, 0, 80)
membersLabel.Position = UDim2.new(0, 6, 0, 44)
membersLabel.BackgroundTransparency = 1
membersLabel.Text = "Соло"
membersLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
membersLabel.Font = Enum.Font.Gotham
membersLabel.TextScaled = true
membersLabel.TextXAlignment = Enum.TextXAlignment.Left
membersLabel.TextYAlignment = Enum.TextYAlignment.Top
membersLabel.Parent = partyPanel

local difficulty = "Normal"
local diffBtn = UIController.CreateButton("Сложность: Нормальный", UDim2.new(0.9, 0, 0, 36), function()
	if difficulty == "Normal" then
		difficulty = "Hard"
	elseif difficulty == "Hard" then
		difficulty = "Easy"
	else
		difficulty = "Normal"
	end
	local names = { Easy = "Лёгкий", Normal = "Нормальный", Hard = "Сложный" }
	diffBtn.Text = "Сложность: " .. (names[difficulty] or difficulty)
	local partyFn = remotes:FindFirstChild(RemoteNames.PartyAction)
	if partyFn then
		pcall(function()
			partyFn:InvokeServer("Create")
			partyFn:InvokeServer("SetDifficulty", difficulty)
		end)
	end
end)
diffBtn.Position = UDim2.new(0.05, 0, 0, 140)
diffBtn.Parent = partyPanel

local battleBtn = UIController.CreateButton("В БОЙ!", UDim2.new(0.9, 0, 0, 44), function()
	local partyFn = remotes:FindFirstChild(RemoteNames.PartyAction)
	if partyFn then
		pcall(function()
			partyFn:InvokeServer("Create")
			partyFn:InvokeServer("SetDifficulty", difficulty)
		end)
	end
	local ok, result = BattleClient.StartBattle()
	ClientLog.Write("Lobby", ok and "StartBattle OK" or ("StartBattle fail: " .. tostring(result)))
end)
battleBtn.Position = UDim2.new(0.05, 0, 0, 190)
battleBtn.Parent = partyPanel

local partyUpdated = remotes:FindFirstChild(RemoteNames.PartyUpdated)
if partyUpdated then
	partyUpdated.OnClientEvent:Connect(function(payload)
		if not payload or not payload.Members then
			membersLabel.Text = "Соло"
			return
		end
		local lines = {}
		for _, m in ipairs(payload.Members) do
			table.insert(lines, m.DisplayName or m.Name)
		end
		membersLabel.Text = table.concat(lines, "\n")
	end)
end
