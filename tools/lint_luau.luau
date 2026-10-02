--[[
	tools/lint_luau.luau — syntax-check every Luau module without Roblox Studio.

	Usage (Lune 0.10+):
		lune run tools/lint_luau.luau            -- checks src/
		lune run tools/lint_luau.luau src map    -- checks the given folders/files

	`luau.load` compiles a chunk but never executes it, so `script`, `game` and
	`require` are parsed, not resolved: this catches real syntax errors
	(missing `end`, stray commas, broken strings) and ignores runtime concerns.
	Exit code 1 when at least one file fails.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local roots = process.args
if #roots == 0 then
	roots = { "src" }
end

local checked, failed = 0, 0

local function check(path: string)
	checked += 1
	local ok, err = pcall(luau.load, fs.readFile(path), { debugName = path })
	if not ok then
		failed += 1
		print(string.format("FAIL %s\n  %s", path, tostring(err)))
	end
end

local function walk(path: string)
	if fs.isDir(path) then
		for _, entry in ipairs(fs.readDir(path)) do
			local name = if typeof(entry) == "table" then entry.name else entry
			walk(path .. "/" .. name)
		end
		return
	end
	if path:match("%.lua$") then
		check(path)
	end
end

for _, root in ipairs(roots) do
	if fs.isFile(root) then
		check(root)
	else
		walk(root)
	end
end

print(string.format("checked %d Luau file(s), %d syntax error(s)", checked, failed))
if failed > 0 then
	process.exit(1)
end
