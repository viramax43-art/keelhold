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
