--[[
	Format — сокращение больших чисел (1.2K / 3.4M / 5.6B).
	Идея из slime-factory-tycoon (Format.luau), MIT.
	С ростом экономики сырые числа в HUD/магазине нечитаемы — форматируем.
]]

local Format = {}

local UNITS = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp" }

-- 1234 -> "1.2K", 999 -> "999"
function Format.Number(value: number): string
	if value ~= value or value == math.huge or value == -math.huge then
		return "0"
	end
	local negative = value < 0
	value = math.abs(value)
	if value < 1000 then
		return (negative and "-" or "") .. tostring(math.floor(value))
	end
	local tier = math.min(math.floor(math.log(value, 1000)), #UNITS - 1)
	local scaled = value / (1000 ^ tier)
	local text
	if scaled >= 100 then
		text = string.format("%.0f", scaled)
	elseif scaled >= 10 then
		text = string.format("%.1f", scaled)
	else
		text = string.format("%.2f", scaled)
	end
	-- убрать хвостовые нули: "1.20" -> "1.2", "3.00" -> "3"
	text = text:gsub("(%.%d-)0+$", "%1"):gsub("%.$", "")
	return (negative and "-" or "") .. text .. UNITS[tier + 1]
end

-- Для цен: всегда компактно + точность до 3 значащих цифр
function Format.Price(value: number): string
	return Format.Number(value)
end

return Format
