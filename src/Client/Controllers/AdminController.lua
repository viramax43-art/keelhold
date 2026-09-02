local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AdminConfig = require(ReplicatedStorage.Shared.Config.AdminConfig)
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)

local AdminController = {}
local panel = nil
local isAdmin = false

local function ensurePanel(gui)
	if panel and panel.Parent then
		return panel
	end
	panel = Instance.new("Frame")
	panel.Name = "AdminPanel"
	panel.Size = UDim2.new(0, 280, 0, 160)
	panel.Position = UDim2.new(1, -300, 0, 120)
	panel.BackgroundColor3 = Color3.fromRGB(22, 24, 32)
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 80
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -12, 0, 28)
	title.Position = UDim2.new(0, 6, 0, 6)
	title.BackgroundTransparency = 1
	title.Text = "Admin"
	title.TextColor3 = Color3.fromRGB(240, 240, 245)
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 81
	title.Parent = panel

	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(1, -12, 0, 40)
	hint.Position = UDim2.new(0, 6, 0, 40)
	hint.BackgroundTransparency = 1
	hint.Text = "Chat /admin to toggle. Use server AdminService remotes for grants."
	hint.TextColor3 = Color3.fromRGB(160, 165, 180)
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 12
	hint.TextWrapped = true
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.ZIndex = 81
	hint.Parent = panel

	local refresh = Instance.new("TextButton")
	refresh.Size = UDim2.new(1, -12, 0, 32)
	refresh.Position = UDim2.new(0, 6, 1, -40)
	refresh.BackgroundColor3 = Color3.fromRGB(80, 140, 255)
	refresh.Text = "Refresh profile"
	refresh.TextColor3 = Color3.new(1, 1, 1)
	refresh.Font = Enum.Font.GothamBold
	refresh.TextSize = 13
	refresh.ZIndex = 81
	refresh.Parent = panel
	local rc = Instance.new("UICorner")
	rc.CornerRadius = UDim.new(0, 6)
	rc.Parent = refresh
	refresh.MouseButton1Click:Connect(function()
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local fn = remotes and remotes:FindFirstChild(RemoteNames.GetProfile)
		if fn then
			pcall(function()
				fn:InvokeServer()
			end)
		end
	end)
	return panel
end

function AdminController.TogglePanel()
	local gui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	gui = gui and gui:FindFirstChild("BridgeDefenseUI")
	if not gui then
		return
	end
	local p = ensurePanel(gui)
	p.Visible = not p.Visible
end

function AdminController:Init()
	local player = Players.LocalPlayer
	for _, id in ipairs(AdminConfig.AdminUserIds or {}) do
		if player.UserId == id then
			isAdmin = true
			break
		end
	end
	if not isAdmin then
		return
	end
	player.Chatted:Connect(function(msg)
		if string.lower(string.sub(msg, 1, 6)) == "/admin" then
			AdminController.TogglePanel()
		end
	end)
end

return AdminController
