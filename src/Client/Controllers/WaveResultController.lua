local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)

local WaveResultController = {}

local function showResult(gui, data)
	data = data or {}
	local success = data.success == true

	local backdrop = Instance.new("Frame")
	backdrop.Name = "WaveResultModal"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel = 0
	backdrop.ZIndex = 100
	backdrop.Parent = gui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.Size = UDim2.new(0, 0, 0, 0)
	panel.BackgroundColor3 = success and Color3.fromRGB(20, 40, 25) or Color3.fromRGB(40, 20, 20)
	panel.BorderSizePixel = 0
	panel.ZIndex = 101
	panel.Parent = backdrop

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = success and Color3.fromRGB(80, 220, 120) or Color3.fromRGB(220, 60, 60)
	stroke.Thickness = 2
	stroke.Parent = panel

	local icon = Instance.new("TextLabel")
	icon.Size = UDim2.new(1, 0, 0, 60)
	icon.BackgroundTransparency = 1
	icon.Text = success and "OK" or "X"
	icon.TextSize = 36
	icon.Font = Enum.Font.GothamBold
	icon.TextColor3 = success and Color3.fromRGB(100, 255, 140) or Color3.fromRGB(255, 80, 80)
	icon.ZIndex = 102
	icon.Parent = panel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -20, 0, 36)
	title.Position = UDim2.new(0, 10, 0, 65)
	title.BackgroundTransparency = 1
	title.Text = success and "ВОЛНА ПРОЙДЕНА!" or "СКВАД УНИЧТОЖЕН"
	title.TextColor3 = success and Color3.fromRGB(100, 255, 140) or Color3.fromRGB(255, 80, 80)
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.ZIndex = 102
	title.Parent = panel

	local waveLabel = Instance.new("TextLabel")
	waveLabel.Size = UDim2.new(1, 0, 0, 24)
	waveLabel.Position = UDim2.new(0, 0, 0, 110)
	waveLabel.BackgroundTransparency = 1
	waveLabel.Text = "Волна: " .. tostring(data.wave or "?")
	waveLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
	waveLabel.Font = Enum.Font.Gotham
	waveLabel.TextSize = 16
	waveLabel.ZIndex = 102
	waveLabel.Parent = panel

	if success then
		local rewardLabel = Instance.new("TextLabel")
		rewardLabel.Size = UDim2.new(1, 0, 0, 28)
		rewardLabel.Position = UDim2.new(0, 0, 0, 140)
		rewardLabel.BackgroundTransparency = 1
		rewardLabel.Text = string.format("+%d золота    +%d опыта", data.goldEarned or 0, data.xpEarned or 0)
		rewardLabel.TextColor3 = Color3.fromRGB(255, 215, 80)
		rewardLabel.Font = Enum.Font.GothamBold
		rewardLabel.TextSize = 16
		rewardLabel.ZIndex = 102
		rewardLabel.Parent = panel
	end

	local targetH = success and 200 or 180
	TweenService:Create(panel, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 340, 0, targetH),
	}):Play()

	task.delay(3, function()
		if not backdrop.Parent then
			return
		end
		TweenService:Create(backdrop, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(panel, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		task.delay(0.35, function()
			if backdrop.Parent then
				backdrop:Destroy()
			end
		end)
	end)
end

function WaveResultController:Init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
	if not remotes then
		return
	end
	local gui = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("BridgeDefenseUI", 10)
	if not gui then
		return
	end

	local waveEvt = remotes:FindFirstChild(RemoteNames.WaveResult)
	if waveEvt then
		waveEvt.OnClientEvent:Connect(function(payload)
			showResult(gui, payload)
		end)
	end

	local waveUp = remotes:FindFirstChild(RemoteNames.WaveUpdated)
	if waveUp then
		local waveLabel = Instance.new("TextLabel")
		waveLabel.Name = "WaveInfo"
		waveLabel.Size = UDim2.new(0, 220, 0, 28)
		waveLabel.Position = UDim2.new(0, 12, 0, 90)
		waveLabel.BackgroundTransparency = 1
		waveLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
		waveLabel.Font = Enum.Font.Gotham
		waveLabel.TextScaled = true
		waveLabel.TextXAlignment = Enum.TextXAlignment.Left
		waveLabel.Text = ""
		waveLabel.Parent = gui
		waveUp.OnClientEvent:Connect(function(info)
			if info then
				waveLabel.Text = string.format(
					"Wave %s | Enemies %s | Bots %s",
					tostring(info.Wave),
					tostring(info.EnemiesAlive),
					tostring(info.BotsAlive)
				)
			end
		end)
	end
end

return WaveResultController
