local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local MobileController = {}

function MobileController:Init()
	if not UserInputService.TouchEnabled then
		return
	end
	local gui = Players.LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild("BridgeDefenseUI")
	if not gui then
		return
	end
	local btn = Instance.new("TextButton")
	btn.Name = "MobileFire"
	btn.Size = UDim2.new(0, 90, 0, 90)
	btn.Position = UDim2.new(1, -110, 1, -120)
	btn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
	btn.Text = "FIRE"
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Font = Enum.Font.GothamBold
	btn.TextScaled = true
	btn.Parent = gui

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
			if holding then
				-- fire via invoking same path: synthesize by requiring FireWeapon
				local ReplicatedStorage = game:GetService("ReplicatedStorage")
				local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)
				local remotes = ReplicatedStorage:FindFirstChild("Remotes")
				local fn = remotes and remotes:FindFirstChild(RemoteNames.FireWeapon)
				if fn then
					local char = Players.LocalPlayer.Character
					local hrp = char and char:FindFirstChild("HumanoidRootPart")
					pcall(function()
						fn:InvokeServer(nil, hrp and hrp.Position)
					end)
				end
			end
		end
	end)
end

return MobileController
