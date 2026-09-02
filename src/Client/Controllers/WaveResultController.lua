local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)

local WaveResultController = {}

function WaveResultController:Init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
	if not remotes then
		return
	end
	local gui = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("BridgeDefenseUI", 10)
	if not gui then
		return
	end

	local banner = Instance.new("TextLabel")
	banner.Name = "WaveBanner"
	banner.Size = UDim2.new(0.5, 0, 0, 60)
	banner.Position = UDim2.new(0.25, 0, 0.2, 0)
	banner.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	banner.BackgroundTransparency = 0.35
	banner.TextColor3 = Color3.new(1, 1, 1)
	banner.Font = Enum.Font.GothamBold
	banner.TextScaled = true
	banner.Visible = false
	banner.Parent = gui

	local waveEvt = remotes:FindFirstChild(RemoteNames.WaveResult)
	if waveEvt then
		waveEvt.OnClientEvent:Connect(function(payload)
			banner.Visible = true
			banner.Text = (payload and payload.success) and ("Волна " .. tostring(payload.wave) .. " пройдена!")
				or ("Поражение на волне " .. tostring(payload and payload.wave))
			banner.TextTransparency = 0
			task.delay(1.8, function()
				local tw = TweenService:Create(banner, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 })
				tw:Play()
				tw.Completed:Wait()
				banner.Visible = false
				banner.BackgroundTransparency = 0.35
			end)
		end)
	end

	local waveUp = remotes:FindFirstChild(RemoteNames.WaveUpdated)
	if waveUp then
		local hud = gui:FindFirstChild("HUD")
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
				waveLabel.Text = string.format("Wave %s | Enemies %s | Bots %s", tostring(info.Wave), tostring(info.EnemiesAlive), tostring(info.BotsAlive))
			end
		end)
	end
end

return WaveResultController
