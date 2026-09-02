local CombatVFX = {}

function CombatVFX.PlayMuzzle(origin: Vector3, target: Vector3)
	local attach = Instance.new("Part")
	attach.Anchored = true
	attach.CanCollide = false
	attach.Transparency = 1
	attach.Size = Vector3.new(0.1, 0.1, 0.1)
	attach.Position = origin
	attach.Parent = workspace:FindFirstChild("CombatVFX") or workspace

	local beam = Instance.new("Part")
	beam.Anchored = true
	beam.CanCollide = false
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(255, 220, 120)
	local dist = (target - origin).Magnitude
	beam.Size = Vector3.new(0.08, 0.08, dist)
	beam.CFrame = CFrame.lookAt(origin, target) * CFrame.new(0, 0, -dist / 2)
	beam.Parent = attach
	task.delay(0.08, function()
		attach:Destroy()
	end)
end

function CombatVFX.PlayBlood(pos: Vector3, _scale: number?)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(160, 30, 30)
	p.Size = Vector3.new(0.4, 0.4, 0.4)
	p.Position = pos
	p.Parent = workspace:FindFirstChild("CombatVFX") or workspace
	task.delay(0.25, function()
		p:Destroy()
	end)
end

return CombatVFX
