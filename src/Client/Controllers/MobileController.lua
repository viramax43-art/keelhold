local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local MobileController = {}

function MobileController:Init()
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
	btn.Position = UDim2.new(1, -110, 1, -120)
	btn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
	btn.BackgroundTransparency = 0.25
	btn.Text = "FIRE"
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Font = Enum.Font.GothamBold
	btn.TextScaled = true
	btn.ZIndex = 60
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

	task.spawn(function()
		local CombatController = require(script.Parent.CombatController)
		while true do
			task.wait(0.12)
			if holding and CombatController.FireNearest then
				CombatController.FireNearest()
			end
		end
	end)
end

return MobileController
