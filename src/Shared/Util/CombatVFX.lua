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

function CombatVFX.PlayMuzzle(origin: Vector3, target: Vector3)
	local folder = ensureFolder()
	local attach = Instance.new("Part")
	attach.Anchored = true
	attach.CanCollide = false
	attach.Transparency = 1
	attach.Size = Vector3.new(0.1, 0.1, 0.1)
	attach.Position = origin
	attach.Parent = folder

	local beam = Instance.new("Part")
	beam.Anchored = true
	beam.CanCollide = false
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(255, 220, 120)
	local dist = math.max(0.1, (target - origin).Magnitude)
	beam.Size = Vector3.new(0.08, 0.08, dist)
	beam.CFrame = CFrame.lookAt(origin, target) * CFrame.new(0, 0, -dist / 2)
	beam.Parent = attach
	task.delay(0.5, function()
		if attach and attach.Parent then
			attach:Destroy()
		end
	end)
end

function CombatVFX.PlayMiss(origin: Vector3, aim: Vector3)
	local folder = ensureFolder()
	local dir = aim - origin
	if dir.Magnitude < 0.1 then
		dir = Vector3.new(0, 0, -1)
	end
	local missPoint = origin + dir.Unit * math.min(dir.Magnitude * 0.7, 36) + Vector3.new(
		(math.random() - 0.5) * 6,
		1 + (math.random() - 0.5) * 3,
		(math.random() - 0.5) * 6
	)
	local spark = Instance.new("Part")
	spark.Name = "MissSpark"
	spark.Anchored = true
	spark.CanCollide = false
	spark.Material = Enum.Material.Neon
	spark.Color = Color3.fromRGB(220, 230, 255)
	spark.Size = Vector3.new(0.7, 0.7, 0.7)
	spark.Position = missPoint
	spark.Parent = folder
	local trail = Instance.new("Part")
	trail.Anchored = true
	trail.CanCollide = false
	trail.Material = Enum.Material.Neon
	trail.Color = Color3.fromRGB(170, 185, 220)
	trail.Transparency = 0.2
	local dist = math.max(0.1, (missPoint - origin).Magnitude)
	trail.Size = Vector3.new(0.08, 0.08, dist)
	trail.CFrame = CFrame.lookAt(origin, missPoint) * CFrame.new(0, 0, -dist / 2)
	trail.Parent = spark
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
		if spark and spark.Parent then
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
