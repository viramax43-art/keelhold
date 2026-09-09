--[[
	UITheme — единая дизайн-система (тёмный профессиональный стиль).
	Использовать во всех контроллерах вместо хардкода цветов.
]]

local UITheme = {
	Colors = {
		-- Панели
		PanelBg = Color3.fromRGB(14, 16, 22),
		PanelBgLight = Color3.fromRGB(20, 23, 32),
		HeaderBg = Color3.fromRGB(18, 21, 30),
		Border = Color3.fromRGB(45, 52, 72),
		BorderLight = Color3.fromRGB(70, 80, 110),

		-- Текст
		TextPrimary = Color3.fromRGB(235, 238, 245),
		TextSecondary = Color3.fromRGB(160, 168, 185),
		TextMuted = Color3.fromRGB(110, 116, 135),

		-- Акценты
		Accent = Color3.fromRGB(0, 170, 255),      -- циан
		AccentGold = Color3.fromRGB(255, 200, 60),  -- золото
		AccentGreen = Color3.fromRGB(60, 200, 120), -- успех
		AccentRed = Color3.fromRGB(230, 60, 70),    -- опасность
		AccentPurple = Color3.fromRGB(160, 100, 255),

		-- Кнопки
		ButtonBg = Color3.fromRGB(32, 38, 55),
		ButtonHover = Color3.fromRGB(45, 55, 80),
		ButtonDisabled = Color3.fromRGB(25, 28, 38),
		ButtonTextDisabled = Color3.fromRGB(90, 95, 110),

		-- Полосы
		BarBg = Color3.fromRGB(22, 25, 35),
		BarHP = Color3.fromRGB(60, 200, 120),
		BarHPEnemy = Color3.fromRGB(230, 60, 70),
		BarXP = Color3.fromRGB(0, 170, 255),
		BarMilestone = Color3.fromRGB(255, 200, 60),
	},

	Fonts = {
		Title = Enum.Font.GothamBold,
		Body = Enum.Font.Gotham,
		Mono = Enum.Font.Code,
	},

	CornerRadius = {
		Panel = UDim.new(0, 6),
		Button = UDim.new(0, 4),
		Bar = UDim.new(0, 2),
	},

	StrokeThickness = 1,
}

-- Хелпер: панель с обводкой и акцентной полосой слева
function UITheme.ApplyPanel(frame: Frame, accent: Color3?)
	frame.BackgroundColor3 = UITheme.Colors.PanelBg
	frame.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UITheme.CornerRadius.Panel
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = UITheme.Colors.Border
	stroke.Thickness = UITheme.StrokeThickness
	stroke.Parent = frame

	if accent then
		local bar = Instance.new("Frame")
		bar.Name = "AccentBar"
		bar.Size = UDim2.new(0, 3, 1, -8)
		bar.Position = UDim2.new(0, 4, 0, 4)
		bar.BackgroundColor3 = accent
		bar.BorderSizePixel = 0
		bar.Parent = frame
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0, 2)
		bc.Parent = bar
	end
end

-- Хелпер: кнопка в едином стиле
function UITheme.ApplyButton(btn: TextButton, color: Color3?)
	btn.BackgroundColor3 = color or UITheme.Colors.ButtonBg
	btn.BorderSizePixel = 0
	btn.TextColor3 = UITheme.Colors.TextPrimary
	btn.Font = UITheme.Fonts.Title
	btn.AutoButtonColor = false

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UITheme.CornerRadius.Button
	corner.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Color = UITheme.Colors.Border
	stroke.Thickness = 1
	stroke.Transparency = 0.5
	stroke.Parent = btn

	-- Hover-эффект
	local baseColor = btn.BackgroundColor3
	btn.MouseEnter:Connect(function()
		btn.BackgroundColor3 = baseColor:Lerp(Color3.new(1, 1, 1), 0.12)
	end)
	btn.MouseLeave:Connect(function()
		btn.BackgroundColor3 = baseColor
	end)
end

-- Хелпер: полоса прогресса (HP/XP/милстоун)
function UITheme.CreateBar(parent: Instance, size: UDim2, pos: UDim2, fillColor: Color3): (Frame, Frame)
	local bg = Instance.new("Frame")
	bg.Size = size
	bg.Position = pos
	bg.BackgroundColor3 = UITheme.Colors.BarBg
	bg.BorderSizePixel = 0
	bg.Parent = parent
	local bgc = Instance.new("UICorner")
	bgc.CornerRadius = UITheme.CornerRadius.Bar
	bgc.Parent = bg
	local bgs = Instance.new("UIStroke")
	bgs.Color = UITheme.Colors.Border
	bgs.Thickness = 1
	bgs.Transparency = 0.6
	bgs.Parent = bg

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = fillColor
	fill.BorderSizePixel = 0
	fill.Parent = bg
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UITheme.CornerRadius.Bar
	fc.Parent = fill

	return bg, fill
end

return UITheme
