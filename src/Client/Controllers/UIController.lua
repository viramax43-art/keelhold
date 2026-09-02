--[[
	UIController — ScreenGui + панели.
]]

local Players = game:GetService("Players")

local UIController = {}
UIController.ScreenGui = nil

function UIController:Init()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "BridgeDefenseUI"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	UIController.ScreenGui = gui

	-- HUD
	local hud = Instance.new("Frame")
	hud.Name = "HUD"
	hud.Size = UDim2.new(0, 220, 0, 70)
	hud.Position = UDim2.new(0, 12, 0, 12)
	hud.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
	hud.BackgroundTransparency = 0.25
	hud.BorderSizePixel = 0
	hud.Parent = gui

	local gold = Instance.new("TextLabel")
	gold.Name = "Gold"
	gold.Size = UDim2.new(1, -12, 0.5, -4)
	gold.Position = UDim2.new(0, 6, 0, 4)
	gold.BackgroundTransparency = 1
	gold.TextXAlignment = Enum.TextXAlignment.Left
	gold.Text = "Gold: 0"
	gold.TextColor3 = Color3.fromRGB(255, 220, 100)
	gold.Font = Enum.Font.GothamBold
	gold.TextScaled = true
	gold.Parent = hud

	local xp = Instance.new("TextLabel")
	xp.Name = "XP"
	xp.Size = UDim2.new(1, -12, 0.5, -4)
	xp.Position = UDim2.new(0, 6, 0.5, 0)
	xp.BackgroundTransparency = 1
	xp.TextXAlignment = Enum.TextXAlignment.Left
	xp.Text = "XP: 0 | Lv 1"
	xp.TextColor3 = Color3.fromRGB(180, 220, 255)
	xp.Font = Enum.Font.Gotham
	xp.TextScaled = true
	xp.Parent = hud
end

function UIController.WaitForReady()
	for _ = 1, 100 do
		if UIController.ScreenGui then
			return true
		end
		task.wait(0.05)
	end
	return false
end

function UIController.CreatePanel(name: string, size: UDim2): Frame
	local gui = UIController.ScreenGui
	local panel = Instance.new("Frame")
	panel.Name = name
	panel.Size = size
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel = 0
	panel.Visible = true
	panel.Parent = gui
	return panel
end

function UIController.CreateButton(text: string, size: UDim2, callback): TextButton
	local btn = Instance.new("TextButton")
	btn.Size = size
	btn.BackgroundColor3 = Color3.fromRGB(50, 120, 70)
	btn.BorderSizePixel = 0
	btn.Text = text
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Font = Enum.Font.GothamBold
	btn.TextScaled = true
	btn.MouseButton1Click:Connect(function()
		if callback then
			callback()
		end
	end)
	return btn
end

local lastHUDUpdate = 0
local pendingProfile = nil
local flushScheduled = false
local HUD_UPDATE_INTERVAL = 0.25

local function applyHUD(p)
	local gui = UIController.ScreenGui
	if not gui or not p then
		return
	end
	local hud = gui:FindFirstChild("HUD")
	if not hud then
		return
	end
	local gold = hud:FindFirstChild("Gold")
	local xp = hud:FindFirstChild("XP")
	if gold then
		gold.Text = "Gold: " .. tostring(p.Gold or 0)
	end
	if xp then
		xp.Text = string.format("XP: %d | Lv %d", p.XP or 0, p.Level or 1)
	end
end

function UIController.UpdateHUD(profile)
	if not profile then
		return
	end
	pendingProfile = profile
	local now = os.clock()
	if now - lastHUDUpdate >= HUD_UPDATE_INTERVAL then
		lastHUDUpdate = now
		local p = pendingProfile
		pendingProfile = nil
		applyHUD(p)
		return
	end
	if flushScheduled then
		return
	end
	flushScheduled = true
	task.delay(HUD_UPDATE_INTERVAL, function()
		flushScheduled = false
		if pendingProfile then
			lastHUDUpdate = os.clock()
			local p = pendingProfile
			pendingProfile = nil
			applyHUD(p)
		end
	end)
end

return UIController
