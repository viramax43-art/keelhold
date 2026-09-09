--[[
	FlightController — свободный полёт зрителя в бою.
	WASD относительно камеры, Space/E вверх, Ctrl/Q вниз, Shift ускорение.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)

local FlightController = {}
local player = Players.LocalPlayer
local active = false
local inited = false
local hbConn, bv, bg
local charAddedConn
local vertical = 0
local BASE_SPEED, FAST_SPEED = 45, 90
local mobileGui

local function cleanupBody()
	if bv then
		bv:Destroy()
		bv = nil
	end
	if bg then
		bg:Destroy()
		bg = nil
	end
end

local function attach(char)
	cleanupBody()
	local hrp = char:WaitForChild("HumanoidRootPart", 5)
	local hum = char:WaitForChild("Humanoid", 5)
	if not hrp or not hum then
		return
	end
	hrp.Anchored = false
	hum.PlatformStand = true
	hum.AutoRotate = false

	local att = hrp:FindFirstChild("RootAttachment")
	if not att then
		att = Instance.new("Attachment")
		att.Name = "RootAttachment"
		att.Parent = hrp
	end

	bv = Instance.new("LinearVelocity")
	bv.Name = "FlightVelocity"
	bv.MaxForce = 1e9
	bv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	bv.RelativeTo = Enum.ActuatorRelativeTo.World
	bv.VectorVelocity = Vector3.zero
	bv.Attachment0 = att
	bv.Parent = hrp

	bg = Instance.new("AlignOrientation")
	bg.Name = "FlightOrient"
	bg.Mode = Enum.OrientationAlignmentMode.OneAttachment
	bg.Attachment0 = att
	bg.MaxTorque = 1e9
	bg.Responsiveness = 50
	bg.Parent = hrp
end

local function step()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or not bv or not bg then
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end

	local move = Vector3.zero
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then
		move += cam.CFrame.LookVector
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then
		move -= cam.CFrame.LookVector
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then
		move += cam.CFrame.RightVector
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		move -= cam.CFrame.RightVector
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) or UserInputService:IsKeyDown(Enum.KeyCode.E) then
		move += Vector3.yAxis
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.Q) then
		move -= Vector3.yAxis
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and hum.MoveDirection.Magnitude > 0.05 then
		move += hum.MoveDirection
	end
	move += Vector3.yAxis * vertical

	local speed = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and FAST_SPEED or BASE_SPEED
	if move.Magnitude > 0 then
		bv.VectorVelocity = move.Unit * speed
	else
		bv.VectorVelocity = Vector3.zero
	end

	local flat = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
	if flat.Magnitude > 0.01 then
		bg.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit)
	end
end

local function buildMobileButtons()
	if not UserInputService.TouchEnabled or mobileGui then
		return
	end
	mobileGui = Instance.new("ScreenGui")
	mobileGui.Name = "FlightMobile"
	mobileGui.ResetOnSpawn = false
	mobileGui.Parent = player:WaitForChild("PlayerGui")
	local function mk(text, y, dir)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0, 64, 0, 64)
		b.AnchorPoint = Vector2.new(1, 1)
		b.Position = UDim2.new(1, -24, 1, y)
		b.BackgroundColor3 = Color3.fromRGB(28, 30, 42)
		b.BackgroundTransparency = 0.25
		b.Text = text
		b.TextSize = 28
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Font = Enum.Font.GothamBold
		b.Parent = mobileGui
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = b
		b.MouseButton1Down:Connect(function()
			vertical = dir
		end)
		b.MouseButton1Up:Connect(function()
			vertical = 0
		end)
	end
	mk("▲", -200, 1)
	mk("▼", -120, -1)
end

function FlightController.Enable()
	if active then
		return
	end
	active = true
	-- Клиентский запасной проход: убрать коллизии невидимых блоков рядом с игроком
	task.spawn(function()
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("BasePart") and d.CanCollide and d.Transparency >= 0.9 then
				local model = d:FindFirstAncestorOfClass("Model")
				if not (model and model:FindFirstChildOfClass("Humanoid")) then
					d.CanCollide = false
				end
			end
		end
	end)
	if player.Character then
		attach(player.Character)
	end
	if charAddedConn then
		charAddedConn:Disconnect()
	end
	charAddedConn = player.CharacterAdded:Connect(function(c)
		if active then
			attach(c)
		end
	end)
	buildMobileButtons()
	if hbConn then
		hbConn:Disconnect()
	end
	hbConn = RunService.Heartbeat:Connect(step)
end

function FlightController.Disable()
	active = false
	vertical = 0
	if charAddedConn then
		charAddedConn:Disconnect()
		charAddedConn = nil
	end
	if hbConn then
		hbConn:Disconnect()
		hbConn = nil
	end
	cleanupBody()
	if mobileGui then
		mobileGui:Destroy()
		mobileGui = nil
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.PlatformStand = false
		hum.AutoRotate = true
	end
end

function FlightController:Init()
	if inited then
		return
	end
	inited = true
	-- Полёт в бою отключён: игрок — пеший бессмертный наблюдатель.
	-- Контроллер оставлен на случай ручного Enable в тестах.
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
	if not remotes then
		return
	end
	local ended = remotes:FindFirstChild(RemoteNames.BattleEnded)
	if ended then
		ended.OnClientEvent:Connect(FlightController.Disable)
	end
end

return FlightController
