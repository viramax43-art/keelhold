--[[
	CombatVFX — серверные helpers + уведомление клиентов о выстреле.
	Debug-маркер только при BD_DebugCombat; текст — только при BD_DebugCombatText.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

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

function CombatVFX.ShowDebugText(): boolean
	return workspace:GetAttribute("BD_DebugCombatText") == true
end

--[[
	Союзник не должен становиться «приёмником» выстрела: ни блокировать LOS,
	ни быть концом трассера. Собираем модели своих юнитов, чтобы отдать их
	в ignore-лист рейкаста — тогда выстрел считается только по карте.

	units — список записей юнитов ({ Model = <Model> }) или сами модели.
	skipModel — стрелок (он и так исключён вызывающим кодом).
]]
function CombatVFX.CollectModels(units: { any }?, skipModel: Model?): { Instance }
	local out = {}
	if type(units) ~= "table" then
		return out
	end
	for _, unit in ipairs(units) do
		local model = if type(unit) == "table" then unit.Model else unit
		if
			model ~= skipModel
			and typeof(model) == "Instance"
			and model:IsA("Model")
			and model.Parent
		then
			table.insert(out, model)
		end
	end
	return out
end

--[[
	Тела бойцов — не укрытие. На мосту отряд и волна врагов идут плотной толпой,
	поэтому любой выстрел упирался в ЧУЖОЕ тело (не в цель): los=false → chance=0
	→ огонь не работал ни у ботов, ни у врагов, а трассер «прилетал» в союзника.

	Собираем всех бойцов (workspace.Squad + workspace.Enemies), кроме стрелка и
	цели: они уходят в ignore-лист рейкаста, и выстрел оценивается только по цели
	и по карте (реальные укрытия).

	units — необязательный явный список (иначе берём папки Squad/Enemies).
]]
function CombatVFX.CollectOtherCombatants(
	shooterModel: Model?,
	targetModel: Model?,
	units: { any }?
): { Instance }
	local out = {}

	local function add(model)
		if
			model ~= nil
			and model ~= shooterModel
			and model ~= targetModel
			and typeof(model) == "Instance"
			and model:IsA("Model")
			and model.Parent
		then
			table.insert(out, model)
		end
	end

	if type(units) == "table" and #units > 0 then
		for _, unit in ipairs(units) do
			add(if type(unit) == "table" then unit.Model else unit)
		end
		return out
	end

	for _, folderName in ipairs({ "Squad", "Enemies" }) do
		local folder = workspace:FindFirstChild(folderName)
		if folder then
			for _, child in ipairs(folder:GetChildren()) do
				add(child)
			end
		end
	end
	return out
end

-- Дополняет ignore-лист союзниками (сам список создаётся вызывающим кодом)
local function mergeExtraIgnore(
	ignore: { Instance },
	extraIgnore: { Instance }?,
	shooterModel: Model?
): { Instance }
	if type(extraIgnore) ~= "table" then
		return ignore
	end
	for _, inst in ipairs(extraIgnore) do
		if inst ~= shooterModel and typeof(inst) == "Instance" and inst.Parent then
			table.insert(ignore, inst)
		end
	end
	return ignore
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

--[[
	Конечная точка выстрела / проверка LOS.
	Попадание в модель цели — это чистый LOS, не препятствие.
]]
function CombatVFX.TraceShot(
	origin: Vector3,
	aim: Vector3,
	maxRange: number?,
	ignoreList: { Instance }?
): (Vector3, RaycastResult?)
	local range = math.max(1, tonumber(maxRange) or 180)
	local direction = aim - origin
	if direction.Magnitude < 0.05 then
		direction = Vector3.new(0, 0, -1)
	end
	direction = direction.Unit * range

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignoreList or {}
	params.IgnoreWater = true

	local result = workspace:Raycast(origin, direction, params)
	if result then
		return result.Position, result
	end
	return origin + direction, nil
end

function CombatVFX.GetShotEndpoint(
	origin: Vector3,
	aim: Vector3,
	maxRange: number?,
	ignoreList: { Instance }?
): (Vector3, boolean)
	local pos, result = CombatVFX.TraceShot(origin, aim, maxRange, ignoreList)
	return pos, result ~= nil
end

--[[
	Порог «призрачности» (GameConfig.Battle.LosGhostTransparency, по умолчанию 0.7):
	части с Transparency >= порога не считаются укрытием. У заказной карты у
	самой линии обороны стоит почти невидимая панель (0.1x28x101,
	Transparency = 0.8), а поперёк моста — невидимая стена (0.3x70x252,
	Transparency = 1): обе «съедали» выстрелы у самого ствола.
]]
local GHOST_TRANSPARENCY = tonumber(GameConfig.Battle and GameConfig.Battle.LosGhostTransparency) or 0.7

--[[
	true = можно стрелять (воздух или попали в цель); false = укрытие/карта.
	2-е значение — точка попадания, 3-е — блокирующая часть (для дебаг-логов).

	Укрытием считается только стена/проп карты с коллизией и с крутым наклоном.
	Тела бойцов (кроме цели), невидимые и несолидные части, а также «плоские»
	поверхности (настил моста и свод арки) — пропускаются: иначе на этом мосту
	los=false срабатывал на 100% выстрелов и огонь не работал вообще.
]]
function CombatVFX.HasClearLos(
	origin: Vector3,
	aim: Vector3,
	maxRange: number?,
	shooterModel: Model?,
	targetModel: Model?,
	extraIgnore: { Instance }?
): (boolean, Vector3, BasePart?)
	local range = math.max(1, tonumber(maxRange) or 180)
	local direction = aim - origin
	if direction.Magnitude < 0.05 then
		direction = Vector3.new(0, 0, -1)
	end
	local unit = direction.Unit

	local ignore = {}
	if shooterModel then
		table.insert(ignore, shooterModel)
	end
	local vfxFolder = workspace:FindFirstChild("CombatVFX")
	if vfxFolder then
		table.insert(ignore, vfxFolder)
	end
	-- Союзники не препятствие: свой не должен блокировать ствол и ловить трассер
	mergeExtraIgnore(ignore, extraIgnore, shooterModel)
	-- Толпа не препятствие: отряд и враги стоят/идут вплотную друг к другу,
	-- иначе выстрел всегда упирается в чужое тело и огонь не работает
	mergeExtraIgnore(ignore, CombatVFX.CollectOtherCombatants(shooterModel, targetModel), shooterModel)

	local from = origin
	local remaining = range
	-- Несколько шагов: пропускаем непрозрачные для пули поверхности, не считая их стеной
	for _ = 1, 6 do
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = ignore
		params.IgnoreWater = true

		local result = workspace:Raycast(from, unit * remaining, params)
		if not result then
			return true, origin + unit * range, nil
		end

		if targetModel and result.Instance:IsDescendantOf(targetModel) then
			return true, result.Position, nil
		end

		local part = result.Instance
		-- Пол / настил моста и свод арки — не укрытие (стрельба идёт вдоль моста)
		local flatSurface = math.abs(result.Normal.Y) > 0.55
		-- Невидимый или без коллизии декор тоже не укрытие
		local ghostPart = (not part.CanCollide) or part.Transparency >= GHOST_TRANSPARENCY
		if flatSurface or ghostPart then
			table.insert(ignore, part)
			local traveled = (result.Position - from).Magnitude
			from = result.Position + unit * 0.15
			remaining = math.max(0, remaining - traveled - 0.15)
			if remaining < 0.5 then
				return true, result.Position, nil
			end
			continue
		end

		return false, result.Position, part
	end

	return true, origin + unit * range, nil
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

function CombatVFX.PlayMiss(
	origin: Vector3,
	aim: Vector3,
	botModel: Model?,
	weaponType: string?,
	maxRange: number?,
	extraIgnore: { Instance }?
)
	local ignore = if botModel then { botModel } else {}
	local vfxFolder = workspace:FindFirstChild("CombatVFX")
	if vfxFolder then
		table.insert(ignore, vfxFolder)
	end
	-- Промах не должен визуально «упираться» в союзника — считаем только карту
	mergeExtraIgnore(ignore, extraIgnore, botModel)
	-- ...и в тело любого другого бойца (иначе трассер «стреляет по своим»)
	mergeExtraIgnore(ignore, CombatVFX.CollectOtherCombatants(botModel), botModel)
	local missPoint = CombatVFX.GetShotEndpoint(origin, aim, maxRange or (aim - origin).Magnitude, ignore)

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
	spark.Size = Vector3.new(0.4, 0.4, 0.4)
	spark.Position = missPoint
	spark.Parent = folder

	if CombatVFX.ShowDebugText() then
		local bill = Instance.new("BillboardGui")
		bill.Size = UDim2.new(0, 70, 0, 22)
		bill.StudsOffset = Vector3.new(0, 1.2, 0)
		bill.AlwaysOnTop = true
		bill.Parent = spark
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Text = "miss"
		label.TextColor3 = Color3.fromRGB(200, 210, 230)
		label.TextStrokeTransparency = 0.4
		label.Font = Enum.Font.GothamBold
		label.TextSize = 14
		label.Parent = bill
	end

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
