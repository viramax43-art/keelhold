--[[
	CombatVFX — серверные helpers + уведомление клиентов о выстреле бота.
	Визуал вспышки/трассера/отдачи — на клиенте (BotShootFX / BotWeaponAnimation).
	Debug-маркер «промах» только при workspace.BD_DebugCombat = true.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatVFX = {}

local function ensureFolder(): Folder
	local folder = workspace:FindFirstChild("CombatVFX")
	if folder and folder:IsA("Folder") then
		return folder
	end
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "CombatVFX"
	folder.Parent = workspace
	return folder
end

function CombatVFX.ShowDebugMarkers(): boolean
	return workspace:GetAttribute("BD_DebugCombat") == true
end

function CombatVFX.GetMuzzleWorldPosition(model: Model?): Vector3?
	if not model then
		return nil
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Attachment") and d.Name == "Muzzle" then
			return d.WorldPosition
		end
	end
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position + Vector3.new(0, 1.2, 0)
	end
	return nil
end

local function missEndpoint(origin: Vector3, aim: Vector3): Vector3
	local dir = aim - origin
	if dir.Magnitude < 0.1 then
		dir = Vector3.new(0, 0, -1)
	end
	return origin + dir.Unit * math.min(dir.Magnitude * 0.85, 80) + Vector3.new(
		(math.random() - 0.5) * 4,
		0.5 + (math.random() - 0.5) * 2,
		(math.random() - 0.5) * 4
	)
end

function CombatVFX.NotifyShot(opts: {
	Bot: Model,
	WeaponType: string?,
	HitPosition: Vector3,
	Kind: string?,
	Hit: boolean?,
})
	if not RunService:IsServer() then
		return
	end
	local ok, RemoteNames = pcall(function()
		return require(ReplicatedStorage.Shared.Remotes.RemoteNames)
	end)
	if not ok or not RemoteNames then
		return
	end
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local evt = remotes and remotes:FindFirstChild(RemoteNames.CombatVFX)
	if evt and evt:IsA("RemoteEvent") then
		evt:FireAllClients({
			Kind = opts.Kind or "BotShot",
			Bot = opts.Bot,
			WeaponType = opts.WeaponType or opts.Bot:GetAttribute("WeaponType") or "Rifle",
			HitPosition = opts.HitPosition,
			Hit = opts.Hit == true,
		})
	end
end

-- Совместимость: сервер больше не спавнит трассёры в Workspace — только remote
function CombatVFX.PlayMuzzle(origin: Vector3, target: Vector3, botModel: Model?, weaponType: string?)
	if botModel then
		CombatVFX.NotifyShot({
			Bot = botModel,
			WeaponType = weaponType,
			HitPosition = target,
			Kind = if botModel:GetAttribute("TeamRole") == "Enemy" then "EnemyShot" else "BotShot",
			Hit = true,
		})
		return
	end
	-- fallback без модели (редко)
	local folder = ensureFolder()
	local beam = Instance.new("Part")
	beam.Anchored = true
	beam.CanCollide = false
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(255, 220, 120)
	local dist = math.max(0.1, (target - origin).Magnitude)
	beam.Size = Vector3.new(0.08, 0.08, dist)
	beam.CFrame = CFrame.lookAt(origin, target) * CFrame.new(0, 0, -dist / 2)
	beam.Parent = folder
	task.delay(0.08, function()
		if beam.Parent then
			beam:Destroy()
		end
	end)
end

function CombatVFX.PlayMiss(origin: Vector3, aim: Vector3, botModel: Model?, weaponType: string?)
	local missPoint = missEndpoint(origin, aim)
	if botModel then
		CombatVFX.NotifyShot({
			Bot = botModel,
			WeaponType = weaponType,
			HitPosition = missPoint,
			Kind = if botModel:GetAttribute("TeamRole") == "Enemy" then "EnemyShot" else "BotShot",
			Hit = false,
		})
	end

	if not CombatVFX.ShowDebugMarkers() then
		return
	end

	local folder = ensureFolder()
	local spark = Instance.new("Part")
	spark.Name = "MissSpark"
	spark.Anchored = true
	spark.CanCollide = false
	spark.Material = Enum.Material.Neon
	spark.Color = Color3.fromRGB(220, 230, 255)
	spark.Size = Vector3.new(0.55, 0.55, 0.55)
	spark.Position = missPoint
	spark.Parent = folder
	local bill = Instance.new("BillboardGui")
	bill.Size = UDim2.new(0, 70, 0, 22)
	bill.StudsOffset = Vector3.new(0, 1.2, 0)
	bill.AlwaysOnTop = true
	bill.Parent = spark
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "промах"
	label.TextColor3 = Color3.fromRGB(200, 210, 230)
	label.TextStrokeTransparency = 0.4
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.Parent = bill
	task.delay(0.55, function()
		if spark.Parent then
			spark:Destroy()
		end
	end)
end

function CombatVFX.PlayBlood(pos: Vector3, duration: number?)
	local folder = ensureFolder()
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(160, 30, 30)
	p.Size = Vector3.new(0.4, 0.4, 0.4)
	p.Position = pos
	p.Parent = folder
	task.delay(duration or 2, function()
		if p and p.Parent then
			p:Destroy()
		end
	end)
end

return CombatVFX
