--[[
	TestTeleportService — быстрый телепорт для тестов в Studio.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Remotes.RemoteNames)
local MapBind = require(ReplicatedStorage.Shared.Map.MapBind)
local Log = require(ReplicatedStorage.Shared.Util.Log)

local TestTeleportService = {}

local function findByZoneType(zoneType: string): BasePart?
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("ZoneType") == zoneType then
			return d
		end
	end
	return nil
end

local function getPoint(key: string): (BasePart?, string?)
	if key == "battle" then
		pcall(function()
			MapBind.EnsureBattlePoints()
		end)
		local folder = workspace:FindFirstChild("MapPoints")
		local p = folder and folder:FindFirstChild("DefenseSpawn1")
		if p and p:IsA("BasePart") then
			return p, "DefenseSpawn1"
		end
		return nil, "DefenseSpawn1"
	elseif key == "enemy" then
		pcall(function()
			MapBind.EnsureBattlePoints()
		end)
		local folder = workspace:FindFirstChild("MapPoints")
		local p = folder and folder:FindFirstChild("EnemySpawn")
		if p and p:IsA("BasePart") then
			return p, "EnemySpawn"
		end
		return nil, "EnemySpawn"
	elseif key == "shop" then
		local p = findByZoneType("Shop")
		if p then
			return p, "Shop"
		end
		-- Fallback: любая часть с именем Shop
		local found = workspace:FindFirstChild("Shop", true)
		if found and found:IsA("BasePart") then
			return found, "Shop"
		end
		if found and found:IsA("Model") then
			local primary = found.PrimaryPart or found:FindFirstChildWhichIsA("BasePart", true)
			if primary then
				return primary, "Shop"
			end
		end
		return nil, "Shop"
	elseif key == "lobby" then
		local folder = workspace:FindFirstChild("MapPoints")
		local ref = folder and folder:FindFirstChild("LobbySpawnRef")
		if ref and ref:IsA("BasePart") then
			return ref, "LobbySpawnRef"
		end
		local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
		if spawn then
			return spawn, "SpawnLocation"
		end
		return nil, "LobbySpawn"
	end
	return nil, key
end

local function teleportPlayer(player: Player, key: string)
	if not RunService:IsStudio() then
		return { success = false, error = "Studio only" }
	end
	local point, label = getPoint(key)
	if not point then
		Log.Write("TestTeleport", "Point missing for " .. tostring(key), "WARN")
		return { success = false, error = "Точка не найдена: " .. tostring(label or key) }
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return { success = false, error = "Нет персонажа" }
	end
	hrp.Anchored = false
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
	hrp.CFrame = point.CFrame + Vector3.new(0, 5, 0)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.PlatformStand = false
		hum.Sit = false
	end
	Log.Write("TestTeleport", player.Name .. " -> " .. tostring(label) .. " (" .. key .. ")")
	return { success = true, destination = label }
end

function TestTeleportService:Init(services)
	if not RunService:IsStudio() then
		return
	end
	local RemoteService = services.RemoteService
	local fn = RemoteService.GetRemote(RemoteNames.TestTeleport)
	if not fn then
		Log.Write("TestTeleport", "Remote TestTeleport missing", "ERROR")
		return
	end
	if fn:IsA("RemoteFunction") then
		fn.OnServerInvoke = function(player, destinationKey)
			local key = tostring(destinationKey or "battle")
			return teleportPlayer(player, key)
		end
		Log.Write("TestTeleport", "Ready (Studio only)")
	else
		Log.Write("TestTeleport", "TestTeleport is not RemoteFunction", "ERROR")
	end
end

return TestTeleportService
