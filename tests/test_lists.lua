-- Every widget starts with empty _children and _regions lists (WowTestKit #38),
-- and a frame keeps its mask textures in _maskTextures (#82).
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

-- A frame's mask textures, in creation order (WowTestKit #82), apart from
-- its regions: whether the client's GetRegions lists them is unmeasured.
local w = CreateFrame("Frame", nil, UIParent)
eq(#w._maskTextures, 0, "a new frame has an empty _maskTextures list")
local wt = w:CreateTexture()
local m1, m2 = w:CreateMaskTexture(), w:CreateMaskTexture()
check(w._maskTextures[1] == m1 and w._maskTextures[2] == m2 and #w._maskTextures == 2,
    "CreateMaskTexture's masks join it, in creation order")
eq(select("#", w:GetRegions()), 1, "GetRegions returns the texture, not the masks")
wt:AddMaskTexture(m2)
check(wt._masks[1] == m2 and #w._maskTextures == 2, "a texture's own masks (AddMaskTexture) are another list")
local w2 = CreateFrame("Frame", nil, UIParent)
m1:SetParent(w2)
eq(w2._maskTextures[1], m1, "a mask moved to another frame joins its masks")
check(#w._maskTextures == 1 and w._maskTextures[1] == m2, "and leaves the old one's")
eq(#w2._regions, 0, "not its regions")
local own = {}
WoW.Methods.CreateMaskTexture(own)
eq(#own._maskTextures, 1, "a stub's own widget table gets the list on its first mask")

done("test_lists")
