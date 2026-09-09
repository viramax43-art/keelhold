--[[
	UIController — ScreenGui + HUD (Gold/XP/level bar).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UITheme = require(ReplicatedStorage.Shared.Util.UITheme)

local UIController = {}
UIController.ScreenGui = nil

local lastGold, lastXP = nil, nil
local lastHUDUpdate = 0
local pendingProfile = nil
local flushScheduled = false
local HUD_UPDATE_INTERVAL = 0.25

local function xpForLevel(level)
	local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
	return math.floor((GameConfig.XPPerLevel or 150) * ((GameConfig.XPPerLevelGrowth or 1.15) ^ (level - 1)))
end

local Format = require(ReplicatedStorage.Shared.Util.Format)

local function popDelta(hud, anchor, delta, color)
	if not hud or not anchor or delta <= 0 then
		return
	end
	local p = Instance.new("TextLabel")
	p.Size = UDim2.new(0, 80, 0, 20)
	p.Position = UDim2.new(1, -90, 0, anchor.Position.Y.Offset + 4)
	p.BackgroundTransparency = 1
	p.Text = "+" .. tostring(delta)
	p.TextColor3 = color
	p.Font = Enum.Font.GothamBold
	p.TextSize = 14
	p.TextXAlignment = Enum.TextXAlignment.Right
	p.Parent = hud
	TweenService:Create(p, TweenInfo.new(0.9, Enum.EasingStyle.Quad), {
		Position = p.Position - UDim2.new(0, 0, 0, 18),
		TextTransparency = 1,
	}):Play()
	task.delay(1, function()
		if p.Parent then
			p:Destroy()
		end
	end)
end

local function applyHUD(p)
	local gui = UIController.ScreenGui
	if not gui or not p then
		return
	end
	local hud = gui:FindFirstChild("HUD")
	if not hud then
		return
	end
	local gold = p.Gold or 0
	local xp = p.XP or 0
	local total = p.TotalXP or xp
	local level, acc = 1, 0
	while total >= acc + xpForLevel(level) and level < 200 do
		acc += xpForLevel(level)
		level += 1
	end
	local inLevel = total - acc
	local need = xpForLevel(level)

	local goldLabel = hud:FindFirstChild("Gold")
	local xpLabel = hud:FindFirstChild("XP")
	local xpBar = hud:FindFirstChild("XPBar")
	local fill = xpBar and xpBar:FindFirstChild("Fill")

	if goldLabel then
		goldLabel.Text = Format.Number(gold)
	end
	if xpLabel then
		xpLabel.Text = string.format("Ур. %d   %s / %s", level, Format.Number(inLevel), Format.Number(need))
	end
	if fill then
		TweenService:Create(fill, TweenInfo.new(0.35), {
			Size = UDim2.new(math.clamp(inLevel / math.max(need, 1), 0, 1), 0, 1, 0),
		}):Play()
	end

	if lastGold ~= nil and goldLabel then
		popDelta(hud, goldLabel, gold - lastGold, Color3.fromRGB(255, 215, 80))
	end
	if lastXP ~= nil and xpLabel then
		popDelta(hud, xpLabel, xp - lastXP, Color3.fromRGB(120, 200, 255))
	end
	lastGold, lastXP = gold, xp
end

function UIController:Init()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "BridgeDefenseUI"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	UIController.ScreenGui = gui

	local hud = Instance.new("Frame")
	hud.Name = "HUD"
	hud.Size = UDim2.new(0, 200, 0, 72)
	hud.Position = UDim2.new(0, 10, 0, 10)
	hud.BackgroundColor3 = UITheme.Colors.PanelBg
	hud.BackgroundTransparency = 0.2
	hud.BorderSizePixel = 0
	hud.Parent = gui
	local hc = Instance.new("UICorner")
	hc.CornerRadius = UITheme.CornerRadius.Panel
	hc.Parent = hud
	local hs = Instance.new("UIStroke")
	hs.Color = UITheme.Colors.Border
	hs.Thickness = 1
	hs.Parent = hud
	local hudAccent = Instance.new("Frame")
	hudAccent.Size = UDim2.new(0, 3, 1, -8)
	hudAccent.Position = UDim2.new(0, 4, 0, 4)
	hudAccent.BackgroundColor3 = UITheme.Colors.Accent
	hudAccent.BorderSizePixel = 0
	hudAccent.Parent = hud
	local hac = Instance.new("UICorner")
	hac.CornerRadius = UDim.new(0, 2)
	hac.Parent = hudAccent

	local function row(name, y, iconLetter, color)
		local badge = Instance.new("Frame")
		badge.Name = name .. "Icon"
		badge.Size = UDim2.new(0, 20, 0, 20)
		badge.Position = UDim2.new(0, 12, 0, y + 1)
		badge.BackgroundColor3 = color
		badge.BorderSizePixel = 0
		badge.Parent = hud
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0, 3)
		bc.Parent = badge
		local ic = Instance.new("TextLabel")
		ic.Size = UDim2.new(1, 0, 1, 0)
		ic.BackgroundTransparency = 1
		ic.Text = iconLetter
		ic.TextColor3 = Color3.fromRGB(15, 17, 22)
		ic.Font = Enum.Font.GothamBold
		ic.TextSize = 11
		ic.Parent = badge
		local l = Instance.new("TextLabel")
		l.Name = name
		l.Size = UDim2.new(1, -42, 0, 22)
		l.Position = UDim2.new(0, 38, 0, y)
		l.BackgroundTransparency = 1
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextColor3 = color
		l.Font = Enum.Font.GothamBold
		l.TextSize = 13
		l.Text = "0"
		l.Parent = hud
		return l
	end
	row("Gold", 6, "З", UITheme.Colors.AccentGold)
	row("XP", 30, "О", UITheme.Colors.Accent)

	local xpBarBg, xpFill = UITheme.CreateBar(hud, UDim2.new(1, -18, 0, 5), UDim2.new(0, 9, 1, -12), UITheme.Colors.BarXP)
	xpBarBg.Name = "XPBar"
	xpFill.Name = "Fill"

	-- Сразу слушаем атрибуты профиля (БД), не ждём MenuController
	do
		local function fromAttrs()
			local gold = player:GetAttribute("BD_Gold")
			if gold == nil then
				return
			end
			UIController.UpdateHUD({
				Gold = gold,
				XP = player:GetAttribute("BD_XP") or 0,
				TotalXP = player:GetAttribute("BD_TotalXP") or 0,
				Level = player:GetAttribute("BD_Level") or 1,
			}, true)
		end
		player:GetAttributeChangedSignal("BD_Gold"):Connect(fromAttrs)
		player:GetAttributeChangedSignal("BD_XP"):Connect(fromAttrs)
		player:GetAttributeChangedSignal("BD_ProfileReady"):Connect(fromAttrs)
		task.defer(fromAttrs)
		task.spawn(function()
			for _ = 1, 40 do
				fromAttrs()
				if player:GetAttribute("BD_ProfileReady") == true then
					break
				end
				task.wait(0.25)
			end
		end)
	end

	-- Компактные кнопки меню (можно свернуть)
	local menuPanel = Instance.new("Frame")
	menuPanel.Name = "MenuButtons"
	menuPanel.Size = UDim2.new(0, 200, 0, 52)
	menuPanel.Position = UDim2.new(0, 10, 0, 88)
	menuPanel.BackgroundTransparency = 1
	menuPanel.Visible = false
	menuPanel.Parent = gui

	local menuToggle = Instance.new("TextButton")
	menuToggle.Name = "MenuToggle"
	menuToggle.Size = UDim2.new(0, 72, 0, 24)
	menuToggle.Position = UDim2.new(0, 10, 0, 88)
	menuToggle.Text = "Меню ▾"
	menuToggle.TextSize = 11
	menuToggle.Parent = gui
	UITheme.ApplyButton(menuToggle, Color3.fromRGB(40, 48, 65))
	local layoutActionRow
	menuToggle.MouseButton1Click:Connect(function()
		menuPanel.Visible = not menuPanel.Visible
		menuToggle.Text = menuPanel.Visible and "Меню ▴" or "Меню ▾"
		if layoutActionRow then
			layoutActionRow()
		end
	end)

	local buttons = {
		{ "Прокачка", "Upgrade", Color3.fromRGB(50, 90, 60) },
		{ "Отряд", "Units", Color3.fromRGB(70, 55, 100) },
		{ "Ежедневка", "Daily", Color3.fromRGB(120, 75, 45) },
		{ "Пати", "Party", Color3.fromRGB(40, 80, 100) },
		{ "Гайд", "Guide", Color3.fromRGB(55, 70, 110) },
	}
	local btnW, btnH, gap = 62, 22, 4
	for i, info in ipairs(buttons) do
		local col = (i - 1) % 3
		local rowIdx = math.floor((i - 1) / 3)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0, btnW, 0, btnH)
		b.Position = UDim2.new(0, col * (btnW + gap), 0, rowIdx * (btnH + gap))
		b.Text = info[1]
		b.TextSize = 10
		b.Parent = menuPanel
		UITheme.ApplyButton(b, info[3])
		local tab = info[2]
		b.MouseButton1Click:Connect(function()
			local ok, MenuBridge = pcall(require, ReplicatedStorage.Shared.Util.MenuBridge)
			if ok and MenuBridge then
				MenuBridge.OpenTab(tab)
			end
		end)
	end

	local status = Instance.new("TextLabel")
	status.Name = "HudStatus"
	status.Size = UDim2.new(0, 240, 0, 16)
	status.Position = UDim2.new(0, 10, 1, -22)
	status.AnchorPoint = Vector2.new(0, 1)
	status.BackgroundTransparency = 1
	status.Text = ""
	status.TextColor3 = Color3.fromRGB(180, 190, 210)
	status.Font = Enum.Font.Gotham
	status.TextSize = 11
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Parent = gui

	local function setStatus(text, color)
		status.Text = text
		status.TextColor3 = color
		task.delay(2.5, function()
			if status.Text == text then
				status.Text = ""
			end
		end)
	end

	local function remotesFolder()
		return ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage:WaitForChild("Remotes", 3)
	end

	local MENU_X = 10
	local MENU_Y = 88
	local ACTION_H = 24
	local ACTION_GAP = 4
	local BTN_W = 70

	local function makeActionBtn(name, text, color, width, onClick)
		local b = Instance.new("TextButton")
		b.Name = name
		b.Size = UDim2.new(0, width or BTN_W, 0, ACTION_H)
		b.Position = UDim2.new(0, MENU_X, 0, MENU_Y)
		b.Text = text
		b.TextSize = 11
		b.Parent = gui
		UITheme.ApplyButton(b, color)
		b.MouseButton1Click:Connect(function()
			task.spawn(onClick)
		end)
		return b
	end

	-- Одна строка: Меню | Прокачка | Шоп | Бой | Обнул.  (в бою: Меню | Выход | Волна)
	local upgradeBtn = makeActionBtn("UpgradeButton", "Прокачка", Color3.fromRGB(50, 90, 60), 78, function()
		local ok, MenuBridge = pcall(require, ReplicatedStorage.Shared.Util.MenuBridge)
		if ok and MenuBridge then
			MenuBridge.OpenTab("Upgrade")
		else
			setStatus("Меню недоступно", Color3.fromRGB(255, 120, 120))
		end
	end)

	local shopBtn = makeActionBtn("TpShopButton", "Шоп", Color3.fromRGB(70, 95, 55), BTN_W, function()
		local fn = remotesFolder() and remotesFolder():FindFirstChild("TestTeleport")
		if not fn or not fn:IsA("RemoteFunction") then
			setStatus("Нет Remote", Color3.fromRGB(255, 120, 120))
			return
		end
		local ok, res = pcall(function()
			return fn:InvokeServer("shop")
		end)
		if ok and type(res) == "table" and res.success then
			setStatus("→ шоп", Color3.fromRGB(120, 220, 140))
		else
			setStatus((type(res) == "table" and res.error) or "Не удалось", Color3.fromRGB(255, 120, 120))
		end
	end)

	local battleBtn = makeActionBtn("TpBattleButton", "Бой", Color3.fromRGB(140, 55, 55), BTN_W, function()
		local rem = remotesFolder()
		local startFn = rem and rem:FindFirstChild("StartBattle")
		if startFn and startFn:IsA("RemoteFunction") then
			local ok, res = pcall(function()
				return startFn:InvokeServer()
			end)
			if ok and type(res) == "table" and res.success ~= false then
				setStatus("→ бой", Color3.fromRGB(120, 220, 140))
				return
			end
		end
		local fn = rem and rem:FindFirstChild("TestTeleport")
		if fn and fn:IsA("RemoteFunction") then
			local ok, res = pcall(function()
				return fn:InvokeServer("battle")
			end)
			if ok and type(res) == "table" and res.success then
				setStatus("→ мост", Color3.fromRGB(120, 220, 140))
			else
				setStatus((type(res) == "table" and res.error) or "Не удалось", Color3.fromRGB(255, 120, 120))
			end
		end
	end)

	local exitBtn = makeActionBtn("ExitMissionButton", "Выход", Color3.fromRGB(90, 70, 50), BTN_W, function()
		local fn = remotesFolder() and remotesFolder():FindFirstChild("ReturnToLobby")
		if not fn or not fn:IsA("RemoteFunction") then
			setStatus("Нет Remote", Color3.fromRGB(255, 120, 120))
			return
		end
		local ok, res = pcall(function()
			return fn:InvokeServer()
		end)
		if ok then
			setStatus("→ лобби", Color3.fromRGB(120, 220, 140))
		else
			setStatus(tostring(res) or "Ошибка", Color3.fromRGB(255, 120, 120))
		end
	end)
	exitBtn.Visible = false

	local waveSpeedBtn = makeActionBtn("SpeedBoostButton", "Волна x10", Color3.fromRGB(60, 70, 110), 84, function()
		local fn = remotesFolder() and remotesFolder():FindFirstChild("ToggleWaveSpeed")
		if not fn or not fn:IsA("RemoteFunction") then
			setStatus("Нет Remote", Color3.fromRGB(255, 120, 120))
			return
		end
		local ok, res = pcall(function()
			return fn:InvokeServer()
		end)
		if ok and type(res) == "table" and res.success then
			local mult = tonumber(res.mult) or 1
			if mult >= 10 then
				waveSpeedBtn.Text = "Волна x1"
				setStatus("Боты x10 — волна ускорена", Color3.fromRGB(120, 220, 140))
			else
				waveSpeedBtn.Text = "Волна x10"
				setStatus("Скорость волны обычная", Color3.fromRGB(180, 190, 210))
			end
		else
			setStatus("Не удалось", Color3.fromRGB(255, 120, 120))
		end
	end)
	waveSpeedBtn.Visible = false

	local resetBtn = makeActionBtn("ResetProfileButton", "Обнул.", Color3.fromRGB(90, 35, 40), BTN_W, function() end)

	layoutActionRow = function()
		local y = if menuPanel.Visible then 144 else MENU_Y
		menuToggle.Position = UDim2.new(0, MENU_X, 0, y)

		-- 1-я линия: Меню | Прокачка | Шоп
		local x1 = MENU_X + menuToggle.Size.X.Offset + ACTION_GAP
		if upgradeBtn.Visible then
			upgradeBtn.Position = UDim2.new(0, x1, 0, y)
			x1 += upgradeBtn.Size.X.Offset + ACTION_GAP
		end
		if shopBtn.Visible then
			shopBtn.Position = UDim2.new(0, x1, 0, y)
		end

		-- 2-я линия: Бой | Обнул.  (в бою: Выход | Волна)
		local y2 = y + ACTION_H + ACTION_GAP
		local x2 = MENU_X
		local row2 = {}
		if battleBtn.Visible then
			table.insert(row2, battleBtn)
		end
		if exitBtn.Visible then
			table.insert(row2, exitBtn)
		end
		if waveSpeedBtn.Visible then
			table.insert(row2, waveSpeedBtn)
		end
		if resetBtn.Visible then
			table.insert(row2, resetBtn)
		end
		for _, btn in ipairs(row2) do
			btn.Position = UDim2.new(0, x2, 0, y2)
			x2 += btn.Size.X.Offset + ACTION_GAP
		end
	end

	local function setBattleHud(inBattle: boolean)
		upgradeBtn.Visible = not inBattle
		shopBtn.Visible = not inBattle
		battleBtn.Visible = not inBattle
		exitBtn.Visible = inBattle
		waveSpeedBtn.Visible = inBattle
		resetBtn.Visible = not inBattle
		if not inBattle then
			waveSpeedBtn.Text = "Волна x10"
		end
		layoutActionRow()
	end
	setBattleHud(false)

	local resetArmed = false
	local resetToken = 0
	resetBtn.MouseButton1Click:Connect(function()
		if not resetArmed then
			resetArmed = true
			resetBtn.Text = "Точно?"
			resetToken += 1
			local token = resetToken
			task.delay(4, function()
				if resetToken == token then
					resetArmed = false
					resetBtn.Text = "Обнул."
				end
			end)
			return
		end
		resetArmed = false
		resetBtn.Text = "Обнул."
		task.spawn(function()
			local fn = remotesFolder() and remotesFolder():FindFirstChild("ResetProfile")
			if not fn or not fn:IsA("RemoteFunction") then
				setStatus("Нет Remote", Color3.fromRGB(255, 120, 120))
				return
			end
			local ok, res = pcall(function()
				return fn:InvokeServer()
			end)
			if ok and type(res) == "table" and res.success then
				if res.profile then
					UIController.UpdateHUD(res.profile, true)
				end
				setStatus("Прогресс сброшен", Color3.fromRGB(120, 220, 140))
			else
				setStatus((type(res) == "table" and res.error) or "Не удалось", Color3.fromRGB(255, 120, 120))
			end
		end)
	end)

	local remotes = remotesFolder()
	if remotes then
		local started = remotes:FindFirstChild("BattleStarted")
		local ended = remotes:FindFirstChild("BattleEnded")
		if started then
			started.OnClientEvent:Connect(function()
				setBattleHud(true)
			end)
		end
		if ended then
			ended.OnClientEvent:Connect(function()
				setBattleHud(false)
			end)
		end
	end
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
	panel.Visible = true
	panel.Parent = gui
	UITheme.ApplyPanel(panel)
	return panel
end

function UIController.CreateButton(text: string, size: UDim2, callback): TextButton
	local btn = Instance.new("TextButton")
	btn.Size = size
	btn.Text = text
	btn.TextScaled = true
	UITheme.ApplyButton(btn, UITheme.Colors.ButtonBg)
	btn.MouseButton1Click:Connect(function()
		if callback then
			callback()
		end
	end)
	return btn
end

function UIController.UpdateHUD(profile, force)
	if not profile then
		return
	end
	pendingProfile = profile
	if force then
		lastHUDUpdate = os.clock()
		local p = pendingProfile
		pendingProfile = nil
		applyHUD(p)
		return
	end
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
