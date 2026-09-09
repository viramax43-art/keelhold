local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)

local WaveResultController = {}
local inited = false

local function showResult(gui, data)
	data = data or {}
	local success = data.success == true
	local goldEarned = data.goldEarned or 0
	local xpEarned = data.xpEarned or 0

	local existing = gui:FindFirstChild("WaveResultModal")
	if existing then
		existing:Destroy()
	end

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
	icon.Size = UDim2.new(1, 0, 0, 50)
	icon.BackgroundTransparency = 1
	icon.Text = success and "✓" or "✕"
	icon.TextSize = 40
	icon.Font = Enum.Font.GothamBold
	icon.TextColor3 = success and Color3.fromRGB(100, 255, 140) or Color3.fromRGB(255, 80, 80)
	icon.ZIndex = 102
	icon.Parent = panel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -20, 0, 36)
	title.Position = UDim2.new(0, 10, 0, 52)
	title.BackgroundTransparency = 1
	title.Text = success and "ВОЛНА ПРОЙДЕНА!" or "ПОРАЖЕНИЕ"
	title.TextColor3 = success and Color3.fromRGB(100, 255, 140) or Color3.fromRGB(255, 80, 80)
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.ZIndex = 102
	title.Parent = panel

	local waveLabel = Instance.new("TextLabel")
	waveLabel.Size = UDim2.new(1, 0, 0, 24)
	waveLabel.Position = UDim2.new(0, 0, 0, 96)
	waveLabel.BackgroundTransparency = 1
	waveLabel.Text = "Волна: " .. tostring(data.wave or "?")
	waveLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
	waveLabel.Font = Enum.Font.Gotham
	waveLabel.TextSize = 16
	waveLabel.ZIndex = 102
	waveLabel.Parent = panel

	local rewardLabel = Instance.new("TextLabel")
	rewardLabel.Size = UDim2.new(1, -16, 0, 32)
	rewardLabel.Position = UDim2.new(0, 8, 0, 128)
	rewardLabel.BackgroundTransparency = 1
	rewardLabel.Text = string.format("Получено:  +%d золота    +%d опыта", goldEarned, xpEarned)
	rewardLabel.TextColor3 = Color3.fromRGB(255, 215, 80)
	rewardLabel.Font = Enum.Font.GothamBold
	rewardLabel.TextSize = 16
	rewardLabel.ZIndex = 102
	rewardLabel.Parent = panel

	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(1, 0, 0, 20)
	hint.Position = UDim2.new(0, 0, 0, 165)
	hint.BackgroundTransparency = 1
	hint.Text = success and "Следующая волна скоро..." or "Возврат в лобби..."
	hint.TextColor3 = Color3.fromRGB(160, 165, 180)
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 13
	hint.ZIndex = 102
	hint.Parent = panel

	TweenService:Create(panel, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 360, 0, 200),
	}):Play()

	task.delay(success and 3.2 or 2.2, function()
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
	if inited then
		return
	end
	inited = true
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
		local old = gui:FindFirstChild("WaveInfo")
		if old then
			old:Destroy()
		end
		local waveLabel = Instance.new("TextLabel")
		waveLabel.Name = "WaveInfo"
		waveLabel.Size = UDim2.new(0, 280, 0, 28)
		-- Справа сверху, чтобы не наползать на HUD золота/опыта
		waveLabel.Position = UDim2.new(1, -292, 0, 12)
		waveLabel.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
		waveLabel.BackgroundTransparency = 0.25
		waveLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
		waveLabel.Font = Enum.Font.Gotham
		waveLabel.TextSize = 14
		waveLabel.TextXAlignment = Enum.TextXAlignment.Center
		waveLabel.Text = ""
		waveLabel.Visible = false
		waveLabel.Parent = gui
		local wc = Instance.new("UICorner")
		wc.CornerRadius = UDim.new(0, 8)
		wc.Parent = waveLabel

		local remotesFolder = remotes
		local started = remotesFolder:FindFirstChild(RemoteNames.BattleStarted)
		local ended = remotesFolder:FindFirstChild(RemoteNames.BattleEnded)
		if started then
			started.OnClientEvent:Connect(function()
				waveLabel.Visible = true
			end)
		end
		if ended then
			ended.OnClientEvent:Connect(function()
				waveLabel.Visible = false
				waveLabel.Text = ""
			end)
		end

		waveUp.OnClientEvent:Connect(function(info)
			if not info then
				return
			end
			if info.InMission == false then
				waveLabel.Visible = false
				waveLabel.Text = ""
				return
			end
			waveLabel.Visible = true
			waveLabel.Text = string.format(
				"Волна %s  |  Враги %s  |  Боты %s",
				tostring(info.Wave),
				tostring(info.EnemiesAlive),
				tostring(info.BotsAlive)
			)
		end)
	end
end

return WaveResultController
