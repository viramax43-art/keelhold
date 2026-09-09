--[[
	LobbyClient — кнопка Пати + попап приглашения (модалка через MenuBridge).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ClientLoader = require(script.Parent.Parent.Client.ClientLoader)
local UIController = require(script.Parent.Parent.Client.Controllers.UIController)
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)
local MenuBridge = require(ReplicatedStorage.Shared.Util.MenuBridge)

ClientLoader.EnsureReady()
UIController.WaitForReady()

local gui = UIController.ScreenGui
if not gui then
	warn("[BridgeDefense] LobbyClient: no ScreenGui")
	return
end

local remotes = ReplicatedStorage:WaitForChild("Remotes")
-- Кнопка «Пати» теперь в HUD (под окном Gold/XP). Огромную боковую кнопку убрали.

-- Shift в лобби: скорость x3
do
	local UserInputService = game:GetService("UserInputService")
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	local baseSpeed = 16
	local boosting = false

	local function getHum()
		local char = player.Character
		return char and char:FindFirstChildOfClass("Humanoid")
	end

	local function applyBoost(on)
		local hum = getHum()
		if not hum then
			return
		end
		if on and not boosting then
			baseSpeed = hum.WalkSpeed > 0 and hum.WalkSpeed or 16
			hum.WalkSpeed = baseSpeed * 3
			boosting = true
		elseif not on and boosting then
			hum.WalkSpeed = baseSpeed
			boosting = false
		end
	end

	UserInputService.InputBegan:Connect(function(input, gp)
		if gp then
			return
		end
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			local char = player.Character
			if char and char:GetAttribute("Spectator") then
				return
			end
			applyBoost(true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			applyBoost(false)
		end
	end)
	player.CharacterAdded:Connect(function()
		boosting = false
	end)
end

local inviteEvt = remotes:FindFirstChild(RemoteNames.PartyInvite)
if inviteEvt then
	inviteEvt.OnClientEvent:Connect(function(inv)
		if not inv then
			return
		end
		local existing = gui:FindFirstChild("InvitePopup")
		if existing then
			existing:Destroy()
		end
		local pop = UIController.CreatePanel("InvitePopup", UDim2.new(0.26, 0, 0.24, 0))
		pop.AnchorPoint = Vector2.new(0.5, 0)
		pop.Position = UDim2.new(0.5, 0, 0.35, 0)
		local t = Instance.new("TextLabel")
		t.Size = UDim2.new(1, -12, 0, 40)
		t.Position = UDim2.new(0, 6, 0, 8)
		t.BackgroundTransparency = 1
		t.Text = tostring(inv.LeaderName) .. " зовёт в команду!"
		t.TextColor3 = Color3.new(1, 1, 1)
		t.Font = Enum.Font.GothamBold
		t.TextScaled = true
		t.Parent = pop
		local acc = UIController.CreateButton("Принять", UDim2.new(0.42, 0, 0, 36), function()
			local partyFn = remotes:FindFirstChild(RemoteNames.PartyAction)
			pcall(function()
				partyFn:InvokeServer("Accept")
			end)
			pop:Destroy()
			MenuBridge.OpenTab("Party")
		end)
		acc.Position = UDim2.new(0.03, 0, 0, 60)
		acc.Parent = pop
		local dec = UIController.CreateButton("Отклонить", UDim2.new(0.42, 0, 0, 36), function()
			local partyFn = remotes:FindFirstChild(RemoteNames.PartyAction)
			pcall(function()
				partyFn:InvokeServer("Decline")
			end)
			pop:Destroy()
		end)
		dec.Position = UDim2.new(0.52, 0, 0, 60)
		dec.Parent = pop
		task.delay(25, function()
			if pop.Parent then
				pop:Destroy()
			end
		end)
	end)
end
