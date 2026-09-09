local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)

local MobileController = {}
local inited = false

function MobileController:Init()
	if inited then
		return
	end
	inited = true
	if not UserInputService.TouchEnabled then
		return
	end
	local gui = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("BridgeDefenseUI", 10)
	if not gui then
		return
	end
	local btn = Instance.new("TextButton")
	btn.Name = "MobileFire"
	btn.Size = UDim2.new(0, 90, 0, 90)
	btn.Position = UDim2.new(1, -210, 1, -120)
	btn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
	btn.BackgroundTransparency = 0.25
	btn.Text = "ОГОНЬ"
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Font = Enum.Font.GothamBold
	btn.TextScaled = true
	btn.ZIndex = 60
	btn.Visible = false
	btn.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = btn

	local holding = false
	btn.MouseButton1Down:Connect(function()
		holding = true
	end)
	btn.MouseButton1Up:Connect(function()
		holding = false
	end)
	btn.MouseLeave:Connect(function()
		holding = false
	end)

	local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
	if remotes then
		local started = remotes:FindFirstChild(RemoteNames.BattleStarted)
		local ended = remotes:FindFirstChild(RemoteNames.BattleEnded)
		-- Кнопка огня скрыта: игрок не стреляет
		if started then
			started.OnClientEvent:Connect(function()
				btn.Visible = false
			end)
		end
		if ended then
			ended.OnClientEvent:Connect(function()
				holding = false
				btn.Visible = false
			end)
		end
	end
	btn.Visible = false
end

return MobileController
