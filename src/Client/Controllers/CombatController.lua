local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)
local ClientLog = require(ReplicatedStorage.Shared.Util.ClientLog)

local CombatController = {}
local inBattle = false
local fireRemote = nil

local function getFire()
	if fireRemote then
		return fireRemote
	end
	local r = ReplicatedStorage:FindFirstChild("Remotes")
	fireRemote = r and r:FindFirstChild(RemoteNames.FireWeapon)
	return fireRemote
end

local function resolveTargetId(origin: Vector3?): string?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local mousePos = UserInputService:GetMouseLocation()
	local unitRay = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	local char = Players.LocalPlayer.Character
	if char then
		table.insert(exclude, char)
	end
	local squad = Workspace:FindFirstChild("Squad")
	if squad then
		table.insert(exclude, squad)
	end
	params.FilterDescendantsInstances = exclude

	local result = Workspace:Raycast(unitRay.Origin, unitRay.Direction * 600, params)
	if result and result.Instance then
		local model = result.Instance:FindFirstAncestorOfClass("Model")
		while model do
			local id = model:GetAttribute("EnemyId")
			if typeof(id) == "string" then
				return id
			end
			local parent = model.Parent
			model = parent and parent:FindFirstAncestorOfClass("Model") or nil
		end
		-- also check hit instance's parent chain attributes
		local cur = result.Instance
		for _ = 1, 8 do
			if not cur then
				break
			end
			local id = cur:GetAttribute("EnemyId")
			if typeof(id) == "string" then
				return id
			end
			cur = cur.Parent
		end
	end

	-- Fallback: nearest enemy model under Enemies folder by mouse aim point
	local enemiesFolder = Workspace:FindFirstChild("Enemies")
	if enemiesFolder and origin then
		local aimPoint = unitRay.Origin + unitRay.Direction * 200
		local bestId, bestDist = nil, 40
		for _, m in ipairs(enemiesFolder:GetChildren()) do
			if m:IsA("Model") then
				local id = m:GetAttribute("EnemyId")
				local root = m.PrimaryPart or m:FindFirstChild("HumanoidRootPart")
				if typeof(id) == "string" and root then
					local d = (root.Position - aimPoint).Magnitude
					if d < bestDist then
						bestDist = d
						bestId = id
					end
				end
			end
		end
		return bestId
	end
	return nil
end

function CombatController.FireNearest()
	if not inBattle then
		return
	end
	local fn = getFire()
	if not fn then
		return
	end
	local char = Players.LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local origin = hrp and hrp.Position
	local targetId = resolveTargetId(origin)
	pcall(function()
		fn:InvokeServer(targetId, origin)
	end)
end

local function tryFire()
	CombatController.FireNearest()
end

function CombatController:Init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
	if not remotes then
		return
	end

	local started = remotes:FindFirstChild(RemoteNames.BattleStarted)
	if started then
		started.OnClientEvent:Connect(function()
			inBattle = true
			ClientLog.Write("Combat", "Battle started — fly + fire")
			local char = Players.LocalPlayer.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.WalkSpeed = 24
			end
		end)
	end
	local ended = remotes:FindFirstChild(RemoteNames.BattleEnded)
	if ended then
		ended.OnClientEvent:Connect(function()
			inBattle = false
		end)
	end

	UserInputService.InputBegan:Connect(function(input, gp)
		if gp then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.Space then
			tryFire()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.12)
			if inBattle and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
				tryFire()
			end
		end
	end)
end

return CombatController
