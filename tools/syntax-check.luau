--[[
	Проверка синтаксиса Luau-файлов без Roblox: luau.load компилирует чанк,
	но не выполняет его (require/Instance не вызываются).
	Запуск: lune run tools/syntax-check.luau [пути...]
]]
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local defaultFiles = {
	"src/Shared/Map/MapBind.lua",
	"src/Shared/Util/CombatVFX.lua",
	"src/Server/Services/BotService.lua",
	"src/Server/Services/EnemyService.lua",
	"tools/check-los2.luau",
}

local files = { ... }
if #files == 0 then
	files = defaultFiles
end

local failed = 0
for _, path in ipairs(files) do
	local ok, source = pcall(fs.readFile, path)
	if not ok then
		print(("%-44s READ ERROR: %s"):format(path, tostring(source)))
		failed += 1
		continue
	end
	local compiled, err = pcall(luau.load, source, { debugName = path })
	if compiled then
		print(("%-44s SYNTAX OK"):format(path))
	else
		print(("%-44s SYNTAX ERROR: %s"):format(path, tostring(err)))
		failed += 1
	end
end
print(if failed == 0 then "ALL OK" else ("FAILED: " .. failed))
