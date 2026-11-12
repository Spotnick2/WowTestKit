-- Every widget starts with empty _children and _regions lists (WowTestKit #38).
dofile("kit.lua")
Kit.load({ build = "70532", api = Kit.API })

local f = CreateFrame("Frame", nil, UIParent)
eq(type(f._children), "table", "a new frame has a _children list")
eq(type(f._regions), "table", "and a _regions list")
local n = 0
for _ in ipairs(f._children) do n = n + 1 end
for _ in ipairs(f._regions) do n = n + 1 end
eq(n, 0, "ipairs over both works on a frame with none, and finds nothing")
eq(select("#", f:GetChildren()), 0, "GetChildren is empty")
eq(type(WoW.newWidget("Frame")._children), "table", "a stub's newWidget too")

local child = CreateFrame("Frame", nil, f)
local tex = f:CreateTexture()
eq(f._children[1], child, "a child joins the list")
eq(f._regions[1], tex, "a region joins its list")

-- A widget that was never a region (a status bar's fill) joins no list on SetParent.
local bar = CreateFrame("StatusBar", nil, f)
bar:SetStatusBarTexture("x")
local fill = bar:GetStatusBarTexture()
local other = CreateFrame("Frame", nil, UIParent)
fill:SetParent(other)
eq(#other._regions, 0, "a fill moved to another frame isn't listed among its regions")
tex:SetParent(other)
eq(other._regions[1], tex, "a real region moves to its new parent's regions")
eq(#f._regions, 0, "and leaves the old one's")

done("test_lists")
