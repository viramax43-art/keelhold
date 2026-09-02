--[[
	ModalManager — централизованные модальные окна (overlay поверх текущего UI).
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ModalManager = {}
local screenGui = nil
local currentModal = nil
local escConn = nil

local COLORS = {
	Backdrop = Color3.fromRGB(0, 0, 0),
	BackdropAlpha = 0.65,
	PanelBg = Color3.fromRGB(18, 20, 28),
	PanelBorder = Color3.fromRGB(60, 70, 100),
	HeaderBg = Color3.fromRGB(25, 28, 40),
	TextPrimary = Color3.fromRGB(240, 240, 245),
	Danger = Color3.fromRGB(220, 60, 60),
	Accent = Color3.fromRGB(80, 140, 255),
}

function ModalManager.Init(screenGuiRef)
	screenGui = screenGuiRef
end

function ModalManager.Close()
	if escConn then
		escConn:Disconnect()
		escConn = nil
	end
	if not currentModal then
		return
	end
	local panel = currentModal.Panel
	local backdropRef = currentModal.Backdrop
	currentModal = nil
	if panel then
		TweenService:Create(panel, TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
			Size = UDim2.new(0, 0, 0, 0),
			BackgroundTransparency = 1,
		}):Play()
	end
	if backdropRef then
		TweenService:Create(backdropRef, TweenInfo.new(0.2), {
			BackgroundTransparency = 1,
		}):Play()
		task.delay(0.25, function()
			if backdropRef and backdropRef.Parent then
				backdropRef:Destroy()
			end
		end)
	end
end

function ModalManager.Open(config)
	if not screenGui then
		return nil
	end
	if currentModal then
		ModalManager.Close()
	end

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "ModalBackdrop"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = COLORS.Backdrop
	backdrop.BackgroundTransparency = COLORS.BackdropAlpha
	backdrop.BorderSizePixel = 0
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.ZIndex = 50
	backdrop.Parent = screenGui
	backdrop.MouseButton1Click:Connect(function()
		ModalManager.Close()
	end)

	local targetSize = config.Size or UDim2.new(0.45, 0, 0.65, 0)
	local panel = Instance.new("Frame")
	panel.Name = "ModalPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.Size = UDim2.new(0, 0, 0, 0)
	panel.BackgroundColor3 = COLORS.PanelBg
	panel.BorderSizePixel = 0
	panel.ZIndex = 51
	panel.Parent = backdrop

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.PanelBorder
	stroke.Thickness = 1
	stroke.Parent = panel

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 48)
	header.BackgroundColor3 = COLORS.HeaderBg
	header.BorderSizePixel = 0
	header.ZIndex = 52
	header.Parent = panel

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 12)
	headerCorner.Parent = header

	local headerFix = Instance.new("Frame")
	headerFix.Size = UDim2.new(1, 0, 0, 14)
	headerFix.Position = UDim2.new(0, 0, 1, -14)
	headerFix.BackgroundColor3 = COLORS.HeaderBg
	headerFix.BorderSizePixel = 0
	headerFix.ZIndex = 52
	headerFix.Parent = header

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, -60, 1, 0)
	titleLabel.Position = UDim2.new(0, 16, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = config.Title or "Меню"
	titleLabel.TextColor3 = COLORS.TextPrimary
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextScaled = true
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.ZIndex = 53
	titleLabel.Parent = header

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0, 32, 0, 32)
	closeBtn.Position = UDim2.new(1, -42, 0, 8)
	closeBtn.BackgroundColor3 = COLORS.Danger
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 16
	closeBtn.ZIndex = 53
	closeBtn.Parent = header
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 8)
	closeCorner.Parent = closeBtn
	closeBtn.MouseButton1Click:Connect(function()
		ModalManager.Close()
	end)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Content"
	scroll.Size = UDim2.new(1, -20, 1, -60)
	scroll.Position = UDim2.new(0, 10, 0, 54)
	scroll.BackgroundTransparency = 1
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = COLORS.Accent
	scroll.BorderSizePixel = 0
	scroll.ZIndex = 52
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = panel

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = scroll

	listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		scroll.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 16)
	end)

	currentModal = { Panel = panel, Backdrop = backdrop, Scroll = scroll }

	TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = targetSize,
		BackgroundTransparency = 0,
	}):Play()

	if config.Content then
		config.Content(scroll)
	end

	escConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			ModalManager.Close()
		end
	end)

	return scroll
end

return ModalManager
