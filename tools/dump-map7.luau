local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local game = roblox.deserializePlace(fs.readFile("Commission_place (1).rbxl"))
local ws = game:GetService("Workspace")
local function cf(d)
  local ok,c=pcall(function() return d.CFrame end)
  return ok and c
end
for _, name in {"Pubg Air Drop", "WoodSign", "base_model_of_unit"} do
  print("==", name)
  for _, d in ws:GetDescendants() do
    if d.Name == name then
      local part = d:IsA("BasePart") and d or d:FindFirstChildWhichIsA("BasePart", true)
      local c = part and cf(part)
      print(d.ClassName, d:GetFullName(), c and c.Position)
    end
  end
end