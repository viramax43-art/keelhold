local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local game = roblox.deserializePlace(fs.readFile("Commission_place (1).rbxl"))
local ws = game:GetService("Workspace")
local function cf(d)
  local ok,c=pcall(function() return d.CFrame end)
  return ok and c
end
print("=== TextLabels Shop/Unit/Armor/Mission ===")
for _, d in ws:GetDescendants() do
  if d.ClassName == "TextLabel" then
    local ok,t=pcall(function() return d.Text end)
    if ok and t and #t>0 and #t<50 then
      local tl=string.lower(t)
      if string.find(tl,"shop") or string.find(tl,"unit") or string.find(tl,"armor") or string.find(tl,"mission") or string.find(tl,"weapon") or string.find(tl,"gun") or string.find(tl,"train") then
        local part=d:FindFirstAncestorWhichIsA("BasePart")
        local c=part and cf(part)
        print(string.format("%q @ %s", t, c and tostring(c.Position) or "?"))
      end
    end
  end
end
print("\n=== Named Shop/Armor/Unit/Mission ===")
for _, d in ws:GetDescendants() do
  local n=string.lower(d.Name)
  if n=="shop" or string.find(n,"armor") or string.find(n,"unit") or string.find(n,"mission") or string.find(n,"weapon") then
    if d:IsA("BasePart") or d:IsA("Model") or d:IsA("Folder") then
      local part=d:IsA("BasePart") and d or d:FindFirstChildWhichIsA("BasePart", true)
      local c=part and cf(part)
      if c then
        local p=c.Position
        if p.X>-3000 and p.X<-1500 then
          print(d.ClassName, d.Name, p)
        end
      end
    end
  end
end