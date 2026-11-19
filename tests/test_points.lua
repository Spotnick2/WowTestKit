-- One anchor per point: SetPoint replaces the anchor a frame already has for
-- that point; GetNumPoints, GetPoint and ClearPoint read the same list
-- (WowTestKit #92).
dofile("kit.lua")
Kit.load({ build = "70959", api = Kit.API })

local f = CreateFrame("Frame", nil, UIParent)
local other = CreateFrame("Frame", nil, UIParent)
f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -10)
f:SetPoint("TOPLEFT", other, "BOTTOMLEFT", 0, -4)
eq(f:GetNumPoints(), 1, "a second TOPLEFT replaces the first")
local p, rel, relP, x, y = f:GetPoint(1)
check(p == "TOPLEFT" and rel == other and relP == "BOTTOMLEFT" and x == 0 and y == -4,
    "GetPoint reads the new anchor")
f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT")
eq(f:GetNumPoints(), 2, "another point is another anchor")
f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 1, 2)
eq(f:GetNumPoints(), 2, "re-anchoring a point keeps the count")
eq(f:GetPoint(1), "BOTTOMRIGHT", "the replaced anchor moves to the end")
local _, _, _, x2, y2 = f:GetPoint(2)
check(x2 == 1 and y2 == 2, "with its new offsets")

-- GlassRaidFrames' case: a header re-lays its children each pass, with no
-- ClearAllPoints between (SecureGroupHeaders.lua's configureChildren).
local child = CreateFrame("Button", nil, UIParent)
for pass = 1, 3 do child:SetPoint("TOP", UIParent, "TOP", 0, -20 * pass) end
eq(child:GetNumPoints(), 1, "a child re-laid three times has one anchor")
eq(select(5, child:GetPoint(1)), -60, "the last pass's")

-- ClearPoint takes one point off; ClearAllPoints all of them.
f:ClearPoint("BOTTOMRIGHT")
eq(f:GetNumPoints(), 1, "ClearPoint removes that point's anchor")
eq(f:GetPoint(1), "TOPLEFT", "and leaves the others")
f:ClearPoint("CENTER")
eq(f:GetNumPoints(), 1, "a point the frame doesn't have is ignored")
f:ClearAllPoints()
eq(f:GetNumPoints(), 0, "ClearAllPoints removes every anchor")
eq(f:GetPoint(1), nil, "GetPoint then reads nothing")

-- SetAllPoints is one point here, replaced the same way.
f:SetAllPoints(UIParent)
f:SetAllPoints(other)
eq(f:GetNumPoints(), 1, "a second SetAllPoints replaces the first")
eq(select(2, f:GetPoint(1)), other, "to the new frame")

-- A secure handle's SetPoint replaces too.
WoW.templates.KitSecureTemplate = function(w) w._protected = true end
local header = CreateFrame("Frame", "KitHeader", UIParent, "KitSecureTemplate")
local ring = CreateFrame("Frame", "KitRing", header, "KitSecureTemplate")
local h = WoW.handleOf(ring)
h:SetPoint("CENTER", "$parent", "CENTER", 5, 5)
h:SetPoint("CENTER", "$parent", "CENTER", 7, 7)
eq(ring:GetNumPoints(), 1, "a handle's SetPoint replaces the point's anchor")
eq(select(4, ring:GetPoint(1)), 7, "with the new one")

-- In combat a protected frame refuses SetPoint: its anchor stays.
WoW.combat = true
ring:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
eq(select(2, ring:GetPoint(1)), header, "a refused SetPoint replaces nothing")
WoW.combat = false
WoW.blocked = {}

done("test_points")
